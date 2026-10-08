-- 005_purchasing_receiving.sql — purchase orders, receipts, lots, lot attributes, weigh tickets, certificates,
-- release decisions. The receiving slice. A receipt line is one lot; a serialized item (a coil) is one line per unit.
SET search_path = app, public;

CREATE TABLE app.purchase_orders (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    number       text NOT NULL UNIQUE,
    supplier_id  bigint NOT NULL REFERENCES app.suppliers(id),
    site_id      bigint NOT NULL REFERENCES app.sites(id),
    status       text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','open','partial','closed','closed_short','cancelled')),
    ordered_on   date,
    expected_on  date,
    notes        text,
    approved_by  bigint REFERENCES app.users(id),
    approved_at  timestamptz,
    created_by   bigint REFERENCES app.users(id),
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX purchase_orders_status_idx ON app.purchase_orders (status, expected_on);
CREATE TRIGGER purchase_orders_touch BEFORE UPDATE ON app.purchase_orders FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

CREATE TABLE app.purchase_order_lines (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    purchase_order_id    bigint NOT NULL REFERENCES app.purchase_orders(id) ON DELETE CASCADE,
    line_no              int NOT NULL,
    item_id              bigint NOT NULL REFERENCES app.items(id),
    qty_ordered          numeric(18,4) NOT NULL CHECK (qty_ordered > 0),   -- in purchase unit
    purchase_unit_code   text NOT NULL,
    to_base_factor       numeric(18,8) NOT NULL,
    qty_ordered_base     numeric(18,4) GENERATED ALWAYS AS (qty_ordered * to_base_factor) STORED,
    weight_kg_ordered    numeric(14,3),                                    -- when the base is a count and the buy is by weight
    unit_price           numeric(18,4) NOT NULL DEFAULT 0,                 -- per purchase unit
    expected_on          date,
    qty_received_base    numeric(18,4) NOT NULL DEFAULT 0,
    weight_kg_received   numeric(14,3) NOT NULL DEFAULT 0,
    status               text NOT NULL DEFAULT 'open' CHECK (status IN ('open','partial','received','closed_short','cancelled')),
    close_reason_code_id bigint REFERENCES app.reason_codes(id),
    notes                text,
    UNIQUE (purchase_order_id, line_no)
);

CREATE TABLE app.goods_receipts (
    id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    number                text NOT NULL UNIQUE,
    site_id               bigint NOT NULL REFERENCES app.sites(id),
    supplier_id           bigint NOT NULL REFERENCES app.suppliers(id),
    purchase_order_id     bigint REFERENCES app.purchase_orders(id),           -- NULL = unplanned receipt
    received_at           timestamptz NOT NULL DEFAULT now(),
    receiving_location_id bigint NOT NULL REFERENCES app.locations(id),
    status                text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','posted','cancelled')),
    delivery_note_ref     text,                                              -- the carrier's or mill's document
    carrier               text,
    notes                 text,
    received_by           bigint REFERENCES app.users(id),
    posted_by             bigint REFERENCES app.users(id),
    posted_at             timestamptz,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX goods_receipts_received_idx ON app.goods_receipts (received_at DESC);
CREATE TRIGGER goods_receipts_touch BEFORE UPDATE ON app.goods_receipts FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

-- Lots: one received or produced quantity of an item. A lot's source is a receipt line, a run output, a packaging run,
-- an adjustment or an opening balance (source_kind/source_id, not a hard FK — the sources are created in different
-- files). weight_kg is the lot's weight as received or produced; unit_weight_kg = weight per base unit, 1 for a lot
-- whose base unit is kg, the scale or theoretical weight per piece otherwise — the ledger carries weight from it (D4).
CREATE TABLE app.lots (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lot_number          text NOT NULL UNIQUE,
    item_id             bigint NOT NULL REFERENCES app.items(id),
    site_id             bigint NOT NULL REFERENCES app.sites(id),
    supplier_lot_number text,                                                -- the mill's coil id, the vendor's lot
    supplier_id         bigint REFERENCES app.suppliers(id),
    received_on         date,
    produced_on         date,
    expires_on          date,
    quality_status      text NOT NULL DEFAULT 'released' CHECK (quality_status IN ('quarantine','hold','released','rejected')),
    unit_cost_base      numeric(18,6) NOT NULL DEFAULT 0,                    -- per base unit
    qty_initial_base    numeric(18,4),                                       -- as received or produced
    weight_kg           numeric(14,3),                                       -- as received or produced
    unit_weight_kg      numeric(14,6),                                       -- per base unit (1 when the base unit is kg)
    source_kind         text NOT NULL CHECK (source_kind IN ('receipt_line','run','packaging_run','adjustment','opening','split')),
    source_id           bigint,
    notes               text,
    created_by          bigint REFERENCES app.users(id),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX lots_item_idx    ON app.lots (item_id, quality_status);
CREATE INDEX lots_expires_idx ON app.lots (expires_on) WHERE expires_on IS NOT NULL;
CREATE INDEX lots_source_idx  ON app.lots (source_kind, source_id);
CREATE INDEX lots_supplier_lot_idx ON app.lots (supplier_lot_number) WHERE supplier_lot_number IS NOT NULL;
CREATE TRIGGER lots_touch BEFORE UPDATE ON app.lots FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

-- A lot of an item whose base unit is kg weighs what it holds.
CREATE OR REPLACE FUNCTION app.lots_default_unit_weight() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_unit text; v_item_unit_weight numeric;
BEGIN
    SELECT base_unit_code, unit_weight_kg INTO v_unit, v_item_unit_weight FROM app.items WHERE id = NEW.item_id;
    IF NEW.unit_weight_kg IS NULL THEN
        IF v_unit = 'kg' THEN
            NEW.unit_weight_kg := 1;
        ELSIF NEW.weight_kg IS NOT NULL AND COALESCE(NEW.qty_initial_base, 0) > 0 THEN
            NEW.unit_weight_kg := NEW.weight_kg / NEW.qty_initial_base;
        ELSE
            NEW.unit_weight_kg := v_item_unit_weight;
        END IF;
    END IF;
    IF NEW.weight_kg IS NULL AND NEW.unit_weight_kg IS NOT NULL AND NEW.qty_initial_base IS NOT NULL THEN
        NEW.weight_kg := round(NEW.unit_weight_kg * NEW.qty_initial_base, 3);
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER lots_default_unit_weight BEFORE INSERT OR UPDATE OF weight_kg, unit_weight_kg, qty_initial_base ON app.lots
    FOR EACH ROW EXECUTE FUNCTION app.lots_default_unit_weight();

-- Typed attributes of a lot: the dictionary's keys (heat, grade, thickness_in, …) and any certificate value. Free keys
-- are admitted so a certificate's extra values survive; the screens show the dictionary's first.
CREATE TABLE app.lot_attributes (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lot_id      bigint NOT NULL REFERENCES app.lots(id) ON DELETE CASCADE,
    key         text NOT NULL CHECK (key ~ '^[a-z][a-z0-9_]{1,39}$'),
    value_num   numeric(18,6),
    value_text  text,
    unit_code   text,
    source      text NOT NULL DEFAULT 'manual' CHECK (source IN ('manual','certificate','weigh_ticket','reading','run','packaging_run','inherited','derived')),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    recorded_by bigint REFERENCES app.users(id),
    UNIQUE (lot_id, key),
    CHECK (value_num IS NOT NULL OR value_text IS NOT NULL)
);

CREATE OR REPLACE FUNCTION app.lot_attribute_num(p_lot_id bigint, p_key text) RETURNS numeric
LANGUAGE sql STABLE AS $$
    SELECT value_num FROM app.lot_attributes WHERE lot_id = p_lot_id AND key = p_key
$$;
CREATE OR REPLACE FUNCTION app.lot_attribute_text(p_lot_id bigint, p_key text) RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(value_text, value_num::text) FROM app.lot_attributes WHERE lot_id = p_lot_id AND key = p_key
$$;

-- Copies every attribute of the dictionary the item class carries from the item onto the lot, then the inheritable
-- ones from a parent lot (a run's primary input), then explicit values — later ones win. Used by receipts and runs.
CREATE OR REPLACE FUNCTION app.lot_attributes_fill(p_lot_id bigint, p_parent_lot_id bigint DEFAULT NULL, p_explicit jsonb DEFAULT '{}'::jsonb,
                                                   p_source text DEFAULT 'derived', p_by bigint DEFAULT NULL)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE v_item bigint; v_class text; n int := 0; r record; v_def app.attribute_definitions%ROWTYPE; v_key text; v_val jsonb;
BEGIN
    SELECT item_id INTO v_item FROM app.lots WHERE id = p_lot_id;
    SELECT item_class INTO v_class FROM app.items WHERE id = v_item;
    -- 1. the item's own values (what the SKU is)
    FOR r IN SELECT v.attribute_key, v.value_num, v.value_text, d.unit_code
               FROM app.item_attribute_values v JOIN app.attribute_definitions d ON d.key = v.attribute_key
              WHERE v.item_id = v_item AND d.on_lots LOOP
        INSERT INTO app.lot_attributes (lot_id, key, value_num, value_text, unit_code, source, recorded_by)
        VALUES (p_lot_id, r.attribute_key, r.value_num, r.value_text, r.unit_code, 'derived', p_by)
        ON CONFLICT (lot_id, key) DO UPDATE SET value_num = EXCLUDED.value_num, value_text = EXCLUDED.value_text, unit_code = EXCLUDED.unit_code,
                                                source = 'derived', recorded_at = now(), recorded_by = p_by;
        n := n + 1;
    END LOOP;
    -- 2. inherited from the parent lot (heat, grade, coating… — the dictionary says which)
    IF p_parent_lot_id IS NOT NULL THEN
        FOR r IN SELECT a.key, a.value_num, a.value_text, a.unit_code
                   FROM app.lot_attributes a JOIN app.attribute_definitions d ON d.key = a.key
                  WHERE a.lot_id = p_parent_lot_id AND d.inherit AND d.on_lots LOOP
            INSERT INTO app.lot_attributes (lot_id, key, value_num, value_text, unit_code, source, recorded_by)
            VALUES (p_lot_id, r.key, r.value_num, r.value_text, r.unit_code, 'inherited', p_by)
            ON CONFLICT (lot_id, key) DO UPDATE SET value_num = EXCLUDED.value_num, value_text = EXCLUDED.value_text, unit_code = EXCLUDED.unit_code,
                                                    source = 'inherited', recorded_at = now(), recorded_by = p_by;
            n := n + 1;
        END LOOP;
    END IF;
    -- 3. explicit values: {"heat": "7A1234", "width_in": 48}
    FOR v_key, v_val IN SELECT * FROM jsonb_each(COALESCE(p_explicit, '{}'::jsonb)) LOOP
        IF v_val IS NULL OR jsonb_typeof(v_val) = 'null' THEN CONTINUE; END IF;
        SELECT * INTO v_def FROM app.attribute_definitions WHERE key = v_key;
        IF jsonb_typeof(v_val) = 'number' OR (v_def.kind = 'num' AND (v_val #>> '{}') ~ '^-?[0-9]+(\.[0-9]+)?$') THEN
            INSERT INTO app.lot_attributes (lot_id, key, value_num, unit_code, source, recorded_by)
            VALUES (p_lot_id, v_key, (v_val #>> '{}')::numeric, v_def.unit_code, p_source, p_by)
            ON CONFLICT (lot_id, key) DO UPDATE SET value_num = EXCLUDED.value_num, value_text = NULL, unit_code = EXCLUDED.unit_code,
                                                    source = p_source, recorded_at = now(), recorded_by = p_by;
        ELSE
            INSERT INTO app.lot_attributes (lot_id, key, value_text, source, recorded_by)
            VALUES (p_lot_id, v_key, v_val #>> '{}', p_source, p_by)
            ON CONFLICT (lot_id, key) DO UPDATE SET value_text = EXCLUDED.value_text, value_num = NULL,
                                                    source = p_source, recorded_at = now(), recorded_by = p_by;
        END IF;
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;

CREATE TABLE app.goods_receipt_lines (
    id                     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    goods_receipt_id       bigint NOT NULL REFERENCES app.goods_receipts(id) ON DELETE CASCADE,
    line_no                int NOT NULL,
    purchase_order_line_id bigint REFERENCES app.purchase_order_lines(id),
    item_id                bigint NOT NULL REFERENCES app.items(id),
    qty_received           numeric(18,4) NOT NULL CHECK (qty_received >= 0),  -- in purchase unit
    purchase_unit_code     text NOT NULL,
    to_base_factor         numeric(18,8) NOT NULL,
    qty_base               numeric(18,4) NOT NULL,                             -- catch-weight: from the weigh ticket
    weight_kg              numeric(14,3),                                      -- the ticket's net, or declared
    unit_cost_base         numeric(18,6) NOT NULL DEFAULT 0,
    discrepancy_kind       text NOT NULL DEFAULT 'none' CHECK (discrepancy_kind IN ('none','short','over','damaged','substituted')),
    discrepancy_note       text,
    supplier_lot_number    text,                                               -- the coil id, the vendor lot
    attributes             jsonb NOT NULL DEFAULT '{}'::jsonb,                 -- explicit lot attributes (heat, grade, …) written at post
    expires_on             date,
    lot_id                 bigint REFERENCES app.lots(id),                     -- created at post
    putaway_location_id    bigint REFERENCES app.locations(id),
    notes                  text,
    UNIQUE (goods_receipt_id, line_no)
);
CREATE INDEX goods_receipt_lines_po_line_idx ON app.goods_receipt_lines (purchase_order_line_id);

-- A scale ticket on a receipt line: gross, tare, net. Weights stored in kg, entered in the display unit.
CREATE TABLE app.weigh_tickets (
    id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    goods_receipt_line_id bigint NOT NULL UNIQUE REFERENCES app.goods_receipt_lines(id) ON DELETE CASCADE,
    ticket_number         text,
    scale                 text,
    gross_kg              numeric(14,3) NOT NULL CHECK (gross_kg >= 0),
    tare_kg               numeric(14,3) NOT NULL DEFAULT 0 CHECK (tare_kg >= 0),
    net_kg                numeric(14,3) GENERATED ALWAYS AS (gross_kg - tare_kg) STORED,
    pieces                int,
    condition_note        text,
    weighed_at            timestamptz NOT NULL DEFAULT now(),
    weighed_by            bigint REFERENCES app.users(id)
);

-- Certificates: a mill test report, a certificate of analysis, a certificate of conformance — the values parsed
-- from the document (the file is an attachment); key ones copied to lot_attributes with source 'certificate'.
CREATE TABLE app.certificates (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lot_id        bigint NOT NULL REFERENCES app.lots(id) ON DELETE CASCADE,
    kind          text NOT NULL DEFAULT 'mtr' CHECK (kind IN ('mtr','coa','conformance','other')),
    number        text,
    issuer        text,
    heat_number   text,
    issued_on     date,
    attachment_id bigint REFERENCES app.attachments(id),
    values_json   jsonb NOT NULL DEFAULT '{}'::jsonb,
    recorded_by   bigint REFERENCES app.users(id),
    created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX certificates_lot_idx  ON app.certificates (lot_id);
CREATE INDEX certificates_heat_idx ON app.certificates (heat_number) WHERE heat_number IS NOT NULL;

-- Quality status changes on lots.
CREATE TABLE app.release_decisions (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    target_kind    text NOT NULL DEFAULT 'lot' CHECK (target_kind = 'lot'),
    target_id      bigint NOT NULL,
    from_status    text NOT NULL,
    to_status      text NOT NULL,
    basis          text NOT NULL CHECK (basis IN ('certificate','inspection','readings','override','other')),
    is_override    boolean NOT NULL DEFAULT false,
    reason_code_id bigint REFERENCES app.reason_codes(id),
    note           text,
    decided_by     bigint NOT NULL REFERENCES app.users(id),
    decided_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX release_decisions_target_idx ON app.release_decisions (target_kind, target_id, decided_at DESC);
