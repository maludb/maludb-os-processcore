<?php
declare(strict_types=1);

/**
 * JSON mode for the Business OS kernel's actions server (maludb-os-integration, mcp-and-api.md §3), os-adoption 2026-10-04.
 *
 * ProcessCore's handlers answer HTMX: a success is a 2xx with HX-Location (navigate to the record) and HX-Trigger; a
 * validation failure is a 422 with the form re-rendered (invalid-feedback divs beside their inputs, alert-danger
 * lists); 403/404 render shared/error.php. The kernel's actions server wants {ok:true, location} · 422
 * {error:{code:'invalid', message, errors, fields}} · {error:{code, message}}. Rather than rewrite 130 handlers,
 * the whole answer is buffered and translated at shutdown — the same reading ProcessCore's own actions server does in
 * Python (services/actions_mcp/php.py). A handler that reports nothing a browser would not also see still answers.
 */

function json_mode_active(): bool
{
    return !empty($GLOBALS['__json_mode']);
}

function json_mode_begin(): void
{
    $GLOBALS['__json_mode'] = true;
    ob_start();
    register_shutdown_function('json_mode_finish');
}

/** The handler explicitly says what happened (new handlers may call this; the shim reads the rest). */
function emit_action_status(bool $ok, array $data = []): void
{
    $GLOBALS['__json_status'] = ['ok' => $ok] + $data;
}

function json_mode_finish(): void
{
    if (!json_mode_active() || !empty($GLOBALS['__json_done'])) {
        return;
    }
    $GLOBALS['__json_done'] = true;
    $html = '';
    while (ob_get_level() > 0) {
        $html = (string) ob_get_clean() . $html;
    }
    $status = http_response_code() ?: 200;
    $location = null;
    $triggers = [];
    foreach (headers_list() as $line) {
        if (stripos($line, 'HX-Location:') === 0) {
            $raw = trim(substr($line, 12));
            $decoded = json_decode($raw, true);
            $location = is_array($decoded) ? (string) ($decoded['path'] ?? '') : $raw;
        } elseif (stripos($line, 'HX-Redirect:') === 0 || stripos($line, 'Location:') === 0) {
            $location = trim(substr($line, strpos($line, ':') + 1));
        } elseif (stripos($line, 'HX-Trigger:') === 0) {
            $raw = trim(substr($line, 11));
            $decoded = json_decode($raw, true);
            $triggers = is_array($decoded) ? array_keys($decoded) : array_values(array_filter(array_map('trim', explode(',', $raw))));
        }
    }
    foreach (['HX-Location', 'HX-Redirect', 'Location', 'HX-Trigger', 'HX-Reswap', 'HX-Retarget', 'Content-Type', 'Set-Cookie'] as $h) {
        header_remove($h);
    }
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');

    $reported = $GLOBALS['__json_status'] ?? null;
    $errors = json_mode_errors($html);
    $message = json_mode_error_message($html);
    $launcher = $location !== null && str_contains($location, 'app=');            // os_to_launcher(): not signed in

    if (is_array($reported) && $reported['ok'] === true) {
        http_response_code(200);
        echo json_encode(['ok' => true] + array_diff_key($reported, ['ok' => true]) + ['location' => $location, 'triggers' => $triggers], JSON_UNESCAPED_SLASHES);
        return;
    }
    if ($status === 401 || $launcher) {
        http_response_code(401);
        echo json_encode(['error' => ['code' => 'unauthorized', 'message' => 'The token names no one ProcessCore admits.']]);
        return;
    }
    if ($status < 400 && $errors === [] && (is_array($reported) ? $reported['ok'] : true)) {
        http_response_code(200);
        $out = ['ok' => true, 'location' => $location, 'triggers' => $triggers];
        if (preg_match('/data-record-id="(\d+)"/', $html, $m)) {
            $out['record_id'] = (int) $m[1];
        }
        // ProcessCore's handlers navigate to the LIST after a save; the kernel wants the record. The handler logged the
        // record it touched under this request id (every write does) — that row names it.
        if (!isset($out['record_id']) && (!is_string($location) || !preg_match('~/(\d+)/?(?:[?#].*)?$~', $location))) {
            try {
                $st = db()->prepare('SELECT entity_type, entity_id FROM app.activity_log WHERE request_id = :r AND entity_id IS NOT NULL AND action <> \'screen_entered\' ORDER BY id DESC LIMIT 1');
                $st->execute(['r' => request_id()]);
                if (($row = $st->fetch()) !== false) {
                    $out['record_id'] = (int) $row['entity_id'];
                    $out['entity_type'] = (string) $row['entity_type'];
                    if (is_string($location) && $location !== '') {
                        $out['location'] = rtrim($location, '/') . '/' . $row['entity_id'];
                    }
                }
            } catch (Throwable $e) {
                error_log('json mode record lookup: ' . $e->getMessage());
            }
        }
        echo json_encode($out, JSON_UNESCAPED_SLASHES);
        return;
    }
    if ($status === 422 || ($status < 400 && $errors !== []) || (is_array($reported) && !empty($reported['errors']))) {
        $list = is_array($reported) && !empty($reported['errors']) ? (array) $reported['errors'] : $errors;
        $fields = [];
        $plain = [];
        foreach ($list as $e) {
            if (is_array($e) && isset($e['field'], $e['message']) && $e['field'] !== null) {
                $fields[(string) $e['field']] = (string) $e['message'];
                $plain[] = $e['field'] . ': ' . $e['message'];
            } else {
                $plain[] = is_array($e) ? (string) ($e['message'] ?? '') : (string) $e;
            }
        }
        http_response_code(422);
        echo json_encode(['error' => ['code' => 'invalid', 'message' => $plain !== [] ? implode(' ', $plain) : 'The input was not accepted.', 'errors' => $plain, 'fields' => $fields]], JSON_UNESCAPED_SLASHES);
        return;
    }
    $codes = [400 => 'bad_request', 403 => 'forbidden', 404 => 'not_found', 405 => 'method_not_allowed', 409 => 'conflict', 429 => 'rate_limited'];
    $code = $status >= 500 ? 'server_error' : ($codes[$status] ?? 'error');
    http_response_code($status >= 400 ? $status : 500);
    echo json_encode(['error' => ['code' => $code, 'message' => $status >= 500 ? 'Something went wrong.' : ($message ?: ($reported['message'] ?? 'The action was refused.'))]], JSON_UNESCAPED_SLASHES);
}

