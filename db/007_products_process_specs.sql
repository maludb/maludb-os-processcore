-- 007_products_process_specs.sql — operations, measurement types, products with attributes, process specs (the
-- generic of a recipe: a versioned, immutable-once-active sequence of steps with inputs and expected losses), specs
-- per product per operation, packaging configurations, standard costs, overhead rates.
SET search_path = app, public;

-- Operations: what a run does. Data, seeded by the profile (steel: slit, cut_to_length, shear, blank, level, pack, inspect).
CREATE TABLE app.operations (
    code          text PRIMARY KEY CHECK (code ~ '^[a-z][a-z0-9_]{1,29}$'),
    name          text NOT NULL,
    kind          text NOT NULL DEFAULT 'convert' CHECK (kind IN ('convert','pack','inspect','move')),
    description   text,
    display_order int NOT NULL DEFAULT 100,
    is_terminal   boolean NOT NULL DEFAULT false,
    is_builtin    boolean NOT NULL DEFAULT false,
    active        boolean NOT NULL DEFAULT true
);

-- Measurement types: what a reading measures. Data, seeded by the profile.
CREATE TABLE app.measurement_types (
    code      text PRIMARY KEY CHECK (code ~ '^[a-z][a-z0-9_]{1,29}$'),
    name      text NOT NULL,
    unit      text NOT NULL,
    decimals  int NOT NULL DEFAULT 2,
    min_valid numeric(14,4),
    max_valid numeric(14,4),
    display_order int NOT NULL DEFAULT 100,
    active    boolean NOT NULL DEFAULT true
);

