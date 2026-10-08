<?php
declare(strict_types=1);
/**
 * The planning projection as JSON, for the records MCP server (one engine for the screens and the assistant).
 * Usage: php scripts/planning-json.php <firm|standing|all> [weeks]
 * Connects with the read-only records role from the environment (PROCESSCORE_DB_HOST, PROCESSCORE_DB_PORT, PROCESSCORE_DB_NAME,
 * PROCESSCORE_RECORDS_DB_USER, PROCESSCORE_RECORDS_DB_PASSWORD, as in config/services.env); it never reads config/local.php.
 */
require_once dirname(__DIR__) . '/vendor/autoload.php';
$config = require dirname(__DIR__) . '/config/application.php';
foreach (['host' => 'PROCESSCORE_DB_HOST', 'port' => 'PROCESSCORE_DB_PORT', 'name' => 'PROCESSCORE_DB_NAME', 'user' => 'PROCESSCORE_RECORDS_DB_USER', 'password' => 'PROCESSCORE_RECORDS_DB_PASSWORD'] as $key => $env) {
    $value = getenv($env);
    if ($value === false || $value === '') {
        fwrite(STDERR, "Missing $env in the environment.\n");
        exit(2);
    }
    $config['db'][$key] = $value;
}
$GLOBALS['__config'] = $config;
function config(string $key, mixed $default = null): mixed { $v = $GLOBALS['__config']; foreach (explode('.', $key) as $p) { if (!is_array($v) || !array_key_exists($p, $v)) { return $default; } $v = $v[$p]; } return $v; }
foreach (['db', 'http', 'ui', 'units', 'list'] as $file) { require_once dirname(__DIR__) . "/app/$file.php"; }
require_once dirname(__DIR__) . '/app/features/planning/projection.php';

$level = $argv[1] ?? 'standing';
$weeks = max(1, min(26, (int) ($argv[2] ?? PLANNING_DEFAULT_WEEKS)));
if (!isset(PLANNING_LEVELS[$level])) {
    fwrite(STDERR, "Level must be one of: " . implode(', ', array_keys(PLANNING_LEVELS)) . "\n");
    exit(2);
}
date_default_timezone_set((string) config('app.timezone', 'UTC'));
try {
    $p = planning_projection(db(), $level, $weeks);
} catch (Throwable $exception) {
    fwrite(STDERR, $exception->getMessage() . "\n");
    exit(1);
}
$weekly = static fn(array $values) => array_combine($p['weeks'], array_map(static fn($v) => round((float) $v, 3), $values));
$out = [
    'level' => $level, 'level_label' => PLANNING_LEVELS[$level], 'weeks' => $p['weeks'],
    'demand_units_by_type' => array_map($weekly, $p['demand_by_type']),
    'demand_value_by_type' => array_map($weekly, $p['value_by_type']),
    'packaging' => array_values(array_map(static fn($c, $x) => ['format' => $p['configs'][$c]['name'], 'product' => $p['configs'][$c]['product_name'],
        'released_on_hand_units' => $x['on_hand'], 'demand_units' => $weekly($x['demand']), 'to_package_units' => $weekly($x['to_package'])], array_keys($p['packaging']), $p['packaging'])),
    'bulk' => array_values(array_map(static fn($id, $x) => ['product' => $p['products'][$id] ?? (string) $id, 'need_l' => $weekly($x['need']), 'supply_l' => $weekly($x['supply']),
        'short_l' => $weekly($x['short'])], array_keys($p['bulk']), $p['bulk'])),
    'bulk_supply' => array_map(static fn($b) => ['source' => $b['ref'], 'kind' => $b['kind'], 'product' => $p['products'][$b['product_id']] ?? null,
        'volume_l' => round($b['volume_l'], 1), 'ready_on' => $b['ready_on']], $p['bulk_supply_rows']),
    'production' => array_map(static fn($x) => ['product' => $p['products'][$x['product_id']] ?? null, 'batches' => $x['batches'], 'volume_l' => round($x['volume_l'], 1),
        'short_l' => round($x['shortfall_l'], 1), 'needed_by' => $x['needed_by'], 'pitch_by' => $x['pitch_by'], 'late' => $x['late'], 'days_pitch_to_ready' => $x['lead_days'],
        'stages_without_duration' => $x['missing_durations'], 'driven_by' => $x['driver']], $p['production']),
    'purchasing' => array_values(array_map(static fn($x) => ['item_code' => $x['item']['code'], 'item' => $x['item']['name'], 'base_unit' => $x['item']['base_unit_code'],
        'short_first' => round($x['short_first'], 3), 'needed_by' => $x['needed_by'], 'short_total' => round($x['short_total'], 3), 'order_by' => $x['order_by'], 'late' => $x['late'],
        'supplier' => $x['supplier']['supplier_name'] ?? null, 'lead_time_days' => $x['supplier']['lead_time_days'] ?? null,
        'suggested_order' => $x['purchase_qty'] === null ? null : ['qty' => $x['purchase_qty'], 'unit' => $x['supplier']['purchase_unit_code'],
            'approx_cost' => $x['supplier']['last_price'] === null ? null : round($x['purchase_qty'] * (float) $x['supplier']['last_price'], 2)],
        'needed_for' => $x['sources'], 'fruit_equivalent_kg' => $x['fruit_kg'] === null ? null : round($x['fruit_kg']), 'driven_by' => $x['driver']], $p['purchasing'])),
    'notes' => $p['warnings'],
];
echo json_encode($out, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES), "\n";
