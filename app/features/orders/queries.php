<?php
declare(strict_types=1);

const ORDER_STATUSES = ['draft' => 'Draft', 'confirmed' => 'Confirmed', 'in_fulfillment' => 'In fulfillment', 'shipped' => 'Shipped', 'closed' => 'Closed', 'cancelled' => 'Cancelled'];
// List filter: "open" is every order still to be filled (draft, confirmed, in fulfillment).
const ORDER_STATUS_FILTERS = ['open' => 'Open orders'] + ORDER_STATUSES;
const ORDER_OPEN_STATUSES = ['draft', 'confirmed', 'in_fulfillment'];
// Locked colors (docs/cidery/12-customer-orders-design.md): closed is secondary here, unlike purchase orders.
const ORDER_STATUS_COLORS = ['draft' => 'dark', 'confirmed' => 'info', 'in_fulfillment' => 'info', 'shipped' => 'success', 'closed' => 'secondary', 'cancelled' => 'danger',
                             'open' => 'info', 'closed_short' => 'warning'];
const ORDER_DESTINATIONS = ['tax_paid_sale' => 'Tax-paid sale', 'taproom_transfer' => 'Taproom transfer', 'in_bond_transfer' => 'In-bond transfer', 'export' => 'Export'];
const ORDER_ORIGINS = ['entered' => 'Entered', 'imported' => 'Imported', 'standing' => 'Standing order', 'assistant' => 'Assistant'];
const ORDER_SORTS = ['number' => 'so.number', 'customer' => 'c.name', 'status' => 'so.status', 'ordered_on' => 'so.ordered_on', 'requested_on' => 'so.requested_on'];

function order_status_color(string $status): string
{
    return ORDER_STATUS_COLORS[$status] ?? 'secondary';
}

function order_status_badge(string $status, ?string $id = null): string
{
    return badge(ORDER_STATUSES[$status] ?? humanize($status), order_status_color($status), $id);
}

function find_orders(PDO $pdo, string $search = '', string $sort = 'requested_on', int $page = 1, ?string $status = 'open', ?int $customerId = null, ?int $productId = null): array
{
    $where = [];
    $params = [];
    if ($search !== '') {
        $where[] = '(so.number ILIKE :s OR c.name ILIKE :s OR so.customer_reference ILIKE :s)';
        $params['s'] = '%' . $search . '%';
    }
    if ($status === 'open') {
        $where[] = "so.status IN ('draft', 'confirmed', 'in_fulfillment')";
    } elseif ($status !== null && $status !== '') {
        $where[] = 'so.status = :status';
        $params['status'] = $status;
    }
    if ($customerId !== null) {
        $where[] = 'so.customer_id = :customer_id';
        $params['customer_id'] = $customerId;
    }
    if ($productId !== null) {
        $where[] = 'EXISTS (SELECT 1 FROM app.sales_order_lines ol JOIN app.packaging_configurations pc ON pc.id = ol.packaging_configuration_id
                             WHERE ol.sales_order_id = so.id AND pc.product_id = :product_id)';
        $params['product_id'] = $productId;
    }
    $whereSql = $where === [] ? '' : ' WHERE ' . implode(' AND ', $where);
    $from = ' FROM app.sales_orders so JOIN app.customers c ON c.id = so.customer_id';
    return paged_query(
        $pdo,
        "SELECT so.id, so.number, so.status, so.origin, so.ordered_on, so.requested_on, so.customer_reference, so.customer_id, c.name AS customer_name,
                t.units_ordered, t.units_open, t.order_value,
                (so.requested_on < current_date AND so.status IN ('confirmed', 'in_fulfillment')) AS overdue"
            . $from . "
           LEFT JOIN LATERAL (SELECT SUM(l.units_ordered) AS units_ordered, SUM(l.units_open) AS units_open, SUM(l.line_total) AS order_value
                                FROM app.v_sales_order_lines l WHERE l.sales_order_id = so.id AND l.line_status <> 'cancelled') t ON true"
            . $whereSql . ' ORDER BY ' . order_by($sort, ORDER_SORTS, 'requested_on') . ', so.id',
        'SELECT count(*)' . $from . $whereSql,
        $params,
        $page
    );
}