-- Products: the specification of something the business makes ---------------------------
CREATE TABLE app.products (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code       text NOT NULL,
    name       text NOT NULL,
    family     text,                                                   -- a grouping the business chooses (cut sheets, blanks, mults)
    status     text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','active','retired')),
    notes      text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX products_code_key ON app.products (lower(code));
CREATE TRIGGER products_touch BEFORE UPDATE ON app.products FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

CREATE TABLE app.product_attribute_values (
    product_id    bigint NOT NULL REFERENCES app.products(id) ON DELETE CASCADE,
    attribute_key text NOT NULL REFERENCES app.attribute_definitions(key) ON DELETE CASCADE,
    value_num     numeric(18,6),
    value_text    text,
    PRIMARY KEY (product_id, attribute_key),
    CHECK (value_num IS NOT NULL OR value_text IS NOT NULL)
);

-- Process spec versions: immutable once active -------------------------------------------
CREATE TABLE app.process_specs (
    id                      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id              bigint NOT NULL REFERENCES app.products(id),
    version_no              int NOT NULL,
    status                  text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','active','retired')),
    output_item_id          bigint NOT NULL REFERENCES app.items(id),         -- what the last convert step yields
    planned_qty_base        numeric(18,4) NOT NULL CHECK (planned_qty_base > 0), -- the usual run size, in the output item's unit
    expected_total_loss_pct numeric(5,2),                                      -- cached sum of step losses
    standard_cost_total     numeric(18,4),                                     -- snapshot at activation, per planned run
    standard_cost_per_base  numeric(18,6),
    change_note             text,
    activated_at            timestamptz,
    activated_by            bigint REFERENCES app.users(id),
    created_by              bigint REFERENCES app.users(id),
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    UNIQUE (product_id, version_no)
);
CREATE UNIQUE INDEX process_specs_one_active ON app.process_specs (product_id) WHERE status = 'active';
CREATE TRIGGER process_specs_touch BEFORE UPDATE ON app.process_specs FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

CREATE OR REPLACE FUNCTION app.process_spec_guard_immutable() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_status text;
BEGIN
    SELECT status INTO v_status FROM app.process_specs WHERE id = COALESCE(NEW.process_spec_id, OLD.process_spec_id);
    IF v_status <> 'draft' THEN
        RAISE EXCEPTION 'process spec version is %, create a new version to change it', v_status
            USING ERRCODE = 'integrity_constraint_violation';
    END IF;
    RETURN COALESCE(NEW, OLD);
END $$;

-- Steps: the operations in order, on what kind of equipment, with the expected loss and the time.
CREATE TABLE app.process_spec_steps (
    id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    process_spec_id       bigint NOT NULL REFERENCES app.process_specs(id) ON DELETE CASCADE,
    seq                   int NOT NULL,
    operation_code        text NOT NULL REFERENCES app.operations(code) ON UPDATE CASCADE,
    equipment_kind        text REFERENCES app.equipment_kinds(code) ON UPDATE CASCADE,
    expected_loss_pct     numeric(5,2) NOT NULL DEFAULT 0,
    setup_minutes         int,
    minutes_per_base_unit numeric(10,4),                                      -- run rate, per base unit of output
    output_item_id        bigint REFERENCES app.items(id),                    -- what this step yields when not the spec's output
    instructions          text,
    UNIQUE (process_spec_id, seq)
);
CREATE TRIGGER process_spec_steps_guard BEFORE INSERT OR UPDATE OR DELETE ON app.process_spec_steps
    FOR EACH ROW EXECUTE FUNCTION app.process_spec_guard_immutable();

-- Inputs: the material (one primary), consumables and packaging, per base unit of output or per run.
CREATE TABLE app.process_spec_inputs (
    id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    process_spec_id    bigint NOT NULL REFERENCES app.process_specs(id) ON DELETE CASCADE,
    seq                int NOT NULL,
    step_seq           int,                                                   -- the step that uses it; NULL = the first
    item_id            bigint NOT NULL REFERENCES app.items(id),
    purpose            text NOT NULL DEFAULT 'primary_material' CHECK (purpose IN ('primary_material','material','consumable','packaging','other')),
    qty_per_base_unit  numeric(18,8),                                         -- scales with output, or
    qty_per_run        numeric(18,4),                                         -- fixed per run
    consumption_mode   text NOT NULL DEFAULT 'explicit' CHECK (consumption_mode IN ('explicit','backflush')),
    notes              text,
    UNIQUE (process_spec_id, seq),
    CHECK ((qty_per_base_unit IS NOT NULL) <> (qty_per_run IS NOT NULL))
);
CREATE TRIGGER process_spec_inputs_guard BEFORE INSERT OR UPDATE OR DELETE ON app.process_spec_inputs
    FOR EACH ROW EXECUTE FUNCTION app.process_spec_guard_immutable();

-- Specs: acceptable ranges per product per operation -----------------------------------------
CREATE TABLE app.specs (
    id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id            bigint NOT NULL REFERENCES app.products(id) ON DELETE CASCADE,
    operation_code        text NOT NULL REFERENCES app.operations(code) ON UPDATE CASCADE,
    measurement_type_code text NOT NULL REFERENCES app.measurement_types(code) ON UPDATE CASCADE,
    min_value             numeric(14,4),
    max_value             numeric(14,4),
    target_value          numeric(14,4),
    active                boolean NOT NULL DEFAULT true,
    UNIQUE (product_id, operation_code, measurement_type_code),
    CHECK (min_value IS NOT NULL OR max_value IS NOT NULL)
);

-- Packaging configurations: how a product's output is packed into a finished good ------------
CREATE TABLE app.packaging_configurations (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id           bigint NOT NULL REFERENCES app.products(id),
    finished_item_id     bigint NOT NULL REFERENCES app.items(id),             -- item_class finished_good
    name                 text NOT NULL,
    package_kind         text NOT NULL DEFAULT 'skid' CHECK (package_kind IN ('skid','bundle','pallet','crate','box','coil','bag','other')),
    qty_per_package_base numeric(14,4) NOT NULL CHECK (qty_per_package_base > 0), -- pieces (or kg) per package
    max_weight_kg        numeric(12,3),
    expected_loss_pct    numeric(5,2) NOT NULL DEFAULT 0,
    default_unit_price   numeric(12,4) CHECK (default_unit_price IS NULL OR default_unit_price >= 0),
    default_price_basis  text NOT NULL DEFAULT 'per_unit' CHECK (default_price_basis IN ('per_unit','per_kg','per_lb','per_cwt','per_package')),
    active               boolean NOT NULL DEFAULT true,
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now(),
    UNIQUE (product_id, finished_item_id)
);
CREATE TRIGGER packaging_configurations_touch BEFORE UPDATE ON app.packaging_configurations FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

CREATE TABLE app.packaging_bom_lines (
    id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    configuration_id  bigint NOT NULL REFERENCES app.packaging_configurations(id) ON DELETE CASCADE,
    item_id           bigint NOT NULL REFERENCES app.items(id),
    qty_per_package_base numeric(18,6) NOT NULL CHECK (qty_per_package_base > 0),
    UNIQUE (configuration_id, item_id)
);

-- Standard costs and overhead ---------------------------------------------------------
CREATE TABLE app.standard_costs (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_id        bigint NOT NULL REFERENCES app.items(id) ON DELETE CASCADE,
    cost_per_base  numeric(18,6) NOT NULL CHECK (cost_per_base >= 0),
    effective_from date NOT NULL DEFAULT current_date,
    created_by     bigint REFERENCES app.users(id),
    created_at     timestamptz NOT NULL DEFAULT now(),
    UNIQUE (item_id, effective_from)
);

-- Overhead per kilogram of material entering a run, per site (D11).
CREATE TABLE app.overhead_rates (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    site_id        bigint NOT NULL REFERENCES app.sites(id),
    rate_per_kg    numeric(18,6) NOT NULL CHECK (rate_per_kg >= 0),
    effective_from date NOT NULL DEFAULT current_date,
    created_by     bigint REFERENCES app.users(id),
    created_at     timestamptz NOT NULL DEFAULT now(),
    UNIQUE (site_id, effective_from)
);
