<?php
declare(strict_types=1);

// Default configuration. Overridden, in this order, by config/local.php (a PHP array, gitignored —
// the standalone product's file) and then by config/.env (KEY=VALUE, gitignored — what the Business
// OS kernel's installer writes; os-adoption 2026-10-04). Read with config('db.name'). A single
// OS/env key is read with env('OS_ENABLED').
$defaults = [
    'app' => [
        'name'        => 'ProcessCore',
        'base_url'    => 'http://127.0.0.1',
        'environment' => 'production',
        'timezone'    => 'America/New_York',
    ],
    'db' => [
        'host' => '127.0.0.1', 'port' => '5432', 'name' => 'processcore_dev', 'user' => 'processcore_app', 'password' => '',
    ],
    'security' => [
        'totp_key'            => '',   // 64 hex chars, libsodium secretbox key for TOTP seeds
        'action_token_key'    => '',   // HMAC key for action tokens (standalone: the app's own; under the OS: the tenant's ACTION_TOKEN_KEY)
        'dummy_password_hash' => '',   // bcrypt cost 12, timing equalizer for unknown emails
        'password_min_length' => 12,
        'lockout_attempts_per_email' => 5,
        'lockout_attempts_per_ip'    => 20,
        'lockout_window_minutes'     => 15,
        'pending_2fa_minutes'        => 10,
        'reset_token_minutes'        => 60,
        'invite_token_days'          => 7,
    ],
    'google' => ['client_id' => '', 'client_secret' => ''],
    'malumail' => ['api_key' => '', 'from' => 'noreply@example.com', 'from_name' => 'ProcessCore'],
    'assistant' => ['service_url' => 'http://127.0.0.1:8765'],
    // The Business OS kernel (maludb-os-integration): empty = standalone.
    'os' => [
        'enabled' => '', 'app_key' => 'processcore', 'internal_url' => 'http://127.0.0.1:8080', 'launcher_url' => '',
        'application_token' => '', 'actions_relay_key' => '', 'maludb_api_url' => '', 'maludb_api_token' => '',
    ],
];

$localFile = __DIR__ . '/local.php';
$local = is_file($localFile) ? (array) require $localFile : [];

/** config/.env (KEY=VALUE, quotes optional, # comments) plus the real environment, which wins. */
function env_file_values(): array
{
    static $values = null;
    if ($values !== null) {
        return $values;
    }
    $values = [];
    $path = __DIR__ . '/.env';
    if (is_readable($path)) {
        foreach (file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
            $line = trim($line);
            if ($line === '' || $line[0] === '#' || !str_contains($line, '=')) {
                continue;
            }
            [$k, $v] = explode('=', $line, 2);
            $k = trim($k);
            $v = trim($v);
            if (strlen($v) >= 2 && ($v[0] === '"' || $v[0] === "'") && $v[-1] === $v[0]) {
                $v = substr($v, 1, -1);
            }
            if (preg_match('/^[A-Z][A-Z0-9_]*$/', $k)) {
                $values[$k] = $v;
            }
        }
    }
    return $values;
}

/** One environment key: the process environment, then config/.env, then $default. */
function env(string $key, mixed $default = null): mixed
{
    $fromProcess = getenv($key);
    if ($fromProcess !== false && $fromProcess !== '') {
        return $fromProcess;
    }
    $file = env_file_values();
    return array_key_exists($key, $file) && $file[$key] !== '' ? $file[$key] : $default;
}

// Every env key that overrides a config value (the installer writes the DB_*, APP_* and OS keys).
$envMap = [
    'APP_NAME' => 'app.name', 'APP_URL' => 'app.base_url', 'APP_ENV' => 'app.environment', 'APP_TIMEZONE' => 'app.timezone',
    'DB_HOST' => 'db.host', 'DB_PORT' => 'db.port', 'DB_NAME' => 'db.name', 'DB_USER' => 'db.user', 'DB_PASSWORD' => 'db.password',
    'ACTION_TOKEN_KEY' => 'security.action_token_key', 'TOTP_KEY' => 'security.totp_key', 'DUMMY_PASSWORD_HASH' => 'security.dummy_password_hash',
    'GOOGLE_CLIENT_ID' => 'google.client_id', 'GOOGLE_CLIENT_SECRET' => 'google.client_secret',
    'MALUMAIL_API_KEY' => 'malumail.api_key', 'MAIL_FROM' => 'malumail.from', 'MAIL_FROM_NAME' => 'malumail.from_name',
    'ASSISTANT_SERVICE_URL' => 'assistant.service_url',
    'OS_ENABLED' => 'os.enabled', 'APP_KEY' => 'os.app_key', 'OS_INTERNAL_URL' => 'os.internal_url', 'OS_LAUNCHER_URL' => 'os.launcher_url',
    'OS_APPLICATION_TOKEN' => 'os.application_token', 'ACTIONS_RELAY_KEY' => 'os.actions_relay_key',
    'MALUDB_API_URL' => 'os.maludb_api_url', 'MALUDB_API_TOKEN' => 'os.maludb_api_token',
];
$fromEnv = [];
foreach ($envMap as $envKey => $path) {
    $value = env($envKey);
    if ($value === null) {
        continue;
    }
    [$section, $name] = explode('.', $path, 2);
    $fromEnv[$section][$name] = (string) $value;
}
if (($fromEnv['app']['environment'] ?? '') === 'local') {
    $fromEnv['app']['environment'] = 'development';
}

return array_replace_recursive($defaults, $local, $fromEnv);
