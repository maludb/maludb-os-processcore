<?php
declare(strict_types=1);
require_once dirname(__DIR__, 2) . '/app/bootstrap.php';

// One assistant turn for the command bar (every screen) or the Ask me anything page.
// Thin proxy: session auth + CSRF, mint the action token, call the unified assistant
// service on localhost, remember the session id, log the exchange (PHP is the one place
// assistant turns are logged), and answer with HTMX:
//   navigation  -> HX-Location {"path", "target": "#page-content"} (+ the reply partial,
//                  which the bar shows itself because htmx does not swap HX-Location bodies)
//   data action -> reply partial with Undo + HX-Trigger with the refresh events
//   confirmation-> reply partial with a Confirm button that re-posts with confirmed=1
$user = require_login();
require_post();
verify_csrf();

$surface  = request_string('source', 20) === 'ama' ? 'ama' : 'command_bar';
$message  = request_string('message', 2000);
$screen   = request_string('screen', 80);
$entity   = request_string('entity', 80);
$recordId = request_integer('record_id');
$confirmed = request_string('confirmed', 1) === '1';

$render = static function (array $data) use ($surface): string {
    return $surface === 'ama' ? view('ama/exchange.php', $data) : view('assistant/reply.php', $data);
};

if ($message === '') {
    http_response_code(422);
    echo $render(['message' => '', 'reply' => 'Say or type something first.', 'undoId' => null]);
    exit;
}

// Beside the Business OS kernel (sign-on-and-directory.md §5): the utterance goes to the kernel's chat endpoint as the
// acting person and ONE turn of ProcessCore's expert answers — its tools attached, every model call ledgered, approvals paused
// in the kernel. ProcessCore holds no model key and runs no assistant service while OS_ENABLED is on.
if (os_enabled()) {
    require_once dirname(__DIR__, 2) . '/app/os_assistant.php';
    os_assistant_turn($user, $surface, $message, $screen, $entity, $recordId, $render);
    exit;
}

$started = microtime(true);
$payload = [
    'user'         => ['id' => (int) $user['id'], 'display_name' => (string) $user['display_name'], 'role' => (string) $user['role']],
    'session_id'   => $_SESSION['assistant_session_id'] ?? null,
    'surface'      => $surface,
    'message'      => $message,
    'screen'       => $screen !== '' ? $screen : null,
    'entity'       => $entity !== '' ? $entity : null,
    'record_id'    => $recordId,
    'action_token' => mint_action_token((int) $user['id'], 300),
    'confirmed'    => $confirmed,
    'today'        => (new DateTimeImmutable('now', new DateTimeZone((string) config('app.timezone', 'UTC'))))->format('Y-m-d'),
    'timezone'     => (string) config('app.timezone', 'UTC'),
];

$result = assistant_call($payload, $surface === 'ama' ? 60 : 20);
if ($result === null) {
    $result = ['reply' => 'The assistant is not available right now. Try again in a minute.', 'mode' => 'down', 'error' => 'service_unavailable'];
}
if (!empty($result['session_id']) && is_string($result['session_id'])) {
    $_SESSION['assistant_session_id'] = $result['session_id'];
}

$reply    = trim((string) ($result['reply'] ?? '')) ?: 'Done.';
$navigate = assistant_navigate($result['navigate'] ?? null);
$refresh  = array_values(array_filter((array) ($result['refresh'] ?? []), static fn ($n) => is_string($n) && preg_match('/^[A-Za-z][A-Za-z0-9_:.\-]{0,63}$/', $n)));
$undoId   = isset($result['undo_id']) && (is_string($result['undo_id']) || is_int($result['undo_id'])) ? (string) $result['undo_id'] : null;
$pending  = isset($result['needs_confirmation']) && is_string($result['needs_confirmation']) && $result['needs_confirmation'] !== '' ? $result['needs_confirmation'] : null;
$sources  = array_values(array_intersect((array) ($result['sources'] ?? []), ['records', 'activity']));
$toolCalls = array_map(static fn ($c) => ['tool' => (string) ($c['tool'] ?? ''), 'is_error' => (bool) ($c['is_error'] ?? false)],
    array_slice(is_array($result['tool_calls'] ?? null) ? $result['tool_calls'] : [], 0, 30));

