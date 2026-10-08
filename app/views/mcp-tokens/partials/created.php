<?php /** @var array $created  @var string $baseUrl */
$url = mcp_token_endpoint($baseUrl, $created['scope']);
$server = 'processcore-' . $created['scope'];
$cli = 'claude mcp add --transport http ' . $server . ' ' . $url . ' --header "Authorization: Bearer ' . $created['token'] . '"';
$desktop = json_encode(['mcpServers' => [$server => [
    'command' => 'npx',
    'args' => ['-y', 'mcp-remote', $url, '--header', 'Authorization:${PROCESSCORE_AUTH}'],
    'env' => ['PROCESSCORE_AUTH' => 'Bearer ' . $created['token']],
]]], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
?>
<div class="col-lg-12">
    <div class="card border-success" id="mcp-token-created-card">
        <div class="card-header"><h5 class="card-title">Token for <?= e($created['name']) ?></h5></div>
        <div class="card-body">
            <div class="alert alert-warning" id="mcp-token-created-warning">Copy this token now. It is stored only as a hash and will not be shown again; if it is lost, revoke it and create another.</div>
            <p class="fw-semibold mb-2">Token (<?= e(MCP_TOKEN_SCOPES[$created['scope']] ?? $created['scope']) ?>)</p>
            <pre class="bg-light p-3 rounded text-wrap text-break" id="mcp-token-created-value"><code><?= e($created['token']) ?></code></pre>
            <p class="fw-semibold mb-2 mt-4">Server URL</p>
            <pre class="bg-light p-3 rounded text-wrap text-break" id="mcp-token-created-url"><code><?= e($url) ?></code></pre>
            <p class="fw-semibold mb-2 mt-4">Claude Code</p>
            <p class="fs-12 text-muted mb-2">Run in a terminal:</p>
            <pre class="bg-light p-3 rounded text-wrap text-break" id="mcp-token-created-claude-code"><code><?= e($cli) ?></code></pre>
            <p class="fw-semibold mb-2 mt-4">Claude Desktop</p>
            <p class="fs-12 text-muted mb-2">Settings, Developer, Edit config: add this to <code>claude_desktop_config.json</code> (needs Node.js), then restart Claude Desktop.</p>
            <pre class="bg-light p-3 rounded text-break" id="mcp-token-created-claude-desktop"><code><?= e($desktop) ?></code></pre>
            <p class="fw-semibold mb-2 mt-4">Any other MCP client</p>
            <p class="fs-12 text-muted mb-0" id="mcp-token-created-other">Streamable HTTP transport at the URL above, with the header <code>Authorization: Bearer &lt;token&gt;</code>.</p>
        </div>
    </div>
</div>