/** [{field, message}] from a re-rendered form: each invalid-feedback is attributed to the nearest preceding input name. */
function json_mode_errors(string $html): array
{
    $errors = [];
    $text = static fn (string $fragment): string => trim(preg_replace('/\s+/', ' ', html_entity_decode(strip_tags($fragment), ENT_QUOTES | ENT_HTML5)) ?? '');
    if (preg_match_all('/<div class="invalid-feedback[^"]*">(.*?)<\/div>/s', $html, $all, PREG_OFFSET_CAPTURE)) {
        foreach ($all[0] as $i => [$whole, $offset]) {
            $before = substr($html, 0, $offset);
            $field = null;
            if (preg_match_all('/<(?:input|select|textarea)[^>]*\sname="([^"]+)"/', $before, $names)) {
                $field = end($names[1]) ?: null;
            }
            $msg = $text($all[1][$i][0]);
            if ($msg !== '') {
                $errors[] = ['field' => $field, 'message' => $msg];
            }
        }
    }
    // The summary block repeats the field messages; keep only what the fields did not already say.
    $seen = array_map(static fn (array $e): string => $e['message'], $errors);
    if (preg_match_all('/<div class="alert alert-danger[^"]*"[^>]*>(.*?)<\/div>/s', $html, $blocks)) {
        foreach ($blocks[1] as $block) {
            $items = preg_match_all('/<li[^>]*>(.*?)<\/li>/s', $block, $li) ? $li[1] : [$block];
            foreach ($items as $item) {
                $msg = $text($item);
                if ($msg !== '' && !in_array($msg, $seen, true)) {
                    $errors[] = ['field' => null, 'message' => $msg];
                    $seen[] = $msg;
                }
            }
        }
    }
    return $errors;
}

function json_mode_error_message(string $html): string
{
    if (preg_match('/id="error-message"[^>]*>(.*?)<\//s', $html, $m)) {
        return trim(html_entity_decode(strip_tags($m[1]), ENT_QUOTES | ENT_HTML5));
    }
    return '';
}
