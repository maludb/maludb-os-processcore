-- 006_ledger.sql — the inventory ledger, balances, interlocks, transfers, adjustments, counts. Every movement is one
-- signed row against (item, lot, location) in the item's base unit, with its weight beside it (D4). The ledger is
-- posted to from receiving on. No tax state here: the cidery's bonded/tax-paid interlock was the beverage's.
SET search_path = app, public;

CREATE TABLE app.inventory_transactions (
    id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    group_id          uuid NOT NULL DEFAULT gen_random_uuid(),
    txn_type          text NOT NULL CHECK (txn_type IN (
                          'receipt','issue','transfer_out','transfer_in','adjustment','count_correction',
                          'production_output','packaging_output','shipment','return','scrap_out','reversal')),
    item_id           bigint NOT NULL REFERENCES app.items(id),
    lot_id            bigint NOT NULL REFERENCES app.lots(id),
    location_id       bigint NOT NULL REFERENCES app.locations(id),
    site_id           bigint NOT NULL REFERENCES app.sites(id),
    qty_base          numeric(18,4) NOT NULL CHECK (qty_base <> 0),
    weight_kg         numeric(14,3) NOT NULL DEFAULT 0,             -- signed like qty; from the lot's unit weight when not given
    unit_cost_base    numeric(18,6) NOT NULL DEFAULT 0,
    counterparty_kind text NOT NULL DEFAULT 'none' CHECK (counterparty_kind IN (
                          'none','location','run','packaging_run','supplier','customer','disposal')),
    counterparty_id   bigint,
    reason_code_id    bigint REFERENCES app.reason_codes(id),
    report_category   text NOT NULL DEFAULT 'none' CHECK (report_category IN (
                          'none','received','produced','consumed','packaged','shipped','returned','scrapped',
                          'process_loss','exceptional_loss','damage','destroyed','shortage','gain','correction')),
    reference_kind    text NOT NULL CHECK (reference_kind IN (
                          'goods_receipt','transfer','adjustment','count','run_input','run_output','run_consumable',
                          'packaging_run','shipment','return','loss_event','co_product_disposition','reversal','opening')),
    reference_id      bigint NOT NULL,
    reverses_id       bigint REFERENCES app.inventory_transactions(id),
    idempotency_key   text NOT NULL UNIQUE,
    occurred_at       timestamptz NOT NULL,
    posted_at         timestamptz NOT NULL DEFAULT now(),
    actor_id          bigint REFERENCES app.users(id),
    note              text
);
CREATE INDEX inventory_transactions_lot_idx      ON app.inventory_transactions (lot_id, occurred_at);
CREATE INDEX inventory_transactions_item_idx     ON app.inventory_transactions (item_id, occurred_at);
CREATE INDEX inventory_transactions_location_idx ON app.inventory_transactions (location_id, occurred_at);
CREATE INDEX inventory_transactions_ref_idx      ON app.inventory_transactions (reference_kind, reference_id);
CREATE INDEX inventory_transactions_group_idx    ON app.inventory_transactions (group_id);
CREATE INDEX inventory_transactions_period_idx   ON app.inventory_transactions (site_id, occurred_at, report_category);
CREATE TRIGGER inventory_transactions_immutable BEFORE UPDATE OR DELETE ON app.inventory_transactions
    FOR EACH ROW EXECUTE FUNCTION app.forbid_change();

-- Materialized balances, maintained by trigger, recomputable --------------------------
CREATE TABLE app.inventory_balances (
    item_id          bigint NOT NULL REFERENCES app.items(id),
    lot_id           bigint NOT NULL REFERENCES app.lots(id),
    location_id      bigint NOT NULL REFERENCES app.locations(id),
    qty_on_hand      numeric(18,4) NOT NULL DEFAULT 0,
    weight_on_hand_kg numeric(14,3) NOT NULL DEFAULT 0,
    qty_allocated    numeric(18,4) NOT NULL DEFAULT 0,
    updated_at       timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (item_id, lot_id, location_id)
);
CREATE INDEX inventory_balances_location_idx ON app.inventory_balances (location_id) WHERE qty_on_hand <> 0;

