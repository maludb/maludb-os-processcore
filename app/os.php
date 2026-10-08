<?php
declare(strict_types=1);

/**
 * The MaluDB Business OS kernel (os-adoption, 2026-10-04; maludb-os-integration `os-adopt`, `php-sign-on-kit.md`).
 *
 * Behind ONE flag, OS_ENABLED (config/.env, written by the kernel's installer): off, ProcessCore runs standalone exactly as
 * before; on, the kernel's hand-off token is the only way in, people are managed in the kernel's directory, the
 * kernel's agents reach the handlers with the tenant's signed tokens, and the command bar runs ProcessCore's expert in the
 * kernel. Nothing here is reached while the flag is off except the verifiers, which are harmless.
 *
 * Verifiers, the session list, the user link, the directory mirror, the kernel calls. Loaded by app/bootstrap.php
 * after app/auth.php (base64url_decode() and action_token_key() live there and are shared).
 */

function os_enabled(): bool
{
    return in_array(strtolower((string) config('os.enabled', '')), ['1', 'true', 'on', 'yes'], true);
}

function os_app_key(): string
{
    return (string) config('os.app_key', 'processcore');
}

function os_launcher_url(): string
{
    return (string) config('os.launcher_url', '');
}

/** Out to the launcher: HX-Redirect for HTMX, Location otherwise; JSON callers get 401. */
function os_to_launcher(): never
{
    $_SESSION = [];
    $url = os_launcher_url();
    $url .= (str_contains($url, '?') ? '&' : '?') . 'app=' . rawurlencode(os_app_key());
    if (function_exists('json_mode_active') && json_mode_active()) {
        http_response_code(401);
        header('Content-Type: application/json');
        echo json_encode(['error' => ['code' => 'unauthorized', 'message' => 'Sign in from the launcher.']]);
        exit;
    }
    header('Cache-Control: no-store');
    if (is_htmx_request()) {
        http_response_code(401);
        header('HX-Redirect: ' . $url);
    } else {
        header('Location: ' . $url, true, 302);
    }
    exit;
}

// ---- the kernel's tokens (php-sign-on-kit.md §1; roles-and-rights.md §2; agents.md §1) --------------------------

/** [member_id, nonce] for a valid hand-off token bound to THIS application, else null. */
function verify_sso_token(string $token, string $expectedAppKey): ?array
{
    $parts = explode('.', $token);
    if (count($parts) !== 5) {
        return null;
    }
    [$mid, $exp, $app, $nonce, $mac] = $parts;
    if (!ctype_digit($mid) || !ctype_digit($exp) || (int) $exp < time() || $app !== $expectedAppKey || !preg_match('/^[a-f0-9]{32}$/', $nonce)) {
        return null;
    }
    $expected = hash_hmac('sha256', 'sso:' . $mid . '.' . $exp . '.' . $app . '.' . $nonce, action_token_key());
    return hash_equals($expected, $mac) ? [(int) $mid, $nonce] : null;
}

/** The signed claims beside the token: base64url(json) . '.' . hmac(base64url text). */
function verify_sso_claims(string $signed): ?array
{
    $dot = strrpos($signed, '.');
    if ($dot === false) {
        return null;
    }
    $text = substr($signed, 0, $dot);
    $mac = substr($signed, $dot + 1);
    if (!hash_equals(hash_hmac('sha256', $text, action_token_key()), $mac)) {
        return null;
    }
    $json = base64url_decode($text);
    $claims = $json === false ? null : json_decode($json, true);
    return is_array($claims) ? $claims : null;
}

/** The kernel's sign-out notice: {member}.{issued}.{app}.{hmac}, 120 s. Member id or null. */
function verify_sso_logout_notice(string $notice, string $expectedAppKey, int $ttlSeconds = 120): ?int
{
    $parts = explode('.', $notice);
    if (count($parts) !== 4) {
        return null;
    }
    [$mid, $issued, $app, $mac] = $parts;
    if (!ctype_digit($mid) || !ctype_digit($issued) || $app !== $expectedAppKey || abs(time() - (int) $issued) > $ttlSeconds) {
        return null;
    }
    $expected = hash_hmac('sha256', 'sso-logout:' . $mid . '.' . $issued . '.' . $app, action_token_key());
    return hash_equals($expected, $mac) ? (int) $mid : null;
}

