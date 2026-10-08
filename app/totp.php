<?php
declare(strict_types=1);

use OTPHP\TOTP;
use chillerlan\QRCode\QRCode;
use chillerlan\QRCode\QROptions;

// Authenticator-app 2FA helpers. Secrets are encrypted at rest with libsodium
// secretbox under config('security.totp_key'); a database dump alone yields nothing.

function totp_key(): string
{
    $hex = (string) config('security.totp_key');
    if (strlen($hex) !== 64) {
        throw new RuntimeException('security.totp_key must be 64 hex characters.');
    }
    return sodium_hex2bin($hex);
}

function totp_encrypt_secret(string $secret): string
{
    $nonce = random_bytes(SODIUM_CRYPTO_SECRETBOX_NONCEBYTES);
    return sodium_bin2base64($nonce . sodium_crypto_secretbox($secret, $nonce, totp_key()), SODIUM_BASE64_VARIANT_ORIGINAL);
}

function totp_decrypt_secret(string $encrypted): string
{
    $raw = sodium_base642bin($encrypted, SODIUM_BASE64_VARIANT_ORIGINAL);
    $nonce = substr($raw, 0, SODIUM_CRYPTO_SECRETBOX_NONCEBYTES);
    $plain = sodium_crypto_secretbox_open(substr($raw, SODIUM_CRYPTO_SECRETBOX_NONCEBYTES), $nonce, totp_key());
    if ($plain === false) {
        throw new RuntimeException('TOTP secret could not be decrypted.');
    }
    return $plain;
}

function totp_new_secret(): string
{
    // 160-bit secret (RFC 4226 minimum): 32 base32 characters, easy to type by hand.
    return ParagonIE\ConstantTime\Base32::encodeUpperUnpadded(random_bytes(20));
}

function totp_provisioning_uri(string $secret, string $email): string
{
    $totp = TOTP::createFromSecret($secret);
    $totp->setLabel($email);
    $totp->setIssuer((string) config('app.name', 'ProcessCore'));
    return $totp->getProvisioningUri();
}

/** QR code as an SVG data URI, rendered server side (no external service). */
function totp_qr_data_uri(string $uri): string
{
    $options = new QROptions(['outputBase64' => true, 'svgAddXmlHeader' => false, 'scale' => 5]);
    return (new QRCode($options))->render($uri);
}

/** Verify a 6-digit code within a ±1 timestep window; returns the matched timestep or null. */
function totp_verify(string $secret, string $code): ?int
{
    $code = preg_replace('/\s+/', '', $code) ?? '';
    if (!preg_match('/^\d{6}$/', $code)) {
        return null;
    }
    $totp = TOTP::createFromSecret($secret);
    $now = time();
    foreach ([0, -1, 1] as $offset) {
        $at = $now + $offset * $totp->getPeriod();
        if (hash_equals($totp->at($at), $code)) {
            return intdiv($at, $totp->getPeriod());
        }
    }
    return null;
}

/** Ten single-use recovery codes, shown once; stored hashed. */
function generate_recovery_codes(): array
{
    $codes = [];
    for ($i = 0; $i < 10; $i++) {
        $raw = strtoupper(bin2hex(random_bytes(5)));
        $codes[] = substr($raw, 0, 5) . '-' . substr($raw, 5, 5);
    }
    return $codes;
}
