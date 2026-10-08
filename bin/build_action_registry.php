<?php
declare(strict_types=1);
/**
 * The action registry for the Business OS kernel's actions server (mcp-and-api.md §3; os-adoption 2026-10-04).
 *
 * ProcessCore's source of truth is docs/05-action-manifest.md, already parsed into config/manifest.json by
 * services/actions_mcp/build_manifest.py (its own actions server reads that). The kernel's actions server reads a
 * different shape — mcp/action_registry.json: one entry per action with a flat endpoint, typed params, built,
 * log_event, who, confirm, approval, undo — so this script derives it. Path parameters ({id}) become named entity
 * parameters ("/vessels/{vessel}/status") that the kernel resolves through the records MCP server's find_* tools
 * (deploy/kernel-registry-processcore.json names them) and substitutes into the path.
 *
 *   php bin/build_action_registry.php            writes mcp/action_registry.json
 *   php bin/build_action_registry.php --check    exits 1 when the file is stale
 */
if (PHP_SAPI !== 'cli') { exit(1); }
$root = dirname(__DIR__);
$manifest = json_decode((string) file_get_contents($root . '/config/manifest.json'), true);
if (!is_array($manifest)) { fwrite(STDERR, "config/manifest.json is missing — run services/actions_mcp/build_manifest.py first\n"); exit(1); }

/** html/{feature}/… → the records MCP resolver kind (services/records_mcp/resolve.py KINDS) for its {id}. */
const FEATURE_KIND = [
    'vessels' => 'vessel', 'items' => 'item', 'suppliers' => 'supplier', 'lots' => 'lot', 'batches' => 'batch', 'purchase-orders' => 'po',
    'receipts' => 'receipt', 'production-orders' => 'order', 'kegs' => 'keg', 'orders' => 'sales_order', 'packaging-runs' => 'packaging_run',
    'customers' => 'customer', 'locations' => 'location', 'premises' => 'premises', 'products' => 'product', 'ttb-reports' => 'report',
    'reason-codes' => 'reason', 'tanks' => 'vessel', 'equipment' => 'equipment', 'reservations' => 'reservation', 'press-runs' => 'press_run',
];
/** Features the kernel manages itself while OS_ENABLED is on: no action tool is made for them. */
const MANAGED_BY_KERNEL = ['users'];
/** Two-word entities, so the log event splits at the right place (receipt_line.weigh_tag, not receipt.line_weigh_tag). */
const TWO_WORD = ['item_class', 'purchase_order', 'production_order', 'packaging_run', 'packaging_config', 'press_run', 'standing_order', 'finished_lot',
    'reason_code', 'standard_cost', 'sales_order', 'count_line', 'supplier_item', 'item_unit', 'recipe_version', 'lab_reading', 'ttb_report', 'tank_board', 'customer_order', 'equipment_reservation'];

function singular(string $feature): string
{
    $s = str_replace('-', '_', $feature);
    if (str_ends_with($s, 'ies')) { return substr($s, 0, -3) . 'y'; }
    if (str_ends_with($s, 'ses')) { return substr($s, 0, -2); }
    if (str_ends_with($s, 's') && !str_ends_with($s, 'ss')) { return substr($s, 0, -1); }
    return $s;
}

function log_event_for(string $action): string
{
    foreach (TWO_WORD as $entity) {
        if (str_starts_with($action, $entity . '_')) { return $entity . '.' . substr($action, strlen($entity) + 1); }
    }
    $i = strpos($action, '_');
    return $i === false ? $action : substr($action, 0, $i) . '.' . substr($action, $i + 1);
}

/** "status (empty, cleaning, out_of_service)" / "name, kind, registry_number" / "— (note)" → [[name, hint], …], [notes] */
function parse_params(string $text): array
{
    $text = trim($text);
    if ($text === '' || str_starts_with($text, '—')) {
        $note = trim($text, "— ()");
        return [[], $note !== '' ? [$note] : []];
    }
    $parts = [];
    $depth = 0;
    $cur = '';
    foreach (str_split($text) as $ch) {
        if ($ch === '(') { $depth++; }
        if ($ch === ')') { $depth--; }
        if ($ch === ',' && $depth === 0) { $parts[] = $cur; $cur = ''; continue; }
        $cur .= $ch;
    }
    $parts[] = $cur;
    $out = [];
    foreach ($parts as $p) {
        $p = trim($p);
        if ($p === '') { continue; }
        if (preg_match('/^([a-z][a-z0-9_]*)(?:\[\])?\s*(?:\((.*)\))?$/s', $p, $m)) {
            $out[] = ['name' => $m[1], 'required' => false, 'repeated' => str_contains($p, '[]'), 'hint' => trim($m[2] ?? '')];
        } elseif (preg_match('/^any field of ([a-z_]+)$/', $p, $m)) {
            $out[] = ['name' => null, 'note' => $p];
        } else {
            $out[] = ['name' => null, 'note' => $p];
        }
    }
    return [$out, []];
}

/** The controller the router would run for "POST /feature/{id}/verb" (html/_router.php's rules); null when none. */
function controller_for(string $root, string $path): ?string
{
    $segments = explode('/', trim($path, '/'));
    $feature = array_shift($segments);
    $dir = $root . '/html/' . $feature;
    if (!is_dir($dir)) { return null; }
    $words = [];
    foreach ($segments as $seg) {
        if ($seg === '' || preg_match('/^\{[a-z_]+\}$/', $seg) || ctype_digit($seg)) { continue; }
        $words[] = $seg;
    }
    if ($words === []) { $name = 'save'; }           // a POST to /feature/ or /feature/{id} is the save handler by convention
    else {
        if (end($words) === 'new') { array_pop($words); $words[] = 'form'; }
        if ($words === ['edit']) { $words = ['form']; }
        $name = implode('-', $words);
    }
    foreach ([$name . '-save', $name] as $candidate) {
        if (is_file($dir . '/' . $candidate . '.php')) { return $feature . '/' . $candidate . '.php'; }
    }
    return null;
}

