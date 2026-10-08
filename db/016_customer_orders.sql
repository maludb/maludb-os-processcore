-- 016_customer_orders.sql — customer orders, standing orders, forecasts, spreadsheet imports,
-- and the links that let an order drive packaging, shipping and production.
-- Plan: docs/cidery/11-customer-orders-plan.md. Design notes: docs/cidery/12-customer-orders-design.md.
-- Orders are planning documents: nothing here touches the ledger, tax or TTB tables.
SET search_path = app, public;

-- Roles and attachments ---------------------------------------------------------------
ALTER TABLE app.users DROP CONSTRAINT users_role_check,
    ADD CONSTRAINT users_role_check CHECK (role IN ('owner','production','receiving','quality','compliance','sales','viewer'));

ALTER TABLE app.attachments DROP CONSTRAINT attachments_kind_check,
    ADD CONSTRAINT attachments_kind_check CHECK (kind IN ('coa','weigh_ticket','cola','formula','lab_report','photo','spreadsheet','other'));

INSERT INTO app.number_sequences (key, format, period_reset) VALUES
    ('sales_order',    'SO-{N:5}',  'never'),
    ('standing_order', 'STO-{N:4}', 'never'),
    ('order_import',   'IMP-{N:4}', 'never')
ON CONFLICT (key) DO NOTHING;

-- List price per format, prefilled on order lines.
ALTER TABLE app.packaging_configurations
    ADD COLUMN default_unit_price numeric(12,2) CHECK (default_unit_price IS NULL OR default_unit_price >= 0);

