<?php
declare(strict_types=1);

function csrf_token(): string
{
    if (empty($_SESSION['csrf_token'])) {
        $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
    }
    return $_SESSION['csrf_token'];
}

function csrf_field(): string
{
    return '<input type="hidden" name="csrf_token" value="' . e(csrf_token()) . '">';
}

/** Guard every unsafe method; accepts the hidden field or the X-CSRF-Token header. */
function verify_csrf(): void
{
    if (!in_array($_SERVER['REQUEST_METHOD'], ['POST', 'PUT', 'PATCH', 'DELETE'], true)) {
        return;
    }
    // CSRF protects cookie sessions. A request authenticated by an action token carries no
    // cookie session; the HMAC token (localhost only, short-lived) is its authorization — ProcessCore's
    // own, or under the Business OS the tenant's relayed token (app/os.php).
    if (empty($_SESSION['user_id']) && function_exists('verify_action_token') && verify_action_token($_SERVER['HTTP_X_ACTION_TOKEN'] ?? null) !== null) {
        return;
    }
    $sent = $_POST['csrf_token'] ?? ($_SERVER['HTTP_X_CSRF_TOKEN'] ?? '');
    $expected = (string) ($_SESSION['csrf_token'] ?? '');
    if ($expected === '' || !hash_equals($expected, (string) $sent)) {
        http_response_code(403);
        exit('CSRF validation failed.');
    }
}

function rotate_csrf_token(): void
{
    unset($_SESSION['csrf_token']);
    csrf_token();
}