CREATE OR REPLACE FUNCTION app.ledger_before_insert() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_lot     app.lots%ROWTYPE;
    v_loc     app.locations%ROWTYPE;
    v_on_hand numeric(18,4);
BEGIN
    SELECT * INTO v_lot FROM app.lots WHERE id = NEW.lot_id;
    SELECT * INTO v_loc FROM app.locations WHERE id = NEW.location_id;

    IF v_lot.item_id <> NEW.item_id THEN
        RAISE EXCEPTION 'lot % belongs to item %, not %', v_lot.lot_number, v_lot.item_id, NEW.item_id;
    END IF;

    -- Snapshot the site from the location; derive the weight from the lot when not given.
    NEW.site_id := v_loc.site_id;
    IF NEW.weight_kg = 0 AND v_lot.unit_weight_kg IS NOT NULL THEN
        NEW.weight_kg := round(NEW.qty_base * v_lot.unit_weight_kg, 3);
    END IF;

    -- Interlock 1: nothing leaves a lot that is not released, except a destruction/adjustment/reversal/transfer
    -- (moving a quarantined coil to another bay is fine).
    IF NEW.qty_base < 0 AND v_lot.quality_status <> 'released'
       AND NEW.txn_type IN ('issue','packaging_output','shipment') THEN
        RAISE EXCEPTION 'lot % is % and cannot be used or shipped', v_lot.lot_number, v_lot.quality_status
            USING ERRCODE = 'check_violation';
    END IF;

    -- Interlock 2: no negative stock unless the location allows it.
    SELECT COALESCE(qty_on_hand, 0) INTO v_on_hand FROM app.inventory_balances
     WHERE item_id = NEW.item_id AND lot_id = NEW.lot_id AND location_id = NEW.location_id;
    IF COALESCE(v_on_hand, 0) + NEW.qty_base < 0 AND NOT v_loc.allow_negative THEN
        RAISE EXCEPTION 'insufficient stock of lot % at %: on hand %, requested %',
            v_lot.lot_number, v_loc.name, COALESCE(v_on_hand, 0), NEW.qty_base
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION app.ledger_after_insert() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO app.inventory_balances (item_id, lot_id, location_id, qty_on_hand, weight_on_hand_kg, updated_at)
    VALUES (NEW.item_id, NEW.lot_id, NEW.location_id, NEW.qty_base, NEW.weight_kg, now())
    ON CONFLICT (item_id, lot_id, location_id)
    DO UPDATE SET qty_on_hand = app.inventory_balances.qty_on_hand + EXCLUDED.qty_on_hand,
                  weight_on_hand_kg = app.inventory_balances.weight_on_hand_kg + EXCLUDED.weight_on_hand_kg,
                  updated_at = now();
    RETURN NULL;
END $$;

CREATE TRIGGER inventory_transactions_before BEFORE INSERT ON app.inventory_transactions
    FOR EACH ROW EXECUTE FUNCTION app.ledger_before_insert();
CREATE TRIGGER inventory_transactions_after AFTER INSERT ON app.inventory_transactions
    FOR EACH ROW EXECUTE FUNCTION app.ledger_after_insert();

CREATE OR REPLACE FUNCTION app.rebuild_inventory_balances() RETURNS void
LANGUAGE sql AS $$
    UPDATE app.inventory_balances SET qty_on_hand = 0, weight_on_hand_kg = 0;
    INSERT INTO app.inventory_balances (item_id, lot_id, location_id, qty_on_hand, weight_on_hand_kg, updated_at)
    SELECT item_id, lot_id, location_id, sum(qty_base), sum(weight_kg), now()
      FROM app.inventory_transactions GROUP BY 1,2,3
    ON CONFLICT (item_id, lot_id, location_id)
    DO UPDATE SET qty_on_hand = EXCLUDED.qty_on_hand, weight_on_hand_kg = EXCLUDED.weight_on_hand_kg, updated_at = now();