/** The kernel itself: kernel.{exp}.{app}.{nonce}.{hmac} over "kernel:exp.app.nonce", 60 s. */
function os_verify_kernel_token(string $token): bool
{
    $parts = explode('.', $token);
    if (count($parts) !== 5 || $parts[0] !== 'kernel') {
        return false;
    }
    [, $exp, $app, $nonce, $mac] = $parts;
    if (!ctype_digit($exp) || (int) $exp < time() || $app !== os_app_key() || strlen($nonce) !== 32) {
        return false;
    }
    return hash_equals(hash_hmac('sha256', 'kernel:' . $exp . '.' . $app . '.' . $nonce, action_token_key()), $mac);
}

/**
 * [member_id, run_id|null] from a tenant token's signature alone: '{mid}.{exp}.{hmac}' (a person's action
 * token, over "mid.exp") or '{mid}.{exp}.{run}.{hmac}' (an agent RUN token, over "run:mid.exp.run").
 */
function os_verify_token_signature(string $token): ?array
{
    $parts = explode('.', $token);
    if (count($parts) === 4) {
        [$mid, $exp, $run, $sig] = $parts;
        if (!ctype_digit($mid) || !ctype_digit($exp) || !ctype_digit($run) || time() > (int) $exp) {
            return null;
        }
        return hash_equals(hash_hmac('sha256', 'run:' . $mid . '.' . $exp . '.' . $run, action_token_key()), $sig) ? [(int) $mid, (int) $run] : null;
    }
    if (count($parts) !== 3) {
        return null;
    }
    [$mid, $exp, $sig] = $parts;
    if (!ctype_digit($mid) || !ctype_digit($exp) || time() > (int) $exp) {
        return null;
    }
    return hash_equals(hash_hmac('sha256', $mid . '.' . $exp, action_token_key()), $sig) ? [(int) $mid, null] : null;
}

/**
 * The member a tenant token speaks for at a PHP handler, or null. A run token (four parts) is honoured only
 * with the relay signature the kernel's actions server adds (X-Action-Relay) — the agent never holds the relay
 * key — or under an approval replay, whose own signature the kernel verified before re-posting.
 */
function os_verify_relayed_token(string $token, string $relay, bool $isReplay): ?array
{
    $signed = os_verify_token_signature($token);
    if ($signed === null) {
        return null;
    }
    if ($signed[1] !== null && !$isReplay) {
        $relayKey = (string) config('os.actions_relay_key', '');
        if (strlen($relayKey) < 32 || $relay === '' || !hash_equals(hash_hmac('sha256', $token, $relayKey), $relay)) {
            return null;
        }
    }
    return $signed;
}

// ---- the session list (php-sign-on-kit.md §3) ---------------------------------------------------------------------

function os_session_hash(string $sessionId): string
{
    return hash('sha256', $sessionId);
}

