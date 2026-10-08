<?php
declare(strict_types=1);
/**
 * The command bar and Ask me anything, run by the kernel (os-adoption; agents.md §5, sign-on-and-directory.md §5).
 * POST {OS_INTERNAL_URL}/api/v1/agents/chat.php?agent=expert with the application token and X-Acting-Member; render the
 * reply and the actions taken (a paused one says it waits for approval); fire the same HX-Trigger refresh events the
 * standalone assistant would (config/manifest.json tools[].refresh, by tool name); follow nothing blindly. Logs the
 * exchange as before — the kernel's run id joins the trails; the utterance text is kept, as the standalone log keeps it.
 */
function os_assistant_turn(array $user, string $surface, string $message, string $screen, string $entity, ?int $recordId, callable $render): void
{
    $started = microtime(true);
    $memberId = (int) ($user['os_member_id'] ?? 0);
    if ($memberId < 1) {
        http_response_code(403);
        echo $render(['message' => $message, 'reply' => 'Your account is not linked to the operating system; open ProcessCore from the launcher.', 'undoId' => null]);
        return;
    }
    $_SESSION['assistant_conversation'] ??= 'processcore-' . bin2hex(random_bytes(8));
    $answer = kernel_call('POST', '/api/v1/agents/chat.php?agent=expert', [
        'utterance' => $message, 'screen' => $screen !== '' ? $screen : null,
        'context' => ['entity' => $entity !== '' ? $entity : null, 'record_id' => $recordId, 'application' => os_app_key(), 'surface' => $surface],
        'conversation_id' => (string) $_SESSION['assistant_conversation'], 'wait' => $surface === 'ama' ? 90 : 60,
    ], ['X-Acting-Member: ' . $memberId], $surface === 'ama' ? 100 : 75);
    $body = $answer['body'] ?? [];
    $fallback = [400 => 'The kernel did not know who was asking.', 403 => 'You are not allowed to use the assistant here.',
                 404 => 'ProcessCore has no expert yet — a super-admin names one in the operating system.', 409 => 'The expert is busy; try again in a moment.',
                 422 => 'Say what you want in a sentence or two.'];
    $error = null;
    if ($answer === null || $answer['status'] === 401 || $answer['status'] >= 500) {
        $error = 'The operating system is not reachable right now. Try again in a minute.';
    } elseif ($answer['status'] >= 400) {
        $error = (string) ($body['error']['message'] ?? ($fallback[$answer['status']] ?? 'The assistant could not answer.'));
    }
    // A long run: poll until finished or the wait is spent.
    $deadline = time() + 55;
    while ($error === null && $answer['status'] === 202 && empty($body['finished']) && !empty($body['run_id']) && time() < $deadline) {
        usleep(1500000);
        $answer = kernel_call('GET', '/api/v1/agents/chat.php?run=' . (int) $body['run_id'], null, [], 20);
        if ($answer === null || $answer['status'] >= 400) { break; }
        $body = $answer['body'] ?? [];
    }
    $actions = is_array($body['actions'] ?? null) ? $body['actions'] : [];
    $reply = $error ?? (trim((string) ($body['reply'] ?? '')) ?: (empty($body['finished']) ? 'Still working — ask again in a moment.' : 'Done.'));
    if (!empty($body['approval_request_id'])) {
        $reply .= ' (Waiting for approval in the operating system.)';
    }
    // Refresh events: the manifest names them per tool; a tool the manifest does not know refreshes nothing.
    $events = [];
    static $refreshByTool = null;
    if ($refreshByTool === null) {
        $refreshByTool = [];
        $manifest = json_decode((string) @file_get_contents(dirname(__DIR__) . '/config/manifest.json'), true) ?: [];
        foreach ((array) ($manifest['tools'] ?? []) as $tool) {
            $refreshByTool[(string) ($tool['name'] ?? '')] = array_values(array_filter((array) ($tool['refresh'] ?? []), 'is_string'));
        }
    }
    foreach ($actions as $a) {
        if (($a['status'] ?? '') === 'ok' || ($a['status'] ?? '') === 'success') {
            foreach ($refreshByTool[(string) ($a['tool'] ?? '')] ?? [] as $ev) { $events[$ev] = true; }
        }
    }
    if ($events !== []) {
        header('HX-Trigger: ' . json_encode($events, JSON_THROW_ON_ERROR));
    }
    $activityId = null;
    try {
        $activityId = log_activity(db(), $surface === 'ama' ? 'ama_question' : 'assistant_message', $entity !== '' ? $entity : null, $recordId, null, null, null, [
            'message' => $message, 'reply' => mb_substr($reply, 0, 4000), 'surface' => $surface, 'screen' => $screen, 'kernel' => true,
            'run_id' => $body['run_id'] ?? null, 'status' => $body['status'] ?? ($answer['status'] ?? 'unreachable'), 'actions' => array_map(static fn ($a) => ['tool' => (string) ($a['tool'] ?? ''), 'status' => (string) ($a['status'] ?? '')], array_slice($actions, 0, 30)),
            'approval_request_id' => $body['approval_request_id'] ?? null, 'cost' => $body['cost'] ?? null, 'duration_ms' => (int) round((microtime(true) - $started) * 1000),
        ], $screen !== '' ? $screen : ($surface === 'ama' ? 'ama' : null), $surface);
    } catch (Throwable $e) {
        error_log('assistant exchange log failed: ' . $e->getMessage());
    }
    if ($error !== null) {
        http_response_code($answer === null || $answer['status'] >= 500 ? 503 : $answer['status']);
    }
    echo $render(['message' => $message, 'reply' => $reply, 'undoId' => null, 'pending' => null, 'navigate' => null, 'sources' => [],
        'activityId' => $activityId, 'surface' => $surface, 'context' => ['screen' => $screen, 'entity' => $entity, 'record_id' => $recordId],
        'occurredAt' => (new DateTimeImmutable())->format(DATE_ATOM), 'actions' => $actions]);
}
