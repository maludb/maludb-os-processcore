-- 008_production.sql — production orders, allocations, RUNS (the unit of execution, D3: lots in, lots out, scrap,
-- readings, yield, lineage), consumptions, lot lineage, losses, readings, co-product dispositions. The exemplar slice.
SET search_path = app, public;

CREATE TABLE app.production_orders (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    number              text NOT NULL UNIQUE,
    site_id             bigint NOT NULL REFERENCES app.sites(id),
    product_id          bigint NOT NULL REFERENCES app.products(id),
    process_spec_id     bigint NOT NULL REFERENCES app.process_specs(id),
    planned_qty_base    numeric(18,4) NOT NULL CHECK (planned_qty_base > 0),   -- in the spec's output item unit
    planned_weight_kg   numeric(14,3),
    planned_start_on    date,
    planned_finish_on   date,
    due_on              date,
    priority            smallint NOT NULL DEFAULT 3 CHECK (priority BETWEEN 1 AND 5),  -- 1 = first
    status              text NOT NULL DEFAULT 'planned' CHECK (status IN ('planned','released','in_progress','complete','closed','cancelled')),
    notes               text,
    created_by          bigint REFERENCES app.users(id),
    released_by         bigint REFERENCES app.users(id),
    released_at         timestamptz,
    closed_by           bigint REFERENCES app.users(id),
    closed_at           timestamptz,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX production_orders_status_idx ON app.production_orders (status, due_on);
CREATE TRIGGER production_orders_touch BEFORE UPDATE ON app.production_orders FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

CREATE TABLE app.allocations (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    production_order_id bigint NOT NULL REFERENCES app.production_orders(id) ON DELETE CASCADE,
    item_id             bigint NOT NULL REFERENCES app.items(id),
    lot_id              bigint REFERENCES app.lots(id),       -- NULL = soft (item level)
    qty_base            numeric(18,4) NOT NULL CHECK (qty_base > 0),
    created_at          timestamptz NOT NULL DEFAULT now(),
    released_at         timestamptz                           -- consumed or cancelled
);
CREATE INDEX allocations_open_idx ON app.allocations (item_id, lot_id) WHERE released_at IS NULL;

-- Runs: one operation, on one machine, in one sitting ------------------------------------------
CREATE TABLE app.runs (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    number               text NOT NULL UNIQUE,
    site_id              bigint NOT NULL REFERENCES app.sites(id),
    production_order_id  bigint REFERENCES app.production_orders(id),          -- NULL = stock processing
    process_spec_step_id bigint REFERENCES app.process_spec_steps(id),
    operation_code       text NOT NULL REFERENCES app.operations(code) ON UPDATE CASCADE,
    equipment_id         bigint REFERENCES app.equipment(id),
    status               text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','in_progress','posted','cancelled')),
    run_on               date NOT NULL DEFAULT current_date,
    started_at           timestamptz,
    finished_at          timestamptz,
    setup_minutes        int,
    run_minutes          int,
    input_qty_base       numeric(18,4),                                       -- totals, written at post
    input_weight_kg      numeric(14,3),
    output_qty_base      numeric(18,4),                                       -- product outputs only
    output_weight_kg     numeric(14,3),
    co_product_weight_kg numeric(14,3),
    scrap_weight_kg      numeric(14,3),
    loss_weight_kg       numeric(14,3),                                       -- input − outputs − co-products − scrap
    yield_pct            numeric(6,2),                                        -- output weight / input weight
    notes                text,
    created_by           bigint REFERENCES app.users(id),
    posted_by            bigint REFERENCES app.users(id),
    posted_at            timestamptz,
    cancelled_by         bigint REFERENCES app.users(id),
    cancelled_at         timestamptz,
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX runs_status_idx ON app.runs (status, run_on);
CREATE INDEX runs_order_idx ON app.runs (production_order_id) WHERE production_order_id IS NOT NULL;
CREATE INDEX runs_equipment_idx ON app.runs (equipment_id, run_on) WHERE equipment_id IS NOT NULL;
CREATE TRIGGER runs_touch BEFORE UPDATE ON app.runs FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

-- Inputs: the lots a run takes. The primary input is the one whose inheritable attributes (heat, grade) flow to the outputs.
CREATE TABLE app.run_inputs (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id     bigint NOT NULL REFERENCES app.runs(id) ON DELETE CASCADE,
    seq        int NOT NULL,
    lot_id     bigint NOT NULL REFERENCES app.lots(id),
    qty_base   numeric(18,4) NOT NULL CHECK (qty_base > 0),
    weight_kg  numeric(14,3),
    is_primary boolean NOT NULL DEFAULT false,
    note       text,
    UNIQUE (run_id, seq)
);
CREATE UNIQUE INDEX run_inputs_one_primary ON app.run_inputs (run_id) WHERE is_primary;
CREATE INDEX run_inputs_lot_idx ON app.run_inputs (lot_id);

-- Outputs: the lots a run makes. kind product = what the step yields; co_product (a remnant coil, a usable offcut);
-- scrap (sold by weight); rework (held). The lot is created at post; attributes are explicit values for the new lot
-- on top of the output item's and the primary input's inheritable ones (app.lot_attributes_fill).
CREATE TABLE app.run_outputs (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id      bigint NOT NULL REFERENCES app.runs(id) ON DELETE CASCADE,
    seq         int NOT NULL,
    kind        text NOT NULL DEFAULT 'product' CHECK (kind IN ('product','co_product','scrap','rework')),
    item_id     bigint NOT NULL REFERENCES app.items(id),
    lot_id      bigint REFERENCES app.lots(id),               -- created at post
    qty_base    numeric(18,4) NOT NULL CHECK (qty_base > 0),
    weight_kg   numeric(14,3),
    location_id bigint NOT NULL REFERENCES app.locations(id),
    lot_number  text,                                         -- a chosen number; NULL = the class's sequence
    attributes  jsonb NOT NULL DEFAULT '{}'::jsonb,
    note        text,
    UNIQUE (run_id, seq)
);
CREATE INDEX run_outputs_lot_idx ON app.run_outputs (lot_id) WHERE lot_id IS NOT NULL;

-- Consumables: knives, oil, banding, paper — explicit lots or backflushed at post.
CREATE TABLE app.run_consumables (
    id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id    bigint NOT NULL REFERENCES app.runs(id) ON DELETE CASCADE,
    item_id   bigint NOT NULL REFERENCES app.items(id),
    lot_id    bigint REFERENCES app.lots(id),                 -- NULL until posted for backflush
    qty_base  numeric(18,4) NOT NULL CHECK (qty_base > 0),
    mode      text NOT NULL DEFAULT 'explicit' CHECK (mode IN ('explicit','backflush'))
);

-- Consumptions: the ledger side of inputs and consumables, written at post ----------------------
CREATE TABLE app.consumptions (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id           bigint NOT NULL REFERENCES app.runs(id),
    item_id          bigint NOT NULL REFERENCES app.items(id),
    lot_id           bigint NOT NULL REFERENCES app.lots(id),
    qty_base         numeric(18,4) NOT NULL CHECK (qty_base > 0),
    weight_kg        numeric(14,3),
    purpose          text NOT NULL CHECK (purpose IN ('primary_material','material','consumable','packaging','other')),
    operation_code   text REFERENCES app.operations(code) ON UPDATE CASCADE,
    planned_qty_base numeric(18,4),
    consumed_at      timestamptz NOT NULL DEFAULT now(),
    actor_id         bigint REFERENCES app.users(id),
    ledger_group_id  uuid,
    note             text
);
CREATE INDEX consumptions_run_idx ON app.consumptions (run_id);
CREATE INDEX consumptions_lot_idx ON app.consumptions (lot_id);

-- Lineage: which lot came from which, through which event; weight-based fraction for cost and trace -----------
CREATE TABLE app.lot_lineage (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    child_lot_id  bigint NOT NULL REFERENCES app.lots(id),
    parent_lot_id bigint NOT NULL REFERENCES app.lots(id),
    event_kind    text NOT NULL CHECK (event_kind IN ('run','packaging_run','split')),
    event_id      bigint NOT NULL,
    weight_kg     numeric(14,3),                              -- of the parent that went into the child
    fraction      numeric(10,8) CHECK (fraction IS NULL OR (fraction > 0 AND fraction <= 1)),  -- share of the parent's input
    created_at    timestamptz NOT NULL DEFAULT now(),
    CHECK (child_lot_id <> parent_lot_id)
);
CREATE INDEX lot_lineage_child_idx  ON app.lot_lineage (child_lot_id);
CREATE INDEX lot_lineage_parent_idx ON app.lot_lineage (parent_lot_id);

-- Losses: expected (in the spec) or exceptional (needs a reason, maybe approval) -----------------
CREATE TABLE app.loss_events (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    target_kind     text NOT NULL CHECK (target_kind IN ('run','lot')),
    target_id       bigint NOT NULL,
    site_id         bigint NOT NULL REFERENCES app.sites(id),
    operation_code  text REFERENCES app.operations(code) ON UPDATE CASCADE,
    qty_base        numeric(18,4) NOT NULL CHECK (qty_base > 0),
    unit_code       text NOT NULL DEFAULT 'kg',
    weight_kg       numeric(14,3),
    reason_code_id  bigint NOT NULL REFERENCES app.reason_codes(id),
    report_category text NOT NULL,                            -- copied from the reason code at posting
    classification  text NOT NULL CHECK (classification IN ('expected','exceptional')),
    approved_by     bigint REFERENCES app.users(id),
    approved_at     timestamptz,
    occurred_at     timestamptz NOT NULL DEFAULT now(),
    actor_id        bigint REFERENCES app.users(id),
    ledger_group_id uuid,
    note            text
);
CREATE INDEX loss_events_target_idx ON app.loss_events (target_kind, target_id);
CREATE INDEX loss_events_period_idx ON app.loss_events (site_id, occurred_at);

-- Readings: one entity for every measurement, on a lot, a run or a machine ----------------------
CREATE TABLE app.readings (
    id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    target_kind           text NOT NULL CHECK (target_kind IN ('lot','run','equipment')),
    target_id             bigint NOT NULL,
    measurement_type_code text NOT NULL REFERENCES app.measurement_types(code) ON UPDATE CASCADE,
    value                 numeric(14,4) NOT NULL,
    taken_at              timestamptz NOT NULL DEFAULT now(),
    operation_code        text REFERENCES app.operations(code) ON UPDATE CASCADE,
    method                text,
    is_lab                boolean NOT NULL DEFAULT false,      -- from a certificate or a lab, not the floor
    analyst_id            bigint REFERENCES app.users(id),
    spec_id               bigint REFERENCES app.specs(id),
    spec_result           text NOT NULL DEFAULT 'none' CHECK (spec_result IN ('none','pass','fail')),
    attachment_id         bigint REFERENCES app.attachments(id),
    note                  text,
    created_at            timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX readings_target_idx ON app.readings (target_kind, target_id, measurement_type_code, taken_at);

-- Co-products leaving: scrap sold, recycled, discarded, reworked, or returned to stock -------------
CREATE TABLE app.co_product_dispositions (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lot_id          bigint NOT NULL REFERENCES app.lots(id),
    qty_base        numeric(18,4) NOT NULL CHECK (qty_base > 0),
    weight_kg       numeric(14,3),
    destination     text NOT NULL CHECK (destination IN ('scrap_sale','recycle','waste','rework','return_to_stock','other')),
    recipient       text,
    customer_id     bigint,                                   -- FK added in 011 after customers exists
    unit_price      numeric(12,4),                            -- per kg, when sold
    disposed_at     timestamptz NOT NULL DEFAULT now(),
    actor_id        bigint REFERENCES app.users(id),
    ledger_group_id uuid,
    note            text
);
CREATE INDEX co_product_dispositions_lot_idx ON app.co_product_dispositions (lot_id);