// Activity memory: one row per exchange (question, tool calls, answer length, duration).
$activityId = null;
try {
    $activityId = log_activity(db(), $surface === 'ama' ? 'ama_question' : 'assistant_message',
        $entity !== '' ? $entity : null, $recordId, null, null, null, [
            'message'            => $message,
            'reply'              => mb_substr($reply, 0, 4000),
            'surface'            => $surface,
            'screen'             => $screen,
            'confirmed'          => $confirmed,
            'session_id'         => $result['session_id'] ?? null,
            'mode'               => $result['mode'] ?? null,
            'tool_calls'         => $toolCalls,
            'sources'            => $sources,
            'answer_length'      => mb_strlen($reply),
            'duration_ms'        => (int) round((microtime(true) - $started) * 1000),
            'service_duration_ms'=> (int) ($result['duration_ms'] ?? 0),
            'navigate'           => $navigate['path'] ?? null,
            'undo_id'            => $undoId,
            'refresh'            => $refresh,
            'needs_confirmation' => $pending,
            'error'              => $result['error'] ?? null,
        ], $screen !== '' ? $screen : ($surface === 'ama' ? 'ama' : null), $surface);
} catch (Throwable $exception) {
    error_log('assistant exchange log failed: ' . $exception->getMessage());
}

if ($refresh !== []) {
    header('HX-Trigger: ' . json_encode(array_fill_keys($refresh, true), JSON_THROW_ON_ERROR));
}
$data = [
    'message' => $message, 'reply' => $reply, 'undoId' => $undoId, 'pending' => $pending,
    'navigate' => $navigate, 'sources' => $sources, 'activityId' => $activityId, 'surface' => $surface,
    'context' => ['screen' => $screen, 'entity' => $entity, 'record_id' => $recordId],
    'occurredAt' => (new DateTimeImmutable())->format(DATE_ATOM),
];
if ($navigate !== null && $surface === 'command_bar') {
    header('HX-Location: ' . json_encode(['path' => $navigate['path'], 'target' => '#page-content', 'swap' => 'innerHTML'], JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES));
}
echo $render($data);

/** POST the turn to the assistant service; null when it is down or answers garbage. */
function assistant_call(array $payload, int $timeoutSeconds): ?array
{
    $url = rtrim((string) config('assistant.service_url', 'http://127.0.0.1:8765'), '/') . '/message';
    $curl = curl_init($url);
    curl_setopt_array($curl, [
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => json_encode($payload, JSON_THROW_ON_ERROR),
        CURLOPT_HTTPHEADER     => ['Content-Type: application/json', 'Accept: application/json'],
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => 2,
        CURLOPT_TIMEOUT        => $timeoutSeconds,
        CURLOPT_PROTOCOLS      => CURLPROTO_HTTP,
    ]);
    $body = curl_exec($curl);
    $status = (int) curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
    $error = curl_error($curl);
    curl_close($curl);
    if ($body === false || $status !== 200) {
        error_log(sprintf('assistant service call failed: HTTP %d %s', $status, $error));
        return null;
    }
    $decoded = json_decode((string) $body, true);
    return is_array($decoded) ? $decoded : null;
}

/** A navigation directive is only ever a same-origin path swapped into #page-content. */
function assistant_navigate(mixed $directive): ?array
{
    $path = is_array($directive) ? ($directive['path'] ?? null) : null;
    if (!is_string($path) || !str_starts_with($path, '/') || str_starts_with($path, '//') || preg_match('/[\s\\\\<>"\']/', $path)) {
        return null;
    }
    return ['path' => $path, 'target' => '#page-content'];
}
