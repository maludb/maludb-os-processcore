<?php
declare(strict_types=1);
/**
 * The mirror's timer (sign-on-and-directory.md §4; os-adopt adapter.md §6): every minute, GET the kernel's change feed
 * since the stored cursor and apply it to app.users — members[] (name, email, status of LINKED users) and access[]
 * (each affected member's capability and roles on ProcessCore; nothing held → no access and every session ended).
 * Departments and memberships are not mirrored: ProcessCore has no departments. --full refreshes from the start.
 *   php bin/directory_sync.php [--full]
 *   php bin/directory_sync.php --from-file bin/dev_directory.json      a fixture in the kernel's format (testing-without-a-kernel.md)
 */
if (PHP_SAPI !== 'cli') { fwrite(STDERR, "CLI only.\n"); exit(1); }
require_once dirname(__DIR__) . '/app/bootstrap.php';
if (!os_enabled()) { echo "OS_ENABLED is off — nothing to sync.\n"; exit(0); }

$opts = getopt('', ['full', 'from-file:']);
$full = isset($opts['full']);
$pdo = db();
if (!(bool) $pdo->query("SELECT pg_try_advisory_lock(hashtext('processcore_directory_sync'))")->fetchColumn()) {
    echo "another sync holds the lock — skipping.\n";
    exit(0);
}
$state = $pdo->query('SELECT next_cursor FROM app.directory_sync_state WHERE id = 1')->fetch();
$cursor = $full ? null : ($state['next_cursor'] ?? null);

if (isset($opts['from-file'])) {
    $fixture = json_decode((string) file_get_contents((string) $opts['from-file']), true);
    if (!is_array($fixture) || !is_array($fixture['feed'] ?? null)) { fwrite(STDERR, "the fixture has no feed\n"); exit(1); }
    $feed = $fixture['feed'];
} else {
    $feed = directory_read('changes.php' . ($cursor !== null ? '?since=' . rawurlencode((string) $cursor) : ''));
    if ($feed === null || ($feed['schema'] ?? '') !== 'os.directory-changes/1') {
        $pdo->prepare('UPDATE app.directory_sync_state SET last_run_at = now(), last_error = :e, updated_at = now() WHERE id = 1')
            ->execute(['e' => 'the kernel did not answer the change feed']);
        log_activity($pdo, 'directory_sync_failed', null, null, null, null, null, ['cursor' => $cursor], null, 'cron', null, 'system/directory-sync');
        fwrite(STDERR, "the kernel did not answer the change feed\n");
        exit(1);
    }
}

$pdo->beginTransaction();
try {
    $counts = ['members' => 0, 'access' => 0];
    foreach ((array) ($feed['members'] ?? []) as $m) { $counts['members'] += os_apply_member_row($pdo, (array) $m) ? 1 : 0; }
    foreach ((array) ($feed['access'] ?? []) as $a) { $counts['access'] += os_apply_access_row($pdo, (array) $a) ? 1 : 0; }
    $wasFull = !empty($feed['full']);
    $pdo->prepare('UPDATE app.directory_sync_state SET next_cursor = COALESCE(:n, next_cursor), full_at = CASE WHEN :full THEN now() ELSE full_at END,
                          last_run_at = now(), last_error = NULL, updated_at = now() WHERE id = 1')
        ->execute(['n' => $feed['next'] ?? null, 'full' => $wasFull ? 't' : 'f']);
    $pdo->commit();
} catch (Throwable $e) {
    $pdo->rollBack();
    error_log('directory_sync: ' . $e->getMessage());
    $pdo->prepare('UPDATE app.directory_sync_state SET last_run_at = now(), last_error = :e, updated_at = now() WHERE id = 1')->execute(['e' => 'apply failed']);
    exit(1);
}
if (array_sum($counts) > 0 || $wasFull) {
    log_activity($pdo, 'directory_synced', null, null, null, null, null, $counts + ['full' => $wasFull], null, 'cron', null, 'system/directory-sync');
}
printf("applied %d members, %d holdings%s; cursor %s\n", $counts['members'], $counts['access'], $wasFull ? ' (full)' : '', $feed['next'] ?? '(unchanged)');