function find_order(PDO $pdo, int $id): ?array
{
    $statement = $pdo->prepare(<<<'SQL'
        SELECT so.*, c.name AS customer_name, pr.name AS premises_name,
               uc.display_name AS created_by_name, uf.display_name AS confirmed_by_name,
               ux.display_name AS closed_by_name, uk.display_name AS cancelled_by_name,
               st.number AS standing_order_number, oi.number AS import_number,
               t.units_ordered, t.units_shipped, t.units_open, t.order_value,
               (so.requested_on < current_date AND so.status IN ('confirmed', 'in_fulfillment')) AS overdue
        FROM app.sales_orders so
        JOIN app.customers c ON c.id = so.customer_id
        JOIN app.premises pr ON pr.id = so.premises_id
        LEFT JOIN app.users uc ON uc.id = so.created_by
        LEFT JOIN app.users uf ON uf.id = so.confirmed_by
        LEFT JOIN app.users ux ON ux.id = so.closed_by
        LEFT JOIN app.users uk ON uk.id = so.cancelled_by
        LEFT JOIN app.standing_orders st ON st.id = so.standing_order_id
        LEFT JOIN app.order_imports oi ON oi.id = so.order_import_id
        LEFT JOIN LATERAL (SELECT SUM(l.units_ordered) AS units_ordered, SUM(l.units_shipped) AS units_shipped,
                                  SUM(l.units_open) AS units_open, SUM(l.line_total) AS order_value
                             FROM app.v_sales_order_lines l WHERE l.sales_order_id = so.id AND l.line_status <> 'cancelled') t ON true
        WHERE so.id = :id
    SQL);
    $statement->execute(['id' => $id]);
    $row = $statement->fetch();
    return $row === false ? null : $row;
}

function find_order_lines(PDO $pdo, int $orderId): array
{
    $statement = $pdo->prepare(<<<'SQL'
        SELECT l.id, l.line_no, l.packaging_configuration_id, l.configuration_name, l.package_kind, l.units_per_case, l.product_id, l.product_name,
               l.units_ordered, l.units_shipped, l.units_in_packaging_runs, l.units_open, l.unit_price, l.line_total, l.line_status,
               ol.notes
        FROM app.v_sales_order_lines l
        JOIN app.sales_order_lines ol ON ol.id = l.id
        WHERE l.sales_order_id = :id
        ORDER BY l.line_no
    SQL);
    $statement->execute(['id' => $orderId]);
    return $statement->fetchAll();
}

/** Packaging runs created for this order's lines (filled from step 3 on). */
function find_order_packaging_runs(PDO $pdo, int $orderId): array
{
    $statement = $pdo->prepare(<<<'SQL'
        SELECT pr.id, pr.number, pr.status, pr.run_on, pr.units_out, pc.name AS configuration_name, b.number AS batch_number, SUM(prol.units) AS units_for_order
        FROM app.packaging_run_order_lines prol
        JOIN app.sales_order_lines ol ON ol.id = prol.sales_order_line_id
        JOIN app.packaging_runs pr ON pr.id = prol.packaging_run_id
        JOIN app.packaging_configurations pc ON pc.id = pr.packaging_configuration_id
        JOIN app.batches b ON b.id = pr.batch_id
        WHERE ol.sales_order_id = :id
        GROUP BY pr.id, pc.name, b.number
        ORDER BY pr.run_on DESC, pr.id DESC
    SQL);
    $statement->execute(['id' => $orderId]);
    return $statement->fetchAll();
}

/** Shipments (removals) for this order, returns and reversals included. */
function find_order_removals(PDO $pdo, int $orderId): array
{
    $statement = $pdo->prepare(<<<'SQL'
        SELECT r.id, r.number, r.direction, r.destination_kind, r.status, r.removed_at, r.reference,
               (SELECT COALESCE(SUM(rl.units), 0) FROM app.removal_lines rl WHERE rl.removal_id = r.id) AS units
        FROM app.removals r WHERE r.sales_order_id = :id
        ORDER BY r.removed_at DESC, r.id DESC
    SQL);
    $statement->execute(['id' => $orderId]);
    return $statement->fetchAll();
}

