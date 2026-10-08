-- 011_shipping_reports.sql — customers, shipments (the bill of lading and its lines; a return is a shipment in),
-- the report line map and period reports (D7: a report is lines derived from the ledger, losses and shipments by a
-- match rule — the mechanism the cidery used for its TTB forms, with generic reports seeded).
SET search_path = app, public;

CREATE TABLE app.customers (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name                text NOT NULL,
    kind                text NOT NULL DEFAULT 'other' CHECK (kind IN ('oem','fabricator','distributor','contractor','scrap_dealer','other')),
    contact_name        text,
    email               text,
    phone               text,
    address             text,
    ship_to_address     text,
    default_price_basis text CHECK (default_price_basis IN ('per_unit','per_kg','per_lb','per_cwt','per_package')),
    notes               text,
    active              boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER customers_touch BEFORE UPDATE ON app.customers FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

ALTER TABLE app.co_product_dispositions ADD CONSTRAINT co_product_dispositions_customer_fk FOREIGN KEY (customer_id) REFERENCES app.customers(id);

-- Shipments: one truck out (or one return in). The number is the bill of lading.
CREATE TABLE app.shipments (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    number           text NOT NULL UNIQUE,
    site_id          bigint NOT NULL REFERENCES app.sites(id),
    direction        text NOT NULL DEFAULT 'out' CHECK (direction IN ('out','in')),   -- in = a return
    customer_id      bigint REFERENCES app.customers(id),
    carrier          text,
    trailer          text,
    carrier_reference text,                                       -- the carrier's PRO or the customer's receiving number
    from_location_id bigint REFERENCES app.locations(id),
    to_location_id   bigint REFERENCES app.locations(id),        -- a return's destination
    shipped_at       timestamptz NOT NULL DEFAULT now(),
    status           text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','posted','reversed','cancelled')),
    total_weight_kg  numeric(14,3),
    packages         int,
    notes            text,
    created_by       bigint REFERENCES app.users(id),
    posted_by        bigint REFERENCES app.users(id),
    posted_at        timestamptz,
    reversed_by_id   bigint REFERENCES app.shipments(id),
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX shipments_period_idx ON app.shipments (site_id, shipped_at, direction);
CREATE INDEX shipments_customer_idx ON app.shipments (customer_id, shipped_at DESC);
CREATE TRIGGER shipments_touch BEFORE UPDATE ON app.shipments FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

CREATE TABLE app.shipment_lines (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    shipment_id bigint NOT NULL REFERENCES app.shipments(id) ON DELETE CASCADE,
    lot_id      bigint NOT NULL REFERENCES app.lots(id),         -- a finished lot, or any lot sold as is (a coil)
    qty_base    numeric(18,4) NOT NULL CHECK (qty_base > 0),   -- in the lot's unit (skids of a finished lot, kg of a coil)
    product_qty_base numeric(18,4),                              -- in the product's unit: pieces = qty × the finished lot's pieces per package
    weight_kg   numeric(14,3),
    note        text
);
CREATE INDEX shipment_lines_lot_idx ON app.shipment_lines (lot_id);

-- Which report line an event feeds. Derivation, not data entry. A match is a JSON object the report engine tests
-- against the source row: {"report_category": "produced"} on the ledger, {"direction": "out"} on shipments,
-- {"classification": "expected"} on losses; "item_class" and "site" are admitted on every source.
CREATE TABLE app.report_line_map (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    report_code   text NOT NULL,
    section       text NOT NULL,
    line_code     text NOT NULL,
    label         text NOT NULL,
    source        text NOT NULL CHECK (source IN ('ledger','loss','shipment','balance','run')),
    match         jsonb NOT NULL,
    measure       text NOT NULL DEFAULT 'weight_kg' CHECK (measure IN ('weight_kg','qty_base','count','value')),
    sign          int NOT NULL DEFAULT 1,
    display_order int NOT NULL,
    UNIQUE (report_code, section, line_code)
);
INSERT INTO app.report_line_map (report_code, section, line_code, label, source, match, measure, sign, display_order) VALUES
    ('production', 'A', '1', 'On hand at start of period',            'balance',  '{"when":"start"}',                          'weight_kg', 1, 10),
    ('production', 'A', '2', 'Received',                               'ledger',   '{"report_category":"received"}',            'weight_kg', 1, 20),
    ('production', 'A', '3', 'Consumed by runs',                       'ledger',   '{"report_category":"consumed"}',            'weight_kg', 1, 30),
    ('production', 'A', '4', 'Produced by runs',                       'ledger',   '{"report_category":"produced"}',            'weight_kg', 1, 40),
    ('production', 'A', '5', 'Packaged',                               'ledger',   '{"report_category":"packaged"}',            'weight_kg', 1, 50),
    ('production', 'A', '6', 'Shipped',                                'shipment', '{"direction":"out"}',                       'weight_kg', 1, 60),
    ('production', 'A', '7', 'Returned',                               'shipment', '{"direction":"in"}',                        'weight_kg', 1, 70),
    ('production', 'A', '8', 'On hand at end of period',               'balance',  '{"when":"end"}',                            'weight_kg', 1, 80),
    ('yield_scrap', 'A', '1', 'Material into runs',                    'run',      '{"measure":"input"}',                       'weight_kg', 1, 10),
    ('yield_scrap', 'A', '2', 'Product out of runs',                   'run',      '{"measure":"output"}',                      'weight_kg', 1, 20),
    ('yield_scrap', 'A', '3', 'Co-products out of runs',               'run',      '{"measure":"co_product"}',                  'weight_kg', 1, 30),
    ('yield_scrap', 'A', '4', 'Scrap out of runs',                     'run',      '{"measure":"scrap"}',                       'weight_kg', 1, 40),
    ('yield_scrap', 'A', '5', 'Unaccounted loss in runs',              'run',      '{"measure":"loss"}',                        'weight_kg', 1, 50),
    ('yield_scrap', 'B', '1', 'Expected losses recorded',              'loss',     '{"classification":"expected"}',             'weight_kg', 1, 60),
    ('yield_scrap', 'B', '2', 'Exceptional losses recorded',           'loss',     '{"classification":"exceptional"}',          'weight_kg', 1, 70),
    ('yield_scrap', 'B', '3', 'Scrap sold or disposed',                'ledger',   '{"report_category":"scrapped"}',            'weight_kg', 1, 80),
    ('shipments', 'A', '1', 'Shipments (count)',                       'shipment', '{"direction":"out"}',                       'count',     1, 10),
    ('shipments', 'A', '2', 'Weight shipped',                          'shipment', '{"direction":"out"}',                       'weight_kg', 1, 20),
    ('shipments', 'A', '3', 'Packages shipped',                        'shipment', '{"direction":"out","measure":"packages"}',  'count',     1, 30),
    ('shipments', 'A', '4', 'Returns (count)',                         'shipment', '{"direction":"in"}',                        'count',     1, 40),
    ('shipments', 'A', '5', 'Weight returned',                         'shipment', '{"direction":"in"}',                        'weight_kg', 1, 50);

CREATE TABLE app.period_reports (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    number        text NOT NULL UNIQUE,
    site_id       bigint NOT NULL REFERENCES app.sites(id),
    report_code   text NOT NULL,
    period_start  date NOT NULL,
    period_end    date NOT NULL,
    status        text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','final','amended')),
    generated_at  timestamptz NOT NULL DEFAULT now(),
    generated_by  bigint REFERENCES app.users(id),
    finalized_at  timestamptz,
    finalized_by  bigint REFERENCES app.users(id),
    totals        jsonb NOT NULL DEFAULT '{}'::jsonb,
    notes         text,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (site_id, report_code, period_start, period_end),
    CHECK (period_end >= period_start)
);
CREATE TRIGGER period_reports_touch BEFORE UPDATE ON app.period_reports FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

CREATE TABLE app.period_report_lines (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    report_id     bigint NOT NULL REFERENCES app.period_reports(id) ON DELETE CASCADE,
    section       text NOT NULL,
    line_code     text NOT NULL,
    label         text NOT NULL,
    group_key     text NOT NULL DEFAULT '',                           -- the item class or product family the line is split by
    value         numeric(16,4) NOT NULL DEFAULT 0,
    unit          text NOT NULL DEFAULT 'kg',
    source_ids    jsonb NOT NULL DEFAULT '[]'::jsonb,                 -- the ledger / loss / shipment ids behind the number
    is_adjustment boolean NOT NULL DEFAULT false,
    UNIQUE (report_id, section, line_code, group_key)
);