function os_session_open(PDO $pdo, int $memberId, string $sessionId): void
{
    $pdo->prepare('INSERT INTO app.member_sessions (session_hash, member_id) VALUES (:h, :m)
                   ON CONFLICT (session_hash) DO UPDATE SET member_id = EXCLUDED.member_id, ended_at = NULL, ended_by = NULL, last_seen_at = now()')
        ->execute(['h' => os_session_hash($sessionId), 'm' => $memberId]);
}

function os_session_is_listed(PDO $pdo, string $sessionId): bool
{
    $st = $pdo->prepare('SELECT 1 FROM app.member_sessions WHERE session_hash = :h AND ended_at IS NULL');
    $st->execute(['h' => os_session_hash($sessionId)]);
    return $st->fetchColumn() !== false;
}

function os_end_session(PDO $pdo, string $sessionId, string $by): void
{
    $pdo->prepare('UPDATE app.member_sessions SET ended_at = now(), ended_by = :by WHERE session_hash = :h AND ended_at IS NULL')
        ->execute(['by' => $by, 'h' => os_session_hash($sessionId)]);
}

function os_end_member_sessions(PDO $pdo, int $memberId, string $by): int
{
    $st = $pdo->prepare('UPDATE app.member_sessions SET ended_at = now(), ended_by = :by WHERE member_id = :m AND ended_at IS NULL');
    $st->execute(['by' => $by, 'm' => $memberId]);
    return $st->rowCount();
}

// ---- people: the link between app.users and the kernel's members (os-adopt adapter.md §3, §6) --------------------

/** ProcessCore's roles in precedence order for the one `users.role` column (owner first). */
const OS_ROLE_PRECEDENCE = ['owner', 'production', 'receiving', 'quality', 'compliance', 'sales', 'viewer'];

/** [role, os_roles] from what the kernel said: its roles (filtered to ours), the capability, the business role. */
function os_roles_from_kernel(array $roles, ?string $capability, string $businessRole, ?string $currentRole): array
{
    $known = array_values(array_intersect(array_unique(array_map('strval', $roles)), OS_ROLE_PRECEDENCE));
    if ($businessRole === 'super_admin' && !in_array('owner', $known, true)) {
        $known[] = 'owner';                                  // the kernel's super-admin runs every application
    }
    if ($known === [] && $capability === 'admin') {
        $known[] = 'owner';
    }
    if ($known === [] && $capability !== null) {
        $known[] = $currentRole !== null && $currentRole !== 'owner' && in_array($currentRole, OS_ROLE_PRECEDENCE, true) ? $currentRole : 'viewer';
    }
    $role = 'viewer';
    foreach (OS_ROLE_PRECEDENCE as $candidate) {
        if (in_array($candidate, $known, true)) {
            $role = $candidate;
            break;
        }
    }
    return [$role, $known];
}

function os_user_for_member(PDO $pdo, int $memberId): ?array
{
    $st = $pdo->prepare('SELECT * FROM app.users WHERE os_member_id = :m');
    $st->execute(['m' => $memberId]);
    return $st->fetch() ?: null;
}

/**
 * The user a hand-off's claims name: found by os_member_id; else an unlinked user with the same email, linked once;
 * else created with no password (the kernel is the only way in). Name, email, status, role and roles follow the
 * claims. Returns the user row. Inside the caller's transaction.
 */
function os_link_user(PDO $pdo, int $memberId, array $claims): array
{
    $email = normalize_email((string) ($claims['email'] ?? ''));
    $name = trim((string) ($claims['display_name'] ?? '')) ?: ('Member #' . $memberId);
    $user = os_user_for_member($pdo, $memberId);
    if ($user === null && $email !== '') {
        $candidate = find_user_by_email($pdo, $email);
        if ($candidate !== null) {
            if ($candidate['os_member_id'] !== null && (int) $candidate['os_member_id'] !== $memberId) {
                throw new RuntimeException('email-in-use');   // never relink an account to a second member
            }
            $user = $candidate;
            log_activity($pdo, 'user_linked_to_os', 'user', (int) $user['id'], $user['display_name'], null, ['os_member_id' => $memberId], ['by' => 'email'], 'sso', 'web');
        }
    }
    if ($user === null) {
        $user = insert_user($pdo, $email !== '' ? $email : ('member-' . $memberId . '@os.invalid'), $name, 'viewer', 'active', null, true);
        log_activity($pdo, 'user_created_by_os', 'user', (int) $user['id'], $name, null, ['os_member_id' => $memberId], [], 'sso', 'web');
    }
    $capability = in_array($claims['capability'] ?? null, ['read', 'write', 'admin'], true) ? (string) $claims['capability'] : null;
    [$role, $osRoles] = os_roles_from_kernel(is_array($claims['roles'] ?? null) ? $claims['roles'] : [], $capability,
        (string) ($claims['business_role'] ?? 'user'), (string) $user['role']);
    $pdo->prepare('UPDATE app.users SET os_member_id = :m, display_name = :n, email = COALESCE(NULLIF(:e, \'\'), email), status = \'active\',
                          role = :r, os_roles = CAST(:rs AS text[]), os_capability = :c, os_synced_at = now(), email_verified_at = COALESCE(email_verified_at, now())
                    WHERE id = :id')
        ->execute(['m' => $memberId, 'n' => $name, 'e' => $email, 'r' => $role, 'rs' => '{' . implode(',', $osRoles) . '}', 'c' => $capability, 'id' => (int) $user['id']]);
    return find_user($pdo, (int) $user['id']);
}

/** A members[] row of the change feed: a linked user follows the kernel's name, email and status. */
function os_apply_member_row(PDO $pdo, array $m): bool
{
    $memberId = (int) ($m['id'] ?? 0);
    $user = $memberId > 0 ? os_user_for_member($pdo, $memberId) : null;
    if ($user === null) {
        return false;                                        // never auto-create: the first hand-off makes the link
    }
    $active = (string) ($m['status'] ?? 'active') === 'active';
    $pdo->prepare('UPDATE app.users SET display_name = COALESCE(NULLIF(:n, \'\'), display_name), email = COALESCE(NULLIF(:e, \'\'), email),
                          status = :s, os_synced_at = now() WHERE id = :id')
        ->execute(['n' => trim((string) ($m['display_name'] ?? '')), 'e' => normalize_email((string) ($m['email'] ?? '')),
                   's' => $active ? 'active' : 'disabled', 'id' => (int) $user['id']]);
    if (!$active) {
        os_end_member_sessions($pdo, $memberId, 'directory');
    }
    return true;
}

/** An access[] row: the member's whole holding on ProcessCore replaces capability and roles; nothing held → every session ends. */
function os_apply_access_row(PDO $pdo, array $a): bool
{
    $memberId = (int) ($a['member_id'] ?? 0);
    $user = $memberId > 0 ? os_user_for_member($pdo, $memberId) : null;
    if ($user === null) {
        return false;
    }
    $capability = in_array($a['capability'] ?? null, ['read', 'write', 'admin'], true) ? (string) $a['capability'] : null;
    [$role, $osRoles] = $capability === null ? [(string) $user['role'], []]
        : os_roles_from_kernel(is_array($a['roles'] ?? null) ? $a['roles'] : [], $capability, (string) ($a['business_role'] ?? 'user'), (string) $user['role']);
    $pdo->prepare('UPDATE app.users SET role = :r, os_roles = CAST(:rs AS text[]), os_capability = :c, os_synced_at = now() WHERE id = :id')
        ->execute(['r' => $role, 'rs' => '{' . implode(',', $osRoles) . '}', 'c' => $capability, 'id' => (int) $user['id']]);
    if ($capability === null) {
        os_end_member_sessions($pdo, $memberId, 'directory');
    }
    return true;
}

/** Still admitted: active, linked, holding a capability. One indexed read; the guard runs it on every request. */
function os_user_admitted(?array $user): bool
{
    return $user !== null && $user['status'] === 'active' && ($user['os_member_id'] ?? null) !== null && ($user['os_capability'] ?? null) !== null;
}

// ---- calls to the kernel (sign-on-and-directory.md §4–5, agents.md A7 b) -------------------------------------------

/**
 * One call to the kernel's internal API with the application token. ['status' => int, 'body' => array|null,
 * 'request_id' => ?string], or null when unreachable or unconfigured.
 */
function kernel_call(string $method, string $path, ?array $body = null, array $headers = [], int $timeout = 15): ?array
{
    $base = rtrim((string) config('os.internal_url', 'http://127.0.0.1:8080'), '/');
    $token = (string) config('os.application_token', '');
    if ($token === '') {
        error_log('kernel_call: OS_APPLICATION_TOKEN is not configured');
        return null;
    }
    $ch = curl_init($base . $path);
    $hdrs = array_merge(['Authorization: Bearer ' . $token, 'Accept: application/json', 'X-Request-Id: ' . request_id()], $headers);
    $opts = [CURLOPT_RETURNTRANSFER => true, CURLOPT_CONNECTTIMEOUT => 3, CURLOPT_TIMEOUT => $timeout, CURLOPT_CUSTOMREQUEST => $method, CURLOPT_HEADER => true];
    if ($body !== null) {
        $hdrs[] = 'Content-Type: application/json';
        $opts[CURLOPT_POSTFIELDS] = json_encode($body, JSON_THROW_ON_ERROR);
    }
    $opts[CURLOPT_HTTPHEADER] = $hdrs;
    curl_setopt_array($ch, $opts);
    $raw = curl_exec($ch);
    $status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    $headerSize = (int) curl_getinfo($ch, CURLINFO_HEADER_SIZE);
    curl_close($ch);
    if ($raw === false || $status === 0) {
        return null;
    }
    $head = substr((string) $raw, 0, $headerSize);
    $decoded = json_decode(substr((string) $raw, $headerSize), true);
    $rid = preg_match('/^X-Request-Id:\s*(.+)$/mi', $head, $m) ? trim($m[1]) : null;
    return ['status' => $status, 'body' => is_array($decoded) ? $decoded : null, 'request_id' => $rid];
}

/** A directory read with the application token (the mirror's refresh). Null when unreachable. */
function directory_read(string $path): ?array
{
    $answer = kernel_call('GET', '/api/v1/directory/' . ltrim($path, '/'));
    return $answer !== null && $answer['status'] === 200 ? $answer['body'] : null;
}

/**
 * The kernel's word on a token a caller presented: {valid, is_agent, member_id, member_name, run_id, request_id,
 * trigger, is_eval, run_status, endpoints[], capability, role, roles, rights}. Null when the kernel cannot be
 * reached — callers fail closed on null exactly as on valid:false. Cached per request.
 */
function run_facts(string $token): ?array
{
    static $cache = [];
    if ($token === '') {
        return null;
    }
    if (!array_key_exists($token, $cache)) {
        $answer = kernel_call('POST', '/api/v1/runs/facts.php', ['token' => $token]);
        $cache[$token] = ($answer !== null && $answer['status'] === 200 && is_array($answer['body'])) ? $answer['body'] : null;
    }
    return $cache[$token];
}

// ---- the local account screens under the flag (adapter.md §5) ---------------------------------------------------

/** The sentence every people screen shows while the kernel manages people; a link to the launcher. */
function os_managed_notice(): string
{
    $url = os_launcher_url();
    return '<div class="alert alert-info d-flex align-items-center gap-2 mb-3" id="os-managed-notice"><i class="feather-shield"></i>'
        . '<div>Managed in the operating system. People, their roles and their access are granted in the Business OS'
        . ($url !== '' ? ' — <a href="' . e($url) . '">open it</a>.' : '.') . '</div></div>';
}

/** A save handler of a people screen: 403 with the same sentence while the kernel manages people. */
function os_refuse_if_managed(): void
{
    if (!os_enabled()) {
        return;
    }
    http_response_code(403);
    if (function_exists('json_mode_active') && json_mode_active()) {
        header('Content-Type: application/json');
        echo json_encode(['error' => ['code' => 'managed_by_os', 'message' => 'People are managed in the operating system.']]);
    } else {
        echo view('shared/error.php', ['message' => 'People are managed in the operating system. Grant or change access in the Business OS.']);
    }
    exit;
}

/** The password form, Google, invitations, reset: all closed while the kernel signs people in. */
function os_close_local_signin(): void
{
    if (os_enabled()) {
        os_to_launcher();
    }
}