-- Spreadsheet imports -------------------------------------------------------------------
-- One row per uploaded file. Rows are validated in the preview before anything is written;
-- an import can be undone (its orders deleted) while none of them has been fulfilled.
CREATE TABLE app.order_imports (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    number         text NOT NULL UNIQUE,
    attachment_id  bigint NOT NULL REFERENCES app.attachments(id),
    status         text NOT NULL DEFAULT 'previewed' CHECK (status IN ('previewed','imported','undone','abandoned')),
    mapping        jsonb NOT NULL DEFAULT '{}'::jsonb,   -- {field: column header}; the latest one prefills the next import
    future_status  text NOT NULL DEFAULT 'confirmed' CHECK (future_status IN ('draft','confirmed')),
    rows_total     int NOT NULL DEFAULT 0,
    rows_imported  int NOT NULL DEFAULT 0,
    rows_skipped   int NOT NULL DEFAULT 0,
    rows_failed    int NOT NULL DEFAULT 0,
    errors         jsonb NOT NULL DEFAULT '[]'::jsonb,   -- [{row, field, message}]
    customers_created int NOT NULL DEFAULT 0,
    created_by     bigint REFERENCES app.users(id),
    imported_by    bigint REFERENCES app.users(id),
    imported_at    timestamptz,
    undone_by      bigint REFERENCES app.users(id),
    undone_at      timestamptz,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER order_imports_touch BEFORE UPDATE ON app.order_imports FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

-- Standing orders -----------------------------------------------------------------------
-- Recurring demand. Future occurrences are projected (app.standing_order_occurrences);
-- an occurrence becomes a firm order once, through sales_orders.standing_occurrence_on.
CREATE TABLE app.standing_orders (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    number           text NOT NULL UNIQUE,
    customer_id      bigint NOT NULL REFERENCES app.customers(id),
    premises_id      bigint NOT NULL REFERENCES app.premises(id),
    frequency        text NOT NULL CHECK (frequency IN ('weekly','every_n_weeks','monthly')),
    interval_weeks   int,                                -- every_n_weeks only, 2 or more
    weekday          smallint,                           -- ISO 1 = Monday; weekly kinds only
    day_of_month     smallint,                           -- monthly only; 1 to 28 so every month has it
    starts_on        date NOT NULL,
    ends_on          date,
    active           boolean NOT NULL DEFAULT true,
    notes            text,
    created_by       bigint REFERENCES app.users(id),
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    CHECK (ends_on IS NULL OR ends_on >= starts_on),
    CHECK ((frequency = 'every_n_weeks') = (interval_weeks IS NOT NULL)),
    CHECK (interval_weeks IS NULL OR interval_weeks BETWEEN 2 AND 52),
    CHECK ((frequency IN ('weekly','every_n_weeks')) = (weekday IS NOT NULL)),
    CHECK (weekday IS NULL OR weekday BETWEEN 1 AND 7),
    CHECK ((frequency = 'monthly') = (day_of_month IS NOT NULL)),
    CHECK (day_of_month IS NULL OR day_of_month BETWEEN 1 AND 28)
);
CREATE INDEX standing_orders_customer_idx ON app.standing_orders (customer_id);
CREATE TRIGGER standing_orders_touch BEFORE UPDATE ON app.standing_orders FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

CREATE TABLE app.standing_order_lines (
    id                         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    standing_order_id          bigint NOT NULL REFERENCES app.standing_orders(id) ON DELETE CASCADE,
    line_no                    int NOT NULL,
    packaging_configuration_id bigint NOT NULL REFERENCES app.packaging_configurations(id),
    units                      int NOT NULL CHECK (units > 0),
    unit_price                 numeric(12,2) CHECK (unit_price IS NULL OR unit_price >= 0),
    UNIQUE (standing_order_id, line_no)
);

-- Customer orders -----------------------------------------------------------------------
CREATE TABLE app.sales_orders (
    id                     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    number                 text NOT NULL UNIQUE,
    customer_id            bigint NOT NULL REFERENCES app.customers(id),
    premises_id            bigint NOT NULL REFERENCES app.premises(id),
    status                 text NOT NULL DEFAULT 'draft'
                               CHECK (status IN ('draft','confirmed','in_fulfillment','shipped','closed','cancelled')),
    origin                 text NOT NULL DEFAULT 'entered' CHECK (origin IN ('entered','imported','standing','assistant')),
    destination_kind       text NOT NULL DEFAULT 'tax_paid_sale'
                               CHECK (destination_kind IN ('tax_paid_sale','taproom_transfer','in_bond_transfer','export')),
    ordered_on             date NOT NULL DEFAULT current_date,
    requested_on           date NOT NULL,                -- the due (ship) date
    customer_reference     text,                         -- the customer's PO number
    fulfilled_outside      boolean NOT NULL DEFAULT false,  -- history: shipped before or outside the system
    standing_order_id      bigint REFERENCES app.standing_orders(id),
    standing_occurrence_on date,
    order_import_id        bigint REFERENCES app.order_imports(id),
    import_row             int,                          -- the spreadsheet row of its first line
    notes                  text,
    created_by             bigint REFERENCES app.users(id),
    confirmed_by           bigint REFERENCES app.users(id),
    confirmed_at           timestamptz,
    closed_by              bigint REFERENCES app.users(id),
    closed_at              timestamptz,
    cancelled_by           bigint REFERENCES app.users(id),
    cancelled_at           timestamptz,
    cancel_reason          text,
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now(),
    CHECK (NOT fulfilled_outside OR status = 'closed'),
    CHECK ((standing_order_id IS NULL) = (standing_occurrence_on IS NULL)),
    CHECK ((origin = 'standing') = (standing_order_id IS NOT NULL)),
    CHECK ((origin = 'imported') = (order_import_id IS NOT NULL))
);
CREATE INDEX sales_orders_status_idx ON app.sales_orders (status, requested_on);
CREATE INDEX sales_orders_customer_idx ON app.sales_orders (customer_id, requested_on);
CREATE INDEX sales_orders_import_idx ON app.sales_orders (order_import_id) WHERE order_import_id IS NOT NULL;
-- An occurrence of a standing order becomes a firm order at most once.
CREATE UNIQUE INDEX sales_orders_standing_occurrence_key ON app.sales_orders (standing_order_id, standing_occurrence_on)
    WHERE standing_order_id IS NOT NULL AND status <> 'cancelled';
-- The same customer PO cannot be entered twice (also stops a spreadsheet being imported twice).
CREATE UNIQUE INDEX sales_orders_customer_reference_key ON app.sales_orders (customer_id, lower(customer_reference))
    WHERE customer_reference IS NOT NULL AND status <> 'cancelled';
CREATE TRIGGER sales_orders_touch BEFORE UPDATE ON app.sales_orders FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

CREATE TABLE app.sales_order_lines (
    id                         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sales_order_id             bigint NOT NULL REFERENCES app.sales_orders(id) ON DELETE CASCADE,
    line_no                    int NOT NULL,
    packaging_configuration_id bigint NOT NULL REFERENCES app.packaging_configurations(id),
    units_ordered              int NOT NULL CHECK (units_ordered > 0),
    unit_price                 numeric(12,2) CHECK (unit_price IS NULL OR unit_price >= 0),
    line_total                 numeric(14,2) GENERATED ALWAYS AS (units_ordered * unit_price) STORED,
    status                     text NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed_short','cancelled')),
    notes                      text,
    UNIQUE (sales_order_id, line_no)
);
CREATE INDEX sales_order_lines_config_idx ON app.sales_order_lines (packaging_configuration_id);

-- Links: packaging, shipping, production -----------------------------------------------
-- A packaging run created for order lines. One run can serve several orders of its format.
CREATE TABLE app.packaging_run_order_lines (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    packaging_run_id    bigint NOT NULL REFERENCES app.packaging_runs(id) ON DELETE CASCADE,
    sales_order_line_id bigint NOT NULL REFERENCES app.sales_order_lines(id),
    units               int NOT NULL CHECK (units > 0),
    UNIQUE (packaging_run_id, sales_order_line_id)
);
CREATE INDEX packaging_run_order_lines_line_idx ON app.packaging_run_order_lines (sales_order_line_id);

-- Shipping an order is a removal. Reversals copy the link, so a reversed shipment nets to zero.
ALTER TABLE app.removals ADD COLUMN sales_order_id bigint REFERENCES app.sales_orders(id);
ALTER TABLE app.removal_lines ADD COLUMN sales_order_line_id bigint REFERENCES app.sales_order_lines(id);
CREATE INDEX removals_sales_order_idx ON app.removals (sales_order_id) WHERE sales_order_id IS NOT NULL;
CREATE INDEX removal_lines_order_line_idx ON app.removal_lines (sales_order_line_id) WHERE sales_order_line_id IS NOT NULL;

-- Optional packaging plan on a production order: blank means bulk, decide later.
CREATE TABLE app.production_order_packages (
    id                         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    production_order_id        bigint NOT NULL REFERENCES app.production_orders(id) ON DELETE CASCADE,
    packaging_configuration_id bigint NOT NULL REFERENCES app.packaging_configurations(id),
    planned_units              int CHECK (planned_units IS NULL OR planned_units > 0),
    share_pct                  numeric(5,2) CHECK (share_pct IS NULL OR (share_pct > 0 AND share_pct <= 100)),
    sales_order_line_id        bigint REFERENCES app.sales_order_lines(id),
    CHECK ((planned_units IS NULL) <> (share_pct IS NULL))
);
CREATE INDEX production_order_packages_order_idx ON app.production_order_packages (production_order_id);

-- Forecasts -----------------------------------------------------------------------------
-- Units per format per ISO week. run_rate rows are regenerated from order history;
-- manual rows are the user's overrides and survive regeneration.
CREATE TABLE app.demand_forecasts (
    id                         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    packaging_configuration_id bigint NOT NULL REFERENCES app.packaging_configurations(id),
    week_start                 date NOT NULL CHECK (extract(isodow FROM week_start) = 1),
    units                      numeric(12,2) NOT NULL CHECK (units >= 0),
    method                     text NOT NULL CHECK (method IN ('run_rate','manual')),
    history_weeks              int CHECK (history_weeks IS NULL OR history_weeks BETWEEN 1 AND 104),
    note                       text,
    created_by                 bigint REFERENCES app.users(id),
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    UNIQUE (packaging_configuration_id, week_start)
);
CREATE TRIGGER demand_forecasts_touch BEFORE UPDATE ON app.demand_forecasts FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

-- Functions and views -------------------------------------------------------------------
-- Occurrence dates of active standing orders in [p_from, p_to].
CREATE OR REPLACE FUNCTION app.standing_order_occurrences(p_from date, p_to date)
RETURNS TABLE (standing_order_id bigint, occurs_on date)
LANGUAGE sql STABLE AS $$
    SELECT s.id, d::date
      FROM app.standing_orders s
      CROSS JOIN LATERAL generate_series(GREATEST(s.starts_on, p_from), LEAST(COALESCE(s.ends_on, p_to), p_to), interval '1 day') AS d
     WHERE s.active
       AND CASE s.frequency
             WHEN 'weekly'        THEN extract(isodow FROM d) = s.weekday
             WHEN 'every_n_weeks' THEN extract(isodow FROM d) = s.weekday
                                       AND ((d::date - date_trunc('week', s.starts_on)::date) / 7) % s.interval_weeks = 0
             WHEN 'monthly'       THEN extract(day FROM d) = s.day_of_month
           END
$$;

-- Each order line with what has shipped and what is open. Shipped = units on outbound removals
-- minus units on inbound ones (returns, reversals), counting posted and reversed documents, so a
-- reversal and its original cancel out. History fulfilled outside the system counts as shipped.
CREATE OR REPLACE VIEW app.v_sales_order_lines AS
SELECT ol.id, ol.sales_order_id, so.number AS order_number, so.status AS order_status, so.customer_id, c.name AS customer_name,
       so.premises_id, so.ordered_on, so.requested_on, so.origin, so.fulfilled_outside,
       ol.line_no, ol.packaging_configuration_id, pc.name AS configuration_name, pc.package_kind, pc.fill_volume_l, pc.units_per_case,
       pc.product_id, p.name AS product_name, pc.finished_item_id,
       ol.units_ordered, ol.unit_price, ol.line_total, ol.status AS line_status,
       CASE WHEN so.fulfilled_outside THEN ol.units_ordered ELSE COALESCE(sh.units_shipped, 0) END AS units_shipped,
       COALESCE(pk.units_packaging, 0) AS units_in_packaging_runs,
       CASE WHEN so.status IN ('confirmed','in_fulfillment') AND ol.status = 'open'
            THEN GREATEST(ol.units_ordered - COALESCE(sh.units_shipped, 0), 0) ELSE 0 END AS units_open
  FROM app.sales_order_lines ol
  JOIN app.sales_orders so ON so.id = ol.sales_order_id
  JOIN app.customers c ON c.id = so.customer_id
  JOIN app.packaging_configurations pc ON pc.id = ol.packaging_configuration_id
  JOIN app.products p ON p.id = pc.product_id
  LEFT JOIN LATERAL (
        SELECT SUM(CASE WHEN r.direction = 'out' THEN rl.units ELSE -rl.units END)::int AS units_shipped
          FROM app.removal_lines rl JOIN app.removals r ON r.id = rl.removal_id
         WHERE rl.sales_order_line_id = ol.id AND r.status IN ('posted','reversed')) sh ON true
  LEFT JOIN LATERAL (
        SELECT SUM(prol.units)::int AS units_packaging
          FROM app.packaging_run_order_lines prol JOIN app.packaging_runs pr ON pr.id = prol.packaging_run_id
         WHERE prol.sales_order_line_id = ol.id AND pr.status <> 'cancelled') pk ON true;

-- Demand by type over the next 26 weeks: firm open order lines, standing occurrences not yet
-- turned into orders, and forecast units not already covered by firm and standing demand in
-- the same format and week. Overdue firm demand is placed in the current week.
CREATE OR REPLACE VIEW app.v_demand AS
WITH horizon AS (
    SELECT current_date AS d_from, (date_trunc('week', current_date)::date + 7 * 26 - 1) AS d_to
), firm AS (
    SELECT 'firm'::text AS demand_type, l.sales_order_id AS source_id, l.order_number AS source_number,
           l.customer_id, l.customer_name, l.packaging_configuration_id, l.requested_on AS due_on,
           l.units_open::numeric AS units, l.unit_price
      FROM app.v_sales_order_lines l
     WHERE l.units_open > 0
), standing (demand_type, source_id, source_number, customer_id, customer_name, packaging_configuration_id, due_on, units, unit_price) AS (
    SELECT 'standing'::text, s.id, s.number, s.customer_id, c.name, sl.packaging_configuration_id, o.occurs_on,
           sl.units::numeric, COALESCE(sl.unit_price, pc.default_unit_price)
      FROM horizon h
      CROSS JOIN LATERAL app.standing_order_occurrences(h.d_from, h.d_to) o
      JOIN app.standing_orders s ON s.id = o.standing_order_id
      JOIN app.customers c ON c.id = s.customer_id
      JOIN app.standing_order_lines sl ON sl.standing_order_id = s.id
      JOIN app.packaging_configurations pc ON pc.id = sl.packaging_configuration_id
     WHERE NOT EXISTS (SELECT 1 FROM app.sales_orders so
                        WHERE so.standing_order_id = s.id AND so.standing_occurrence_on = o.occurs_on AND so.status <> 'cancelled')
), covered AS (
    SELECT packaging_configuration_id, GREATEST(date_trunc('week', due_on)::date, date_trunc('week', current_date)::date) AS week_start,
           SUM(units) AS units
      FROM (SELECT packaging_configuration_id, due_on, units FROM firm
            UNION ALL SELECT packaging_configuration_id, due_on, units FROM standing) x
     GROUP BY 1, 2
), forecast (demand_type, source_id, source_number, customer_id, customer_name, packaging_configuration_id, due_on, units, unit_price) AS (
    SELECT 'forecast'::text, f.id, NULL::text, NULL::bigint, NULL::text, f.packaging_configuration_id, f.week_start,
           GREATEST(f.units - COALESCE(cv.units, 0), 0), pc.default_unit_price
      FROM app.demand_forecasts f
      CROSS JOIN horizon h
      JOIN app.packaging_configurations pc ON pc.id = f.packaging_configuration_id
      LEFT JOIN covered cv ON cv.packaging_configuration_id = f.packaging_configuration_id AND cv.week_start = f.week_start
     WHERE f.week_start BETWEEN date_trunc('week', h.d_from)::date AND h.d_to
)
SELECT d.demand_type, d.source_id, d.source_number, d.customer_id, d.customer_name,
       d.packaging_configuration_id, pc.name AS configuration_name, pc.product_id, p.name AS product_name,
       d.due_on, GREATEST(date_trunc('week', d.due_on)::date, date_trunc('week', current_date)::date) AS week_start,
       d.units, d.units * pc.fill_volume_l AS volume_l, d.unit_price, d.units * d.unit_price AS value
  FROM (SELECT * FROM firm UNION ALL SELECT * FROM standing UNION ALL SELECT * FROM forecast) d
  JOIN app.packaging_configurations pc ON pc.id = d.packaging_configuration_id
  JOIN app.products p ON p.id = pc.product_id
 WHERE d.units > 0;
