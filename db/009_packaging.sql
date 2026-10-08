-- 009_packaging.sql — packaging runs (lots in through a packaging configuration, finished lots out) and finished
-- lots. A finished lot is a typed extension of a lot: pieces per package, weight, the heats inside, the product.
SET search_path = app, public;

CREATE TABLE app.packaging_runs (
    id                         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    number                     text NOT NULL UNIQUE,
    site_id                    bigint NOT NULL REFERENCES app.sites(id),
    packaging_configuration_id bigint NOT NULL REFERENCES app.packaging_configurations(id),
    production_order_id        bigint REFERENCES app.production_orders(id),
    equipment_id               bigint REFERENCES app.equipment(id),
    output_location_id         bigint NOT NULL REFERENCES app.locations(id),
    run_on                     date NOT NULL DEFAULT current_date,
    started_at                 timestamptz,
    finished_at                timestamptz,
    status                     text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','posted','cancelled')),
    input_qty_base             numeric(18,4),
    input_weight_kg            numeric(14,3),
    packages_out               int,
    output_weight_kg           numeric(14,3),
    loss_qty_base              numeric(18,4),
    notes                      text,
    created_by                 bigint REFERENCES app.users(id),
    posted_by                  bigint REFERENCES app.users(id),
    posted_at                  timestamptz,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX packaging_runs_order_idx ON app.packaging_runs (production_order_id) WHERE production_order_id IS NOT NULL;
CREATE TRIGGER packaging_runs_touch BEFORE UPDATE ON app.packaging_runs FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

-- The lots packed (run outputs or stock of the configuration's product).
CREATE TABLE app.packaging_run_inputs (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    packaging_run_id bigint NOT NULL REFERENCES app.packaging_runs(id) ON DELETE CASCADE,
    lot_id           bigint NOT NULL REFERENCES app.lots(id),
    qty_base         numeric(18,4) NOT NULL CHECK (qty_base > 0),
    weight_kg        numeric(14,3)
);
CREATE INDEX packaging_run_inputs_lot_idx ON app.packaging_run_inputs (lot_id);

-- The packaging materials used (skids, banding, paper), explicit or backflushed.
CREATE TABLE app.packaging_run_materials (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    packaging_run_id bigint NOT NULL REFERENCES app.packaging_runs(id) ON DELETE CASCADE,
    item_id          bigint NOT NULL REFERENCES app.items(id),
    lot_id           bigint REFERENCES app.lots(id),           -- NULL until posted for backflush
    qty_base         numeric(18,4) NOT NULL CHECK (qty_base > 0),
    mode             text NOT NULL CHECK (mode IN ('explicit','backflush'))
);

-- Finished lots: a typed extension of lots for finished goods — one per package or per batch of packages.
CREATE TABLE app.finished_lots (
    lot_id                     bigint PRIMARY KEY REFERENCES app.lots(id) ON DELETE CASCADE,
    packaging_run_id           bigint NOT NULL REFERENCES app.packaging_runs(id),
    packaging_configuration_id bigint NOT NULL REFERENCES app.packaging_configurations(id),
    product_id                 bigint NOT NULL REFERENCES app.products(id),
    production_order_id        bigint REFERENCES app.production_orders(id),
    packaged_on                date NOT NULL,
    packages                   int NOT NULL CHECK (packages > 0),
    qty_per_package_base       numeric(14,4) NOT NULL,
    package_weight_kg          numeric(12,3),
    heat_numbers               text[] NOT NULL DEFAULT '{}',        -- for the packing list; also in lineage
    best_before_on             date,
    unit_cost                  numeric(18,6)                        -- cost per package, filled by costing
);
CREATE INDEX finished_lots_product_idx ON app.finished_lots (product_id);
CREATE INDEX finished_lots_order_idx ON app.finished_lots (production_order_id) WHERE production_order_id IS NOT NULL;
