<?php
declare(strict_types=1);
/**
 * Activity memory, every minute (memory.md §2). Two destinations, one timer:
 *   1. the in-database MaluDB memory schema the activity MCP server reads (app.activity_ingest_pending(), as before);
 *   2. beside the Business OS kernel, the tenant's ONE MaluDB through its API — one `activity` episode per row,
 *      payload first key "application": "processcore", checkpoint app.activity_ingest_state.last_id, advisory-locked,
 *      stop at the first rejected row, a clean no-op when MALUDB_API_URL / MALUDB_API_TOKEN are not configured.
 * Replaces deploy/activity-ingest.sh (which looped over the standalone product's processcore_host registry).
 */
if (PHP_SAPI !== 'cli') { fwrite(STDERR, "CLI only.\n"); exit(1); }
require_once dirname(__DIR__) . '/app/bootstrap.php';
$pdo = db();
if (!(bool) $pdo->query("SELECT pg_try_advisory_lock(hashtext('processcore_activity_ingest'))")->fetchColumn()) {
    exit(0);
}
// 1. the in-database memory schema
$local = 0;
do {
    $n = (int) $pdo->query('SELECT app.activity_ingest_pending(500)')->fetchColumn();
    $local += $n;
} while ($n >= 500);

// 2. the tenant's MaluDB (the kernel's memory)
$url = rtrim((string) config('os.maludb_api_url', ''), '/');
$token = (string) config('os.maludb_api_token', '');
$shipped = 0;
if ($url !== '' && $token !== '') {
    $last = (int) $pdo->query('SELECT last_id FROM app.activity_ingest_state WHERE id = 1')->fetchColumn();
    $st = $pdo->prepare('SELECT a.*, u.display_name AS actor_name FROM app.activity_log a LEFT JOIN app.users u ON u.id = a.actor_id WHERE a.id > :last ORDER BY a.id LIMIT 500');
    $st->execute(['last' => $last]);
    foreach ($st->fetchAll() as $row) {
        $payload = array_filter([
            'application' => os_app_key(), 'activity_log_id' => (int) $row['id'], 'actor_id' => $row['actor_id'] !== null ? (int) $row['actor_id'] : null,
            'actor_label' => $row['actor_label'], 'source' => $row['source'], 'action' => $row['action'], 'screen' => $row['screen'],
            'entity_type' => $row['entity_type'], 'entity_id' => $row['entity_id'] !== null ? (int) $row['entity_id'] : null, 'entity_label' => $row['entity_label'],
            'before' => $row['before'] !== null ? json_decode((string) $row['before'], true) : null, 'after' => $row['after'] !== null ? json_decode((string) $row['after'], true) : null,
            'details' => json_decode((string) $row['details'], true), 'request_id' => $row['request_id'], 'agent_run_id' => $row['agent_run_id'] !== null ? (int) $row['agent_run_id'] : null,
        ], static fn ($v) => $v !== null && $v !== '' && $v !== []);
        $episode = ['kind' => 'activity', 'title' => $row['action'] . ' by ' . ($row['actor_name'] ?? ($row['actor_id'] !== null ? 'user #' . $row['actor_id'] : 'system')),
                    'summary' => null, 'occurred_at' => (new DateTimeImmutable((string) $row['occurred_at']))->format(DATE_ATOM),
                    'sensitivity' => 'internal', 'provenance' => 'provided', 'payload' => $payload];
        $ch = curl_init($url . '/v1/episodes');
        curl_setopt_array($ch, [CURLOPT_POST => true, CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 30, CURLOPT_CONNECTTIMEOUT => 5,
            CURLOPT_HTTPHEADER => ['Content-Type: application/json', 'Authorization: Bearer ' . $token], CURLOPT_POSTFIELDS => json_encode($episode, JSON_THROW_ON_ERROR)]);
        curl_exec($ch);
        $code = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        curl_close($ch);
        if ($code !== 200 && $code !== 201) {
            fwrite(STDERR, "MaluDB answered {$code} for activity row {$row['id']} — stopping; the checkpoint stays at {$last}\n");
            break;
        }
        $last = (int) $row['id'];
        $shipped++;
        $pdo->prepare('UPDATE app.activity_ingest_state SET last_id = GREATEST(last_id, :id), updated_at = now() WHERE id = 1')->execute(['id' => $last]);
    }
}
if ($local > 0 || $shipped > 0) {
    echo "ingested {$local} rows locally, shipped {$shipped} to the tenant's MaluDB\n";
}