function insert_order(PDO $pdo, array $order, int $createdBy): array
{
    $statement = $pdo->prepare(<<<'SQL'
        INSERT INTO app.sales_orders (number, customer_id, premises_id, status, destination_kind, ordered_on, requested_on, customer_reference,
                                      fulfilled_outside, notes, created_by, closed_by, closed_at)
        VALUES (app.next_number('sales_order'), :customer_id, :premises_id, :status, :destination, :ordered_on, :requested_on, :reference,
                :outside, :notes, :by, CASE WHEN :outside THEN CAST(:by AS bigint) END, CASE WHEN :outside THEN now() END)
        RETURNING id, number, customer_id, premises_id, status, destination_kind, ordered_on, requested_on, customer_reference, fulfilled_outside, notes
    SQL);
    $statement->execute([
        'customer_id' => $order['customer_id'], 'premises_id' => $order['premises_id'], 'status' => $order['fulfilled_outside'] ? 'closed' : 'draft',
        'destination' => $order['destination_kind'], 'ordered_on' => $order['ordered_on'], 'requested_on' => $order['requested_on'],
        'reference' => $order['customer_reference'] ?: null, 'outside' => $order['fulfilled_outside'] ? 't' : 'f', 'notes' => $order['notes'] ?: null, 'by' => $createdBy,
    ]);
    return $statement->fetch();
}

/** Draft and confirmed orders can change; a draft can also be recorded as history fulfilled outside the system. */
function update_order(PDO $pdo, int $id, array $order, int $userId): array
{
    $statement = $pdo->prepare(<<<'SQL'
        UPDATE app.sales_orders
        SET customer_id = :customer_id, premises_id = :premises_id, destination_kind = :destination, ordered_on = :ordered_on, requested_on = :requested_on,
            customer_reference = :reference, notes = :notes,
            fulfilled_outside = :outside,
            status = CASE WHEN :outside THEN 'closed' ELSE status END,
            closed_by = CASE WHEN :outside THEN CAST(:by AS bigint) ELSE closed_by END,
            closed_at = CASE WHEN :outside THEN now() ELSE closed_at END
        WHERE id = :id AND (status = 'draft' OR (status = 'confirmed' AND NOT :outside))
        RETURNING id, number, customer_id, premises_id, status, destination_kind, ordered_on, requested_on, customer_reference, fulfilled_outside, notes
    SQL);
    $statement->execute([
        'id' => $id, 'customer_id' => $order['customer_id'], 'premises_id' => $order['premises_id'], 'destination' => $order['destination_kind'],
        'ordered_on' => $order['ordered_on'], 'requested_on' => $order['requested_on'], 'reference' => $order['customer_reference'] ?: null,
        'notes' => $order['notes'] ?: null, 'outside' => $order['fulfilled_outside'] ? 't' : 'f', 'by' => $userId,
    ]);
    $row = $statement->fetch();
    if ($row === false) {
        throw new RuntimeException('Only draft or confirmed orders can be edited, and only a draft can be recorded as fulfilled outside the system.');
    }
    return $row;
}

/**
 * Save the form's lines in place: existing lines (by id) are updated, new ones inserted, and lines
 * left off the form deleted. A line that a packaging run or shipment points at cannot be removed,
 * moved to another format, or cut below what has shipped or is in packaging runs.
 * Each line: id?, packaging_configuration_id, units_ordered, unit_price, notes.
 */
