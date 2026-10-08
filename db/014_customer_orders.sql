-- 014_customer_orders.sql — customer orders, standing orders, forecasts, spreadsheet imports, and the links that let
-- an order drive packaging, shipping and production. Orders are planning documents: nothing here touches the ledger.
-- A line is a product in pieces (or kg) with its weight and a price basis (D9); the package is optional.
SET search_path = app, public;

-- Spreadsheet imports -------------------------------------------------------------------
CREATE TABLE app.order_imports (
    id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    number            text NOT NULL UNIQUE,
    attachment_id     bigint NOT NULL REFERENCES app.attachments(id),
    status            text NOT NULL DEFAULT 'previewed' CHECK (status IN ('previewed','imported','undone','abandoned')),
    mapping           jsonb NOT NULL DEFAULT '{}'::jsonb,   -- {field: column header}; the latest one prefills the next import
    future_status     text NOT NULL DEFAULT 'confirmed' CHECK (future_status IN ('draft','confirmed')),
    rows_total        int NOT NULL DEFAULT 0,
    rows_imported     int NOT NULL DEFAULT 0,
    rows_skipped      int NOT NULL DEFAULT 0,
    rows_failed       int NOT NULL DEFAULT 0,
    errors            jsonb NOT NULL DEFAULT '[]'::jsonb,   -- [{row, field, message}]
    customers_created int NOT NULL DEFAULT 0,
    created_by        bigint REFERENCES app.users(id),
    imported_by       bigint REFERENCES app.users(id),
    imported_at       timestamptz,
    undone_by         bigint REFERENCES app.users(id),
    undone_at         timestamptz,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER order_imports_touch BEFORE UPDATE ON app.order_imports FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

-- Standing orders: recurring demand. Future occurrences are projected (app.standing_order_occurrences);
-- an occurrence becomes a firm order once, through sales_orders.standing_occurrence_on.
CREATE TABLE app.standing_orders (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    number           text NOT NULL UNIQUE,
    customer_id      bigint NOT NULL REFERENCES app.customers(id),
    site_id          bigint NOT NULL REFERENCES app.sites(id),
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
    product_id                 bigint NOT NULL REFERENCES app.products(id),
    packaging_configuration_id bigint REFERENCES app.packaging_configurations(id),
    qty_ordered                numeric(18,4) NOT NULL CHECK (qty_ordered > 0),
    weight_kg_ordered          numeric(14,3),
    unit_price                 numeric(12,4) CHECK (unit_price IS NULL OR unit_price >= 0),
    price_basis                text NOT NULL DEFAULT 'per_unit' CHECK (price_basis IN ('per_unit','per_kg','per_lb','per_cwt','per_package')),
    UNIQUE (standing_order_id, line_no)
);

-- Customer orders -----------------------------------------------------------------------
CREATE TABLE app.sales_orders (
    id                     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    number                 text NOT NULL UNIQUE,
    customer_id            bigint NOT NULL REFERENCES app.customers(id),
    site_id                bigint NOT NULL REFERENCES app.sites(id),
    status                 text NOT NULL DEFAULT 'draft'
                               CHECK (status IN ('draft','confirmed','in_fulfillment','shipped','closed','cancelled')),
    origin                 text NOT NULL DEFAULT 'entered' CHECK (origin IN ('entered','imported','standing','assistant')),
    ordered_on             date NOT NULL DEFAULT current_date,
    requested_on           date NOT NULL,                -- the due (ship) date
    customer_reference     text,                         -- the customer's PO number
    ship_to_address        text,
    fulfilled_outside      boolean NOT NULL DEFAULT false,  -- history: shipped before or outside the system
    standing_order_id      bigint REFERENCES app.standing_orders(id),
    standing_occurrence_on date,
    order_import_id        bigint REFERENCES app.order_imports(id),
    import_row             int,
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
CREATE UNIQUE INDEX sales_orders_standing_occurrence_key ON app.sales_orders (standing_order_id, standing_occurrence_on)
    WHERE standing_order_id IS NOT NULL AND status <> 'cancelled';
CREATE UNIQUE INDEX sales_orders_customer_reference_key ON app.sales_orders (customer_id, lower(customer_reference))
    WHERE customer_reference IS NOT NULL AND status <> 'cancelled';
CREATE TRIGGER sales_orders_touch BEFORE UPDATE ON app.sales_orders FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

-- A line: a product, how much (pieces or kg, with weight), how packed (optional), at what price on what basis.
-- line_total: per_unit × qty, per_kg × weight, per_lb and per_cwt from the weight, per_package × packages.
CREATE TABLE app.sales_order_lines (
    id                         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sales_order_id             bigint NOT NULL REFERENCES app.sales_orders(id) ON DELETE CASCADE,
    line_no                    int NOT NULL,
    product_id                 bigint NOT NULL REFERENCES app.products(id),
    packaging_configuration_id bigint REFERENCES app.packaging_configurations(id),
    qty_ordered                numeric(18,4) NOT NULL CHECK (qty_ordered > 0),
    weight_kg_ordered          numeric(14,3),
    package_qty_base           numeric(14,4),                                   -- pieces per package, copied from the configuration
    unit_price                 numeric(12,4) CHECK (unit_price IS NULL OR unit_price >= 0),
    price_basis                text NOT NULL DEFAULT 'per_unit' CHECK (price_basis IN ('per_unit','per_kg','per_lb','per_cwt','per_package')),
    line_total                 numeric(14,2) GENERATED ALWAYS AS (
                                   CASE price_basis
                                     WHEN 'per_unit'    THEN qty_ordered * unit_price
                                     WHEN 'per_kg'      THEN weight_kg_ordered * unit_price
                                     WHEN 'per_lb'      THEN weight_kg_ordered / 0.45359237 * unit_price
                                     WHEN 'per_cwt'     THEN weight_kg_ordered / 45.359237 * unit_price
                                     WHEN 'per_package' THEN qty_ordered / NULLIF(package_qty_base, 0) * unit_price
                                   END) STORED,
    requested_on               date,                                            -- the line's own due date, else the order's
    status                     text NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed_short','cancelled')),
    notes                      text,
    UNIQUE (sales_order_id, line_no)
);
CREATE INDEX sales_order_lines_product_idx ON app.sales_order_lines (product_id);

-- Links: packaging, shipping, production -----------------------------------------------
CREATE TABLE app.packaging_run_order_lines (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    packaging_run_id    bigint NOT NULL REFERENCES app.packaging_runs(id) ON DELETE CASCADE,
    sales_order_line_id bigint NOT NULL REFERENCES app.sales_order_lines(id),
    qty_base            numeric(18,4) NOT NULL CHECK (qty_base > 0),
    UNIQUE (packaging_run_id, sales_order_line_id)
);
CREATE INDEX packaging_run_order_lines_line_idx ON app.packaging_run_order_lines (sales_order_line_id);

-- Shipping an order. Reversals copy the link, so a reversed shipment nets to zero.
ALTER TABLE app.shipments ADD COLUMN sales_order_id bigint REFERENCES app.sales_orders(id);
ALTER TABLE app.shipment_lines ADD COLUMN sales_order_line_id bigint REFERENCES app.sales_order_lines(id);
CREATE INDEX shipments_sales_order_idx ON app.shipments (sales_order_id) WHERE sales_order_id IS NOT NULL;
CREATE INDEX shipment_lines_order_line_idx ON app.shipment_lines (sales_order_line_id) WHERE sales_order_line_id IS NOT NULL;

-- A production order made for an order line, and its packaging plan.
ALTER TABLE app.production_orders ADD COLUMN sales_order_line_id bigint REFERENCES app.sales_order_lines(id);
CREATE INDEX production_orders_order_line_idx ON app.production_orders (sales_order_line_id) WHERE sales_order_line_id IS NOT NULL;

CREATE TABLE app.production_order_packages (
    id                         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    production_order_id        bigint NOT NULL REFERENCES app.production_orders(id) ON DELETE CASCADE,
    packaging_configuration_id bigint NOT NULL REFERENCES app.packaging_configurations(id),
    planned_qty_base           numeric(18,4) CHECK (planned_qty_base IS NULL OR planned_qty_base > 0),
    share_pct                  numeric(5,2) CHECK (share_pct IS NULL OR (share_pct > 0 AND share_pct <= 100)),
    sales_order_line_id        bigint REFERENCES app.sales_order_lines(id),
    CHECK ((planned_qty_base IS NULL) <> (share_pct IS NULL))
);
CREATE INDEX production_order_packages_order_idx ON app.production_order_packages (production_order_id);

-- Forecasts: quantity per product per ISO week. run_rate rows are regenerated from order history;
-- manual rows are the user's overrides and survive regeneration.
CREATE TABLE app.demand_forecasts (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id    bigint NOT NULL REFERENCES app.products(id),
    week_start    date NOT NULL CHECK (extract(isodow FROM week_start) = 1),
    qty           numeric(14,4) NOT NULL CHECK (qty >= 0),
    weight_kg     numeric(14,3),
    method        text NOT NULL CHECK (method IN ('run_rate','manual')),
    history_weeks int CHECK (history_weeks IS NULL OR history_weeks BETWEEN 1 AND 104),
    note          text,
    created_by    bigint REFERENCES app.users(id),
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (product_id, week_start)
);
CREATE TRIGGER demand_forecasts_touch BEFORE UPDATE ON app.demand_forecasts FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

-- Functions and views -------------------------------------------------------------------
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

-- Each order line with what has shipped and what is open. Shipped = quantity on outbound shipments minus inbound
-- (returns, reversals), counting posted and reversed documents, so a reversal and its original cancel out.
CREATE OR REPLACE VIEW app.v_sales_order_lines AS
SELECT ol.id, ol.sales_order_id, so.number AS order_number, so.status AS order_status, so.customer_id, c.name AS customer_name,
       so.site_id, so.ordered_on, COALESCE(ol.requested_on, so.requested_on) AS requested_on, so.origin, so.fulfilled_outside,
       ol.line_no, ol.product_id, p.name AS product_name, ol.packaging_configuration_id, pc.name AS configuration_name, pc.package_kind,
       ol.qty_ordered, ol.weight_kg_ordered, ol.package_qty_base, ol.unit_price, ol.price_basis, ol.line_total, ol.status AS line_status,
       CASE WHEN so.fulfilled_outside THEN ol.qty_ordered ELSE COALESCE(sh.qty_shipped, 0) END AS qty_shipped,
       COALESCE(sh.weight_shipped, 0) AS weight_kg_shipped,
       COALESCE(pk.qty_packaging, 0) AS qty_in_packaging_runs,
       COALESCE(pr.qty_in_production, 0) AS qty_in_production,
       CASE WHEN so.status IN ('confirmed','in_fulfillment') AND ol.status = 'open'
            THEN GREATEST(ol.qty_ordered - COALESCE(sh.qty_shipped, 0), 0) ELSE 0 END AS qty_open
  FROM app.sales_order_lines ol
  JOIN app.sales_orders so ON so.id = ol.sales_order_id
  JOIN app.customers c ON c.id = so.customer_id
  JOIN app.products p ON p.id = ol.product_id
  LEFT JOIN app.packaging_configurations pc ON pc.id = ol.packaging_configuration_id
  LEFT JOIN LATERAL (
        SELECT SUM(CASE WHEN s.direction = 'out' THEN COALESCE(sl.product_qty_base, sl.qty_base) ELSE -COALESCE(sl.product_qty_base, sl.qty_base) END) AS qty_shipped,
               SUM(CASE WHEN s.direction = 'out' THEN COALESCE(sl.weight_kg, 0) ELSE -COALESCE(sl.weight_kg, 0) END) AS weight_shipped
          FROM app.shipment_lines sl JOIN app.shipments s ON s.id = sl.shipment_id
         WHERE sl.sales_order_line_id = ol.id AND s.status IN ('posted','reversed')) sh ON true
  LEFT JOIN LATERAL (
        SELECT SUM(prol.qty_base) AS qty_packaging
          FROM app.packaging_run_order_lines prol JOIN app.packaging_runs pr ON pr.id = prol.packaging_run_id
         WHERE prol.sales_order_line_id = ol.id AND pr.status <> 'cancelled') pk ON true
  LEFT JOIN LATERAL (
        SELECT SUM(po.planned_qty_base) AS qty_in_production
          FROM app.production_orders po WHERE po.sales_order_line_id = ol.id AND po.status NOT IN ('cancelled','closed')) pr ON true;

-- Demand by type over the next 26 weeks: firm open order lines, standing occurrences not yet turned into orders,
-- and forecast quantities not already covered by firm and standing demand for the same product and week.
CREATE OR REPLACE VIEW app.v_demand AS
WITH horizon AS (
    SELECT current_date AS d_from, (date_trunc('week', current_date)::date + 7 * 26 - 1) AS d_to
), firm AS (
    SELECT 'firm'::text AS demand_type, l.sales_order_id AS source_id, l.order_number AS source_number,
           l.customer_id, l.customer_name, l.product_id, l.requested_on AS due_on,
           l.qty_open::numeric AS qty, l.weight_kg_ordered, l.unit_price, l.price_basis
      FROM app.v_sales_order_lines l
     WHERE l.qty_open > 0
), standing (demand_type, source_id, source_number, customer_id, customer_name, product_id, due_on, qty, weight_kg_ordered, unit_price, price_basis) AS (
    SELECT 'standing'::text, s.id, s.number, s.customer_id, c.name, sl.product_id, o.occurs_on,
           sl.qty_ordered::numeric, sl.weight_kg_ordered, sl.unit_price, sl.price_basis
      FROM horizon h
      CROSS JOIN LATERAL app.standing_order_occurrences(h.d_from, h.d_to) o
      JOIN app.standing_orders s ON s.id = o.standing_order_id
      JOIN app.customers c ON c.id = s.customer_id
      JOIN app.standing_order_lines sl ON sl.standing_order_id = s.id
     WHERE NOT EXISTS (SELECT 1 FROM app.sales_orders so
                        WHERE so.standing_order_id = s.id AND so.standing_occurrence_on = o.occurs_on AND so.status <> 'cancelled')
), covered AS (
    SELECT product_id, GREATEST(date_trunc('week', due_on)::date, date_trunc('week', current_date)::date) AS week_start, SUM(qty) AS qty
      FROM (SELECT product_id, due_on, qty FROM firm UNION ALL SELECT product_id, due_on, qty FROM standing) x
     GROUP BY 1, 2
), forecast (demand_type, source_id, source_number, customer_id, customer_name, product_id, due_on, qty, weight_kg_ordered, unit_price, price_basis) AS (
    SELECT 'forecast'::text, f.id, NULL::text, NULL::bigint, NULL::text, f.product_id, f.week_start,
           GREATEST(f.qty - COALESCE(cv.qty, 0), 0), f.weight_kg, NULL::numeric, 'per_unit'
      FROM app.demand_forecasts f
      CROSS JOIN horizon h
      LEFT JOIN covered cv ON cv.product_id = f.product_id AND cv.week_start = f.week_start
     WHERE f.week_start BETWEEN date_trunc('week', h.d_from)::date AND h.d_to
)
SELECT d.demand_type, d.source_id, d.source_number, d.customer_id, d.customer_name,
       d.product_id, p.name AS product_name, p.family,
       d.due_on, GREATEST(date_trunc('week', d.due_on)::date, date_trunc('week', current_date)::date) AS week_start,
       d.qty, d.weight_kg_ordered AS weight_kg, d.unit_price, d.price_basis
  FROM (SELECT * FROM firm UNION ALL SELECT * FROM standing UNION ALL SELECT * FROM forecast) d
  JOIN app.products p ON p.id = d.product_id
 WHERE d.qty > 0;
