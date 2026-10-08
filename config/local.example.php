<?php
// Template for config/local.php (gitignored). Copy, fill in, then:
//   chown <deploy user>:www-data config/local.php && chmod 0640 config/local.php
// Every key here overrides the same key in config/application.php; keys you
// leave out keep their default. Read in code with config('db.name').
return [
    'db' => [
        'host'     => '127.0.0.1',
        'port'     => '5432',
        'name'     => 'processcore_dev',          // processcore_<slug> from deploy/provision-client.sh
        'user'     => 'processcore_app',
        'password' => '',                    // ALTER ROLE processcore_app PASSWORD '...'
    ],
    'app' => [
        'base_url'    => 'https://processcore.example.com',   // public URL, no trailing slash; used in invite links and the Google redirect URI
        'environment' => 'production',                    // or 'development'
    ],
    'security' => [
        'totp_key'            => '',   // openssl rand -hex 32  (encrypts TOTP seeds at rest)
        'action_token_key'    => '',   // openssl rand -hex 32  (HMAC for assistant action tokens; must equal PROCESSCORE_ACTION_TOKEN_KEY in services.env)
        'dummy_password_hash' => '',   // php -r "echo password_hash(bin2hex(random_bytes(16)), PASSWORD_BCRYPT, ['cost' => 12]);"
    ],
    'google' => [                      // optional: leave empty to disable Google sign-in
        'client_id'     => '',
        'client_secret' => '',
    ],
    'malumail' => [                    // optional: leave api_key empty to log mail to the Apache error log instead of sending
        'api_key'   => '',
        'from'      => 'noreply@example.com',
        'from_name' => 'ProcessCore',
    ],
];