function save_order_lines(PDO $pdo, int $orderId, array $lines): void
{
    $existing = [];
    foreach (find_order_lines($pdo, $orderId) as $row) {
        $existing[(int) $row['id']] = $row;
    }
    $kept = [];
    foreach ($lines as $line) {
        if (!empty($line['id']) && isset($existing[(int) $line['id']])) {
            $kept[(int) $line['id']] = true;
        }
    }
    foreach ($existing as $lineId => $row) {
        if (isset($kept[$lineId])) {
            continue;
        }
        if ((int) $row['units_shipped'] > 0 || (int) $row['units_in_packaging_runs'] > 0 || order_line_is_linked($pdo, $lineId)) {
            throw new RuntimeException('Line ' . $row['line_no'] . ' (' . $row['configuration_name'] . ') has packaging runs or shipments and cannot be removed.');
        }
        $pdo->prepare('DELETE FROM app.sales_order_lines WHERE id = :id')->execute(['id' => $lineId]);
    }
    $update = $pdo->prepare('UPDATE app.sales_order_lines SET line_no = :line_no, packaging_configuration_id = :config, units_ordered = :units, unit_price = :price, notes = :notes WHERE id = :id AND sales_order_id = :order');
    $insert = $pdo->prepare('INSERT INTO app.sales_order_lines (sales_order_id, line_no, packaging_configuration_id, units_ordered, unit_price, notes) VALUES (:order, :line_no, :config, :units, :price, :notes)');
    // Renumber in two passes so the (order, line_no) key never collides mid-update.
    $pdo->prepare('UPDATE app.sales_order_lines SET line_no = line_no + 10000 WHERE sales_order_id = :order')->execute(['order' => $orderId]);
    foreach (array_values($lines) as $index => $line) {
        $params = ['order' => $orderId, 'line_no' => $index + 1, 'config' => $line['packaging_configuration_id'], 'units' => $line['units_ordered'],
                   'price' => $line['unit_price'], 'notes' => $line['notes'] ?: null];
        $lineId = (int) ($line['id'] ?? 0);
        if ($lineId !== 0 && isset($existing[$lineId])) {
            $row = $existing[$lineId];
            $floor = max((int) $row['units_shipped'], (int) $row['units_in_packaging_runs']);
            if ($floor > 0 && (int) $row['packaging_configuration_id'] !== (int) $line['packaging_configuration_id']) {
                throw new RuntimeException('Line ' . $row['line_no'] . ' has packaging runs or shipments; its format cannot change.');
            }
            if ($line['units_ordered'] < $floor) {
                throw new RuntimeException('Line ' . $row['line_no'] . ' cannot drop below ' . $floor . ' units, already shipped or in packaging runs.');
            }
            $update->execute($params + ['id' => $lineId]);
        } else {
            $insert->execute($params);
        }
    }
}

function order_line_is_linked(PDO $pdo, int $lineId): bool
{
    $statement = $pdo->prepare(<<<'SQL'
        SELECT EXISTS (SELECT 1 FROM app.packaging_run_order_lines WHERE sales_order_line_id = :id)
            OR EXISTS (SELECT 1 FROM app.removal_lines WHERE sales_order_line_id = :id)
            OR EXISTS (SELECT 1 FROM app.production_order_packages WHERE sales_order_line_id = :id)
    SQL);
    $statement->execute(['id' => $lineId]);
    return (bool) $statement->fetchColumn();
}

function confirm_order(PDO $pdo, int $id, int $userId): array
{
    $statement = $pdo->prepare(<<<'SQL'
        UPDATE app.sales_orders SET status = 'confirmed', confirmed_by = :by, confirmed_at = now()
        WHERE id = :id AND status = 'draft' AND EXISTS (SELECT 1 FROM app.sales_order_lines WHERE sales_order_id = :id)
        RETURNING id, number, status, confirmed_at
    SQL);
    $statement->execute(['id' => $id, 'by' => $userId]);
    $row = $statement->fetch();
    if ($row === false) {
        throw new RuntimeException('Only a draft order with at least one line can be confirmed.');
    }
    return $row;
}

/** Draft or confirmed, with nothing shipped and no packaging run still standing for it. */
function cancel_order(PDO $pdo, int $id, string $reason, int $userId): array
{
    $statement = $pdo->prepare(<<<'SQL'
        UPDATE app.sales_orders SET status = 'cancelled', cancelled_by = :by, cancelled_at = now(), cancel_reason = :reason
        WHERE id = :id AND status IN ('draft', 'confirmed')
          AND NOT EXISTS (SELECT 1 FROM app.v_sales_order_lines l WHERE l.sales_order_id = :id AND (l.units_shipped > 0 OR l.units_in_packaging_runs > 0))
          AND NOT EXISTS (SELECT 1 FROM app.removals r WHERE r.sales_order_id = :id AND r.status IN ('draft', 'posted'))
        RETURNING id, number, status, cancel_reason
    SQL);
    $statement->execute(['id' => $id, 'by' => $userId, 'reason' => $reason]);
    $row = $statement->fetch();
    if ($row === false) {
        throw new RuntimeException('Only a draft or confirmed order with nothing shipped and no packaging runs or draft shipments can be cancelled.');
    }
    $pdo->prepare("UPDATE app.sales_order_lines SET status = 'cancelled' WHERE sales_order_id = :id")->execute(['id' => $id]);
    return $row;
}

