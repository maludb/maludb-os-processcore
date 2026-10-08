<?php
declare(strict_types=1);
/**
 * /sso — the Business OS kernel's hand-off (php-sign-on-kit.md §4, os-adopt adapter.md §3). Checks in order; any
 * failure is ONE page that never says which. Ends in ProcessCore's own login function (complete_login) so every session
 * key the application expects is filled the way it always was; the TOTP challenge is not asked — the kernel
 * authenticated the person.
 */
require_once dirname(__DIR__) . '/app/bootstrap.php';

if (!os_enabled()) {
    not_found();
}
no_store_headers();
$pdo = db();
$token = (string) ($_GET['token'] ?? '');
$claimsRaw = (string) ($_GET['claims'] ?? '');
$refuse = static function (string $reason, ?int $memberId = null) use ($pdo): never {
    try {
        log_activity($pdo, 'os_sign_on_refused', 'user', null, null, null, null, ['reason' => $reason, 'member_id' => $memberId], 'sso', 'web', null, 'os/member:' . ($memberId ?? '?'));
    } catch (Throwable $e) {
        error_log('sso refusal log: ' . $e->getMessage());
    }
    http_response_code(403);
    echo view('auth/layout.php', ['title' => 'Sign-on link expired', 'content' => view('auth/sso-refused.php', ['launcher' => os_launcher_url()])]);
    exit;
};

$verified = $token === '' ? null : verify_sso_token($token, os_app_key());
if ($verified === null) {
    $refuse('token');
}
[$memberId, $nonce] = $verified;
$claims = $claimsRaw === '' ? null : verify_sso_claims($claimsRaw);
if ($claims === null || (int) ($claims['member_id'] ?? 0) !== $memberId) {
    $refuse('claims', $memberId);
}
if (($claims['status'] ?? 'active') !== 'active') {
    $refuse('status', $memberId);
}
if (!in_array($claims['capability'] ?? null, ['read', 'write', 'admin'], true)) {
    $refuse('capability', $memberId);
}
$claimed = $pdo->prepare('INSERT INTO app.sso_nonces (nonce, member_id, expires_at) VALUES (:n, :m, to_timestamp(:e)) ON CONFLICT (nonce) DO NOTHING');
$claimed->execute(['n' => $nonce, 'm' => $memberId, 'e' => (int) explode('.', $token)[1]]);
if ($claimed->rowCount() !== 1) {
    $refuse('replay', $memberId);
}
$pdo->exec("DELETE FROM app.sso_nonces WHERE expires_at < now() - interval '1 hour'");

$pdo->beginTransaction();
try {
    $user = os_link_user($pdo, $memberId, $claims);
    $pdo->commit();
} catch (Throwable $e) {
    $pdo->rollBack();
    error_log('sso link: ' . $e->getMessage());
    $refuse($e->getMessage() === 'email-in-use' ? 'email-in-use' : 'link', $memberId);
}

complete_login($user, 'os');                        // ProcessCore's own login function: session id regenerated, CSRF rotated, the session listed, logged
log_activity($pdo, 'os_sign_on', 'user', (int) $user['id'], $user['display_name'], null, ['capability' => $claims['capability'], 'roles' => user_os_roles($user)], [], 'sso', 'web', (int) $user['id'], 'user/' . $user['id'] . ' ' . $user['display_name']);
header('Location: /', true, 302);
exit;