$$;

-- Documents the screens work with --------------------------------------------------
CREATE TABLE app.inventory_transfers (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    number           text NOT NULL UNIQUE,
    from_location_id bigint NOT NULL REFERENCES app.locations(id),
    to_location_id   bigint NOT NULL REFERENCES app.locations(id),
    status           text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','posted','cancelled')),
    transferred_at   timestamptz NOT NULL DEFAULT now(),
    notes            text,
    created_by       bigint REFERENCES app.users(id),
    posted_by        bigint REFERENCES app.users(id),
    posted_at        timestamptz,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    CHECK (from_location_id <> to_location_id)
);
CREATE TRIGGER inventory_transfers_touch BEFORE UPDATE ON app.inventory_transfers FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

CREATE TABLE app.inventory_transfer_lines (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    transfer_id bigint NOT NULL REFERENCES app.inventory_transfers(id) ON DELETE CASCADE,
    item_id     bigint NOT NULL REFERENCES app.items(id),
    lot_id      bigint NOT NULL REFERENCES app.lots(id),
    qty_base    numeric(18,4) NOT NULL CHECK (qty_base > 0)
);

CREATE TABLE app.inventory_adjustments (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    number         text NOT NULL UNIQUE,
    location_id    bigint NOT NULL REFERENCES app.locations(id),
    reason_code_id bigint NOT NULL REFERENCES app.reason_codes(id),
    status         text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','pending_approval','posted','cancelled')),
    adjusted_at    timestamptz NOT NULL DEFAULT now(),
    notes          text,
    created_by     bigint REFERENCES app.users(id),
    approved_by    bigint REFERENCES app.users(id),
    approved_at    timestamptz,
    posted_by      bigint REFERENCES app.users(id),
    posted_at      timestamptz,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER inventory_adjustments_touch BEFORE UPDATE ON app.inventory_adjustments FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

CREATE TABLE app.inventory_adjustment_lines (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    adjustment_id  bigint NOT NULL REFERENCES app.inventory_adjustments(id) ON DELETE CASCADE,
    item_id        bigint NOT NULL REFERENCES app.items(id),
    lot_id         bigint NOT NULL REFERENCES app.lots(id),
    qty_delta_base numeric(18,4) NOT NULL CHECK (qty_delta_base <> 0),
    weight_delta_kg numeric(14,3),
    unit_cost_base numeric(18,6),
    note           text
);

CREATE TABLE app.inventory_counts (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    number       text NOT NULL UNIQUE,
    location_id  bigint NOT NULL REFERENCES app.locations(id),
    kind         text NOT NULL DEFAULT 'cycle' CHECK (kind IN ('cycle','physical')),
    status       text NOT NULL DEFAULT 'open' CHECK (status IN ('open','counting','review','approved','cancelled')),
    started_at   timestamptz NOT NULL DEFAULT now(),
    started_by   bigint REFERENCES app.users(id),
    completed_at timestamptz,
    approved_by  bigint REFERENCES app.users(id),
    approved_at  timestamptz,
    notes        text,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER inventory_counts_touch BEFORE UPDATE ON app.inventory_counts FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

CREATE TABLE app.inventory_count_lines (
    id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    count_id          bigint NOT NULL REFERENCES app.inventory_counts(id) ON DELETE CASCADE,
    item_id           bigint NOT NULL REFERENCES app.items(id),
    lot_id            bigint NOT NULL REFERENCES app.lots(id),
    qty_expected_base numeric(18,4) NOT NULL,
    qty_counted_base  numeric(18,4),
    weight_counted_kg numeric(14,3),
    variance_base     numeric(18,4) GENERATED ALWAYS AS (qty_counted_base - qty_expected_base) STORED,
    counted_by        bigint REFERENCES app.users(id),
    counted_at        timestamptz,
    note              text,
    UNIQUE (count_id, item_id, lot_id)
);