/** Close an order: lines still open are closed short. */
function close_order(PDO $pdo, int $id, int $userId): array
{
    $statement = $pdo->prepare(<<<'SQL'
        UPDATE app.sales_orders SET status = 'closed', closed_by = :by, closed_at = now()
        WHERE id = :id AND status IN ('confirmed', 'in_fulfillment', 'shipped')
          AND NOT EXISTS (SELECT 1 FROM app.removals r WHERE r.sales_order_id = :id AND r.status = 'draft')
        RETURNING id, number, status, closed_at
    SQL);
    $statement->execute(['id' => $id, 'by' => $userId]);
    $row = $statement->fetch();
    if ($row === false) {
        throw new RuntimeException('Only a confirmed, in-fulfillment or shipped order with no draft shipment can be closed.');
    }
    $pdo->prepare(<<<'SQL'
        UPDATE app.sales_order_lines ol SET status = 'closed_short'
        FROM app.v_sales_order_lines v
        WHERE v.id = ol.id AND ol.sales_order_id = :id AND ol.status = 'open' AND v.units_shipped < ol.units_ordered
    SQL)->execute(['id' => $id]);
    return $row;
}

/** Active customers: id => [name, default_destination]. Keeps a given inactive customer (editing an old order). */
function order_customer_options(PDO $pdo, ?int $keepId = null): array
{
    $statement = $pdo->prepare('SELECT id, name, default_destination FROM app.customers WHERE active OR id = :keep ORDER BY name');
    $statement->execute(['keep' => $keepId]);
    $out = [];
    foreach ($statement->fetchAll() as $row) {
        $out[(int) $row['id']] = $row;
    }
    return $out;
}

/** The destination an order takes from its customer; customers whose default is not a sale fall back to a tax-paid sale. */
function order_default_destination(?array $customer): string
{
    $destination = (string) ($customer['default_destination'] ?? '');
    return isset(ORDER_DESTINATIONS[$destination]) ? $destination : 'tax_paid_sale';
}

/** Orderable formats: active packaging configurations of active products, plus any already on the order. */
function order_format_catalog(PDO $pdo, array $keepIds = []): array
{
    $keep = '{' . implode(',', array_map('intval', $keepIds)) . '}';
    $statement = $pdo->prepare(<<<'SQL'
        SELECT pc.id, pc.name, pc.package_kind, pc.fill_volume_l, pc.units_per_case, pc.default_unit_price, pc.finished_item_id,
               p.id AS product_id, p.name AS product_name
        FROM app.packaging_configurations pc JOIN app.products p ON p.id = pc.product_id
        WHERE (pc.active AND p.status = 'active') OR pc.id = ANY (CAST(:keep AS bigint[]))
        ORDER BY p.name, pc.name
    SQL);
    $statement->execute(['keep' => $keep]);
    $out = [];
    foreach ($statement->fetchAll() as $row) {
        $out[(int) $row['id']] = $row;
    }
    return $out;
}

/**
 * What stands behind a format right now: released finished units available, units promised to other
 * open orders, and the product's bulk volume in active batches (liters).
 */
function order_format_availability(PDO $pdo, int $configurationId, ?int $excludeOrderId = null): array
{
    $statement = $pdo->prepare(<<<'SQL'
        SELECT
            (SELECT COALESCE(SUM(fs.units_available), 0) FROM app.v_finished_stock fs JOIN app.lots l ON l.id = fs.lot_id
              WHERE fs.packaging_configuration_id = :c AND l.quality_status = 'released') AS units_available,
            (SELECT COALESCE(SUM(v.units_open), 0) FROM app.v_sales_order_lines v
              WHERE v.packaging_configuration_id = :c AND v.sales_order_id IS DISTINCT FROM CAST(:exclude AS bigint)) AS units_promised,
            (SELECT COALESCE(SUM(b.current_volume_l), 0) FROM app.batches b
              WHERE b.status = 'active' AND b.product_id = (SELECT product_id FROM app.packaging_configurations WHERE id = :c)) AS bulk_volume_l
    SQL);
    $statement->execute(['c' => $configurationId, 'exclude' => $excludeOrderId]);
    return $statement->fetch();
}