$actions = [];
$resolveParams = [];
foreach ($manifest['actions'] as $a) {
    [$method, $path] = explode(' ', (string) $a['endpoint'], 2);
    // Composite rows: "/kegs/{id}/state (event=clean)" fixes a field; "/orders/save then POST /orders/{id}/confirm" and
    // "/a/commit, /undo, /discard" name several handlers — the first path is the action's, the rest are their own rows.
    $fixed = [];
    if (preg_match('/^(\S+)\s*\(([a-z_]+)=([a-z_]+)(?:\s*\/\s*[a-z_]+)?\)$/', trim($path), $m)) {
        $path = $m[1];
        if (!str_contains((string) $a['endpoint'], ' / ')) { $fixed[$m[2]] = $m[3]; }
    }
    $path = trim(preg_split('/\s*(?:,|\sthen\s)\s*/', $path)[0]);
    $path = preg_replace('/\s*\(.*$/', '', $path);
    $feature = explode('/', trim($path, '/'))[0];
    if (in_array($feature, MANAGED_BY_KERNEL, true)) { continue; }
    [$params, $notes] = parse_params((string) $a['params']);
    // Path parameters: {id} → the feature's entity; others keep their name. All required.
    $pathParams = [];
    $endpoint = preg_replace_callback('/\{([a-z_]+)\}/', static function (array $m) use ($feature, &$pathParams, &$resolveParams): string {
        $kind = FEATURE_KIND[$feature] ?? null;
        $name = $m[1] === 'id' ? ($kind ?? singular($feature)) : $m[1];
        $pathParams[] = ['name' => $name, 'required' => true, 'repeated' => false,
            'hint' => $m[1] === 'id' ? ('the ' . str_replace('_', ' ', singular($feature)) . ($kind !== null ? ' (its number or name, or its id)' : "'s id")) : ('the ' . $m[1] . "'s id")];
        if ($m[1] === 'id' && $kind !== null) { $resolveParams[$kind][$name] = true; }
        return '{' . $name . '}';
    }, $path);
    $name = (string) $a['name'];
    $actions[$name] = [
        'action' => $name, 'section' => (string) $a['section'], 'endpoint' => $endpoint, 'method' => $method,
        'params' => array_merge($pathParams, $params, array_map(static fn (string $n): array => ['name' => null, 'note' => $n], $notes)),
        'undo' => (string) $a['undo'] === 'none' ? null : str_replace('_', ' ', (string) $a['undo']),
        'confirm' => (string) $a['confirm'] === 'yes',
        'approval' => str_ends_with($name, '_delete') ? 'deletion' : (preg_match('/^ttb_report_(file|submit|finalize)/', $name) ? 'other' : null),
        'fixed' => $fixed,
        'log_event' => log_event_for($name),
        'who' => (string) $a['role'],
        'built' => controller_for($root, $path) !== null,
        'controller' => controller_for($root, $path),
    ];
}
$screens = [];
foreach ($manifest['screens'] as $s) {
    $screens[$s['id']] = ['screen' => $s['id'], 'url' => $s['url'], 'section' => $s['section'], 'when' => $s['when'],
        'params' => array_values((array) ($s['prefill'] ?? [])), 'built' => !empty($s['navigable']), 'stub' => false];
}
ksort($actions);
$registry = ['generated_from' => 'config/manifest.json (docs/05-action-manifest.md)', 'generated_at' => (new DateTimeImmutable())->format(DATE_ATOM),
    'screens' => $screens, 'actions' => $actions];
$json = json_encode($registry, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . "\n";
$target = $root . '/mcp/action_registry.json';
$built = count(array_filter($actions, static fn (array $x): bool => $x['built']));
if (in_array('--check', $argv, true)) {
    $current = is_file($target) ? json_decode((string) file_get_contents($target), true) : null;
    $same = is_array($current) && ($current['actions'] ?? null) === $actions && ($current['screens'] ?? null) === $screens;
    echo $same ? "mcp/action_registry.json is current ({$built} of " . count($actions) . " actions built)\n" : "mcp/action_registry.json is STALE — run bin/build_action_registry.php\n";
    exit($same ? 0 : 1);
}
@mkdir($root . '/mcp');
file_put_contents($target, $json);
// The kernel's resolve block: each entity parameter → the records MCP resolver for its kind.
$resolve = [];
foreach ($resolveParams as $kind => $names) {
    $resolve[$kind] = ['tool' => 'find_' . $kind, 'query_param' => 'q', 'id_field' => $kind . '_id', 'label_field' => 'label', 'params' => array_keys($names)];
}
ksort($resolve);
$wrapper = ['schema' => 'maludb-os.registry/1', 'app_key' => 'processcore', 'name' => 'ProcessCore',
    'note' => 'The kernel installer (bin/app_install.php, step registry) writes mcp/registries/processcore.json from this resolve block plus mcp/action_registry.json. Each find_<kind> tool on the records MCP server answers {"rows": [{<kind>_id, label, detail}]} for `q`; the kernel substitutes the id into the endpoint path.',
    'resolve' => $resolve];
@mkdir($root . '/deploy');
file_put_contents($root . '/deploy/kernel-registry-processcore.json', json_encode($wrapper, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . "\n");
printf("mcp/action_registry.json: %d actions (%d built), %d screens; deploy/kernel-registry-processcore.json: %d resolvers\n", count($actions), $built, count($screens), count($resolve));
