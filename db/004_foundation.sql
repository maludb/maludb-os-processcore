-- 004_foundation.sql — the business, sites, units, item classes and the attribute dictionary, items, suppliers,
-- locations (areas and racks), reason codes, equipment, attachments. Industry-neutral: the profile seeds the classes,
-- attributes, equipment kinds and reason codes an industry needs (db/profiles/<name>/seed.sql).
SET search_path = app, public;

-- One row per business ------------------------------------------------------------------
CREATE TABLE app.client_settings (
    id                   int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    client_name          text NOT NULL,
    subdomain            text NOT NULL,
    timezone             text NOT NULL DEFAULT 'America/New_York',
    profile              text NOT NULL DEFAULT 'steel',           -- the profile applied at provisioning (D12)
    mass_display_unit    text NOT NULL DEFAULT 'lb',
    length_display_unit  text NOT NULL DEFAULT 'in',
    area_display_unit    text NOT NULL DEFAULT 'ft2',
    volume_display_unit  text NOT NULL DEFAULT 'gal',
    settings             jsonb NOT NULL DEFAULT '{"equipment": {"double_booking": "refuse"}}'::jsonb,  -- the switches and the dashboard tiles
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER client_settings_touch BEFORE UPDATE ON app.client_settings FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

-- Sites: a plant, a yard, a warehouse — where stock sits and runs happen ------------------
CREATE TABLE app.sites (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code       text NOT NULL,
    name       text NOT NULL,
    address    text,
    timezone   text,                                               -- NULL = the business's
    active     boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX sites_code_key ON app.sites (lower(code));
CREATE TRIGGER sites_touch BEFORE UPDATE ON app.sites FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

-- Units: metric base per dimension, any display --------------------------------------------
CREATE TABLE app.units (
    code           text PRIMARY KEY,
    name           text NOT NULL,
    dimension      text NOT NULL CHECK (dimension IN ('mass','length','area','volume','count')),
    to_base_factor numeric(18,8) NOT NULL,                         -- multiply to get base (kg, m, m², L, ea)
    is_base        boolean NOT NULL DEFAULT false,
    display_order  int NOT NULL DEFAULT 100
);
INSERT INTO app.units (code, name, dimension, to_base_factor, is_base, display_order) VALUES
    ('kg',   'kilogram',               'mass',   1,              true,  10),
    ('g',    'gram',                   'mass',   0.001,          false, 11),
    ('mt',   'metric tonne',           'mass',   1000,           false, 12),
    ('lb',   'pound',                  'mass',   0.45359237,     false, 20),
    ('oz',   'ounce',                  'mass',   0.0283495231,   false, 21),
    ('cwt',  'hundredweight (100 lb)', 'mass',   45.359237,      false, 22),
    ('ton',  'US short ton',           'mass',   907.18474,      false, 23),
    ('m',    'metre',                  'length', 1,              true,  30),
    ('mm',   'millimetre',             'length', 0.001,          false, 31),
    ('cm',   'centimetre',             'length', 0.01,           false, 32),
    ('in',   'inch',                   'length', 0.0254,         false, 40),
    ('ft',   'foot',                   'length', 0.3048,         false, 41),
    ('m2',   'square metre',           'area',   1,              true,  50),
    ('ft2',  'square foot',            'area',   0.09290304,     false, 51),
    ('in2',  'square inch',            'area',   0.00064516,     false, 52),
    ('L',    'litre',                  'volume', 1,              true,  60),
    ('mL',   'millilitre',             'volume', 0.001,          false, 61),
    ('gal',  'US gallon',              'volume', 3.785411784,    false, 62),
    ('ea',   'each',                   'count',  1,              true,  70);

-- Item classes: what kind of thing an item is. Data, so a profile or a client adds classes and renames the built-in
-- ones; the built-in codes carry behaviour in PHP (finished_good is the Finished goods screen, packaging feeds the
-- packaging BOM, co_product is what a run throws off), so a built-in row cannot be deleted and its code and kind
-- cannot change. kind picks the On hand screen; purchasable offers the class on purchase orders and receipts;
-- process_input on process spec inputs and run inputs; catch_weight and serialized are the defaults for new items;
-- lot_noun is the word the screens use for a lot of the class ("Coil", "Skid"); lot_number_key names the sequence.
CREATE TABLE app.item_classes (
    id                bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
    code              text PRIMARY KEY CHECK (code ~ '^[a-z][a-z0-9_]{1,29}$'),
    name              text NOT NULL,
    kind              text NOT NULL CHECK (kind IN ('material','finished')),
    purchasable       boolean NOT NULL DEFAULT true,
    process_input     boolean NOT NULL DEFAULT false,
    catch_weight      boolean NOT NULL DEFAULT false,
    serialized        boolean NOT NULL DEFAULT false,            -- one lot = one unit (a coil, a roll, a log)
    lot_noun          text NOT NULL DEFAULT 'Lot',
    lot_noun_plural   text NOT NULL DEFAULT 'Lots',
    lot_number_key    text REFERENCES app.number_sequences(key),  -- NULL = 'lot'
    density_kg_m3     numeric(12,3),                              -- default for theoretical weight; an item may override
    display_order     int NOT NULL DEFAULT 100,
    is_builtin        boolean NOT NULL DEFAULT false,
    active            boolean NOT NULL DEFAULT true,
    notes             text,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER item_classes_touch BEFORE UPDATE ON app.item_classes FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

INSERT INTO app.item_classes (code, name, kind, purchasable, process_input, catch_weight, serialized, lot_noun, lot_noun_plural, display_order, is_builtin) VALUES
    ('material',         'Material',         'material', true,  true,  false, false, 'Lot',  'Lots',  10,  true),
    ('intermediate',     'Intermediate',     'material', false, true,  false, false, 'Lot',  'Lots',  20,  true),
    ('consumable',       'Consumable',       'material', true,  true,  false, false, 'Lot',  'Lots',  30,  true),
    ('packaging',        'Packaging',        'material', true,  false, false, false, 'Lot',  'Lots',  40,  true),
    ('co_product',       'Co-product',       'material', false, false, true,  false, 'Lot',  'Lots',  50,  true),
    ('finished_good',    'Finished good',    'finished', false, false, false, false, 'Lot',  'Lots',  60,  true),
    ('returnable_asset', 'Returnable asset', 'material', true,  false, false, true,  'Unit', 'Units', 70,  true);

CREATE OR REPLACE FUNCTION app.item_classes_guard_builtin() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.is_builtin THEN
            RAISE EXCEPTION 'built-in item class % cannot be deleted', OLD.code USING ERRCODE = 'integrity_constraint_violation';
        END IF;
        RETURN OLD;
    END IF;
    IF OLD.is_builtin AND (NEW.code <> OLD.code OR NEW.kind <> OLD.kind OR NOT NEW.is_builtin) THEN
        RAISE EXCEPTION 'built-in item class %: the code and kind cannot change', OLD.code USING ERRCODE = 'integrity_constraint_violation';
    END IF;
    IF NOT OLD.is_builtin THEN
        NEW.is_builtin := false;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER item_classes_guard BEFORE UPDATE OR DELETE ON app.item_classes FOR EACH ROW EXECUTE FUNCTION app.item_classes_guard_builtin();

-- The attribute dictionary (D5): typed definitions the profile seeds and a client extends. A value lives on an item
-- (what the SKU is: thickness, width), on a product (what is to be made) and on a lot (what this one is: heat, grade,
-- the measured width). inherit = a run's output lot copies the value from its primary input lot unless the output item
-- or the run says otherwise (heat and grade flow down; length does not).
CREATE TABLE app.attribute_definitions (
    key           text PRIMARY KEY CHECK (key ~ '^[a-z][a-z0-9_]{1,39}$'),
    name          text NOT NULL,
    kind          text NOT NULL CHECK (kind IN ('num','text','choice','bool')),
    unit_code     text REFERENCES app.units(code),               -- num only; the unit the value is stored in
    decimals      int NOT NULL DEFAULT 2,
    choices       text[],                                        -- choice only
    on_items      boolean NOT NULL DEFAULT true,
    on_products   boolean NOT NULL DEFAULT true,
    on_lots       boolean NOT NULL DEFAULT true,
    inherit       boolean NOT NULL DEFAULT false,
    in_code       boolean NOT NULL DEFAULT false,                -- part of a composed item or product code
    display_order int NOT NULL DEFAULT 100,
    active        boolean NOT NULL DEFAULT true,
    notes         text,
    CHECK (kind <> 'choice' OR choices IS NOT NULL)
);

-- Which attributes a class carries, and whether each is required on an item of the class.
CREATE TABLE app.item_class_attributes (
    item_class    text NOT NULL REFERENCES app.item_classes(code) ON UPDATE CASCADE ON DELETE CASCADE,
    attribute_key text NOT NULL REFERENCES app.attribute_definitions(key) ON DELETE CASCADE,
    required      boolean NOT NULL DEFAULT false,
    display_order int NOT NULL DEFAULT 100,
    PRIMARY KEY (item_class, attribute_key)
);

-- Items ------------------------------------------------------------------------------------
CREATE TABLE app.items (
    id                     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code                   text NOT NULL,
    name                   text NOT NULL,
    item_class             text NOT NULL REFERENCES app.item_classes(code) ON UPDATE CASCADE,
    base_unit_code         text NOT NULL REFERENCES app.units(code),
    lot_controlled         boolean NOT NULL DEFAULT true,
    catch_weight           boolean NOT NULL DEFAULT false,         -- the weight is the ticket's, not the count's
    serialized             boolean NOT NULL DEFAULT false,         -- one lot = one unit
    unit_weight_kg         numeric(14,6),                          -- weight of one base unit when the base is a count (theoretical or nominal)
    density_kg_m3          numeric(12,3),                          -- overrides the class's for theoretical weight
    shelf_life_days        int,
    default_receipt_status text NOT NULL DEFAULT 'released' CHECK (default_receipt_status IN ('quarantine','released')),
    consumption_mode       text NOT NULL DEFAULT 'explicit' CHECK (consumption_mode IN ('explicit','backflush')),
    costing_method         text NOT NULL DEFAULT 'actual_lot' CHECK (costing_method IN ('actual_lot','standard')),
    standard_cost_per_base numeric(18,6),                          -- current standard; history in standard_costs
    reorder_point_base     numeric(18,4),
    min_qty_base           numeric(18,4),
    max_qty_base           numeric(18,4),
    units_per_package      int,                                    -- finished goods: pieces per package, informational
    active                 boolean NOT NULL DEFAULT true,
    notes                  text,
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX items_code_key ON app.items (lower(code));
CREATE INDEX items_class_idx ON app.items (item_class) WHERE active;
CREATE TRIGGER items_touch BEFORE UPDATE ON app.items FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

CREATE TABLE app.item_attribute_values (
    item_id       bigint NOT NULL REFERENCES app.items(id) ON DELETE CASCADE,
    attribute_key text NOT NULL REFERENCES app.attribute_definitions(key) ON DELETE CASCADE,
    value_num     numeric(18,6),
    value_text    text,
    PRIMARY KEY (item_id, attribute_key),
    CHECK (value_num IS NOT NULL OR value_text IS NOT NULL)
);

-- Per-item alternate units (a 25 kg sack, a bundle of 50, a skid of 40)
CREATE TABLE app.item_units (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_id        bigint NOT NULL REFERENCES app.items(id) ON DELETE CASCADE,
    unit_code      text NOT NULL,                                  -- free label: 'sack', 'bundle', 'skid'
    unit_name      text NOT NULL,
    to_base_factor numeric(18,8) NOT NULL,
    is_purchase_default boolean NOT NULL DEFAULT false,
    UNIQUE (item_id, unit_code)
);

-- A numeric or text attribute of an item (NULL when absent).
CREATE OR REPLACE FUNCTION app.item_attribute_num(p_item_id bigint, p_key text) RETURNS numeric
LANGUAGE sql STABLE AS $$
    SELECT value_num FROM app.item_attribute_values WHERE item_id = p_item_id AND attribute_key = p_key
$$;
CREATE OR REPLACE FUNCTION app.item_attribute_text(p_item_id bigint, p_key text) RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(value_text, value_num::text) FROM app.item_attribute_values WHERE item_id = p_item_id AND attribute_key = p_key
$$;

-- Suppliers -----------------------------------------------------------------------------
CREATE TABLE app.suppliers (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name         text NOT NULL,
    kind         text NOT NULL DEFAULT 'vendor' CHECK (kind IN ('vendor','mill','distributor','processor','packaging','services','other')),
    contact_name text,
    email        text,
    phone        text,
    address      text,
    notes        text,
    active       boolean NOT NULL DEFAULT true,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER suppliers_touch BEFORE UPDATE ON app.suppliers FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

CREATE TABLE app.supplier_items (
    id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    supplier_id        bigint NOT NULL REFERENCES app.suppliers(id) ON DELETE CASCADE,
    item_id            bigint NOT NULL REFERENCES app.items(id),
    supplier_sku       text,
    purchase_unit_code text NOT NULL,                              -- app.units.code or item_units.unit_code
    to_base_factor     numeric(18,8) NOT NULL,
    last_price         numeric(18,4),                              -- per purchase unit
    lead_time_days     int,
    active             boolean NOT NULL DEFAULT true,
    UNIQUE (supplier_id, item_id)
);

-- Locations hold lots. An area is a location; a rack is a location inside an area (one level) ----------------
CREATE TABLE app.locations (
    id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    site_id            bigint NOT NULL REFERENCES app.sites(id),
    name               text NOT NULL,
    kind               text NOT NULL CHECK (kind IN ('receiving','storage','yard','line_side','finished_goods','shipping','scrap','quarantine','outside')),
    allow_negative     boolean NOT NULL DEFAULT false,
    parent_location_id bigint REFERENCES app.locations(id),
    rack_number        text,
    active             boolean NOT NULL DEFAULT true,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now(),
    UNIQUE (site_id, name),
    CONSTRAINT locations_rack_shape CHECK ((parent_location_id IS NULL) = (rack_number IS NULL)),
    CONSTRAINT locations_rack_number_check CHECK (rack_number IS NULL OR rack_number ~ '^[A-Za-z0-9-]{1,12}$'),
    CONSTRAINT locations_rack_not_own_area CHECK (parent_location_id <> id)
);
CREATE UNIQUE INDEX locations_site_rack_number_key ON app.locations (site_id, upper(rack_number)) WHERE rack_number IS NOT NULL;
CREATE INDEX locations_parent_idx ON app.locations (parent_location_id) WHERE parent_location_id IS NOT NULL;
CREATE TRIGGER locations_touch BEFORE UPDATE ON app.locations FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

-- Sort key that puts rack 2 before rack 10 and A2 before A10.
CREATE OR REPLACE FUNCTION app.rack_sort_key(p_rack_number text) RETURNS text
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    v_out text := '';
    v_part text;
BEGIN
    IF p_rack_number IS NULL THEN
        RETURN NULL;
    END IF;
    FOR v_part IN SELECT (regexp_matches(upper(p_rack_number), '([0-9]+|[^0-9]+)', 'g'))[1] LOOP
        v_out := v_out || CASE WHEN v_part ~ '^[0-9]+$' THEN lpad(v_part, 10, '0') ELSE v_part END;
    END LOOP;
    RETURN v_out;
END $$;

-- Racks copy site and kind from their area and are named "Rack <number>".
CREATE OR REPLACE FUNCTION app.locations_rack_rules() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_area app.locations%ROWTYPE;
BEGIN
    IF NEW.parent_location_id IS NULL THEN
        RETURN NEW;
    END IF;
    SELECT * INTO v_area FROM app.locations WHERE id = NEW.parent_location_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'The area for this rack does not exist.' USING ERRCODE = 'foreign_key_violation';
    END IF;
    IF v_area.parent_location_id IS NOT NULL THEN
        RAISE EXCEPTION 'A rack must sit in an area, not in another rack.' USING ERRCODE = 'check_violation';
    END IF;
    IF TG_OP = 'UPDATE' AND EXISTS (SELECT 1 FROM app.locations WHERE parent_location_id = NEW.id) THEN
        RAISE EXCEPTION 'This area has racks, so it cannot become a rack.' USING ERRCODE = 'check_violation';
    END IF;
    NEW.rack_number := upper(NEW.rack_number);
    NEW.site_id := v_area.site_id;
    NEW.kind    := v_area.kind;
    NEW.name    := 'Rack ' || NEW.rack_number;
    RETURN NEW;
END $$;
CREATE TRIGGER locations_rack_rules BEFORE INSERT OR UPDATE ON app.locations
    FOR EACH ROW EXECUTE FUNCTION app.locations_rack_rules();

-- When an area changes site or kind its racks follow.
CREATE OR REPLACE FUNCTION app.locations_area_cascade() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE app.locations SET site_id = NEW.site_id, kind = NEW.kind WHERE parent_location_id = NEW.id;
    RETURN NULL;
END $$;
CREATE TRIGGER locations_area_cascade AFTER UPDATE OF site_id, kind ON app.locations
    FOR EACH ROW WHEN (NEW.parent_location_id IS NULL AND (OLD.site_id, OLD.kind) IS DISTINCT FROM (NEW.site_id, NEW.kind))
    EXECUTE FUNCTION app.locations_area_cascade();

-- Reason codes: why stock moved outside the plan; report_category is what the period reports group by -------------
CREATE TABLE app.reason_codes (
    id                      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code                    text NOT NULL UNIQUE,
    name                    text NOT NULL,
    applies_to              text NOT NULL CHECK (applies_to IN ('adjustment','loss','scrap','override','count','short_close')),
    report_category         text NOT NULL DEFAULT 'none' CHECK (report_category IN (
                                'none','process_loss','exceptional_loss','scrap','damage','destroyed','shortage','gain','correction')),
    classification          text NOT NULL DEFAULT 'exceptional' CHECK (classification IN ('expected','exceptional')),
    requires_approval_above numeric(18,4),                         -- NULL = never; in kg for loss and scrap, the item's base unit otherwise
    is_builtin              boolean NOT NULL DEFAULT false,
    active                  boolean NOT NULL DEFAULT true
);
INSERT INTO app.reason_codes (code, name, applies_to, report_category, classification, is_builtin) VALUES
    ('PROCESS',  'Process loss (expected)',       'loss',        'process_loss',     'expected',    true),
    ('SCRAP',    'Scrap (expected)',              'scrap',       'scrap',            'expected',    true),
    ('DAMAGE',   'Damaged',                       'adjustment',  'damage',           'exceptional', true),
    ('DESTROY',  'Destroyed or discarded',        'loss',        'destroyed',        'exceptional', true),
    ('COUNT',    'Count variance',                'count',       'shortage',         'exceptional', true),
    ('OPENING',  'Opening balance',               'adjustment',  'none',             'expected',    true),
    ('CORRECT',  'Data entry correction',         'adjustment',  'correction',       'exceptional', true),
    ('SHORT',    'Supplier short-shipped',        'short_close', 'none',             'expected',    true),
    ('SPECOVR',  'Spec override by quality',      'override',    'none',             'exceptional', true);

-- Equipment: what a run happens on. The kinds are data (the profile seeds them); capabilities are limits keyed by
-- attribute (D6): {"width_in": {"max": 72}, "thickness_in": {"min": 0.015, "max": 0.25}, "weight_kg": {"max": 20000}}
-- — compared with an item's attributes (weight_kg with a lot's weight) by app.equipment_fits(), a warning never a stop.
CREATE TABLE app.equipment_kinds (
    code          text PRIMARY KEY CHECK (code ~ '^[a-z][a-z0-9_]{1,29}$'),
    name          text NOT NULL,
    display_order int NOT NULL DEFAULT 100,
    is_builtin    boolean NOT NULL DEFAULT false,
    active        boolean NOT NULL DEFAULT true
);
INSERT INTO app.equipment_kinds (code, name, display_order, is_builtin) VALUES
    ('packaging_line', 'Packaging line', 80, true),
    ('scale',          'Scale',          81, true),
    ('crane',          'Crane',          82, true),
    ('forklift',       'Forklift',       83, true),
    ('other',          'Other',          99, true);

CREATE TABLE app.equipment (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    site_id      bigint NOT NULL REFERENCES app.sites(id),
    location_id  bigint REFERENCES app.locations(id),              -- the bay or area it stands in, when known
    name         text NOT NULL,
    kind         text NOT NULL REFERENCES app.equipment_kinds(code) ON UPDATE CASCADE,
    status       text NOT NULL DEFAULT 'available' CHECK (status IN ('available','setup','maintenance','out_of_service')),
    rating       text,                                             -- "60 ft/min", "20,000 lb coils": words, not a number
    capabilities jsonb NOT NULL DEFAULT '{}'::jsonb,
    notes        text,
    active       boolean NOT NULL DEFAULT true,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    UNIQUE (site_id, name)
);
CREATE TRIGGER equipment_touch BEFORE UPDATE ON app.equipment FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

-- Attachments on any entity --------------------------------------------------------------
CREATE TABLE app.attachments (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    entity_type  text NOT NULL,                                    -- 'lot','goods_receipt','product','run','shipment',...
    entity_id    bigint NOT NULL,
    kind         text NOT NULL CHECK (kind IN ('certificate','weigh_ticket','drawing','photo','spreadsheet','bol','packing_list','other')),
    file_name    text NOT NULL,
    mime_type    text NOT NULL,
    storage_path text NOT NULL,                                    -- under storage/{client}/
    byte_size    bigint NOT NULL,
    uploaded_by  bigint REFERENCES app.users(id),
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX attachments_entity_idx ON app.attachments (entity_type, entity_id);
