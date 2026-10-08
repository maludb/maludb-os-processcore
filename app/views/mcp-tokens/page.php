<?php /** @var array $result  @var array $query  @var string $baseUrl  @var ?array $created  @var array $input  @var array $errors */
$actions = '<button type="submit" form="mcp-token-form" id="mcp-token-form-save-btn" class="btn btn-primary"><i class="feather-key me-2"></i><span>Create token</span></button>';
$p = 'mcp-token-form';
?>
<?= view('shared/page-header.php', ['title' => 'AI access tokens', 'screen' => 'settings-mcp-tokens', 'crumbs' => ['Setup' => null, 'AI access tokens' => null], 'actionsHtml' => $actions]) ?>
<div class="main-content" id="settings-mcp-tokens-content">
    <?php if ($created !== null): ?>
        <div class="row"><?= view('mcp-tokens/partials/created.php', ['created' => $created, 'baseUrl' => $baseUrl]) ?></div>
    <?php endif; ?>
    <div class="row">
        <div class="col-xxl-4 col-xl-6">
            <div class="card" id="mcp-token-form-card">
                <div class="card-header"><h5 class="card-title">New token</h5></div>
                <div class="card-body">
                    <form id="mcp-token-form" method="post" action="/settings/mcp-tokens/save" hx-post="/settings/mcp-tokens/save" hx-target="#page-content" hx-swap="innerHTML">
                        <?= csrf_field() ?>
                        <?= view('shared/validation-errors.php', ['errors' => $errors, 'id' => 'mcp-token-form-errors']) ?>
                        <?= form_input($p, 'name', 'Name', $input['name'], $errors, ['required' => true, 'maxlength' => 80, 'icon' => 'feather-tag', 'placeholder' => 'Ed laptop Claude Desktop', 'help' => 'Who or what uses it. The name appears in the activity log on every call.']) ?>
                        <?= form_select($p, 'scope', 'Can read', MCP_TOKEN_SCOPES, $input['scope'], $errors, ['required' => true, 'last' => true, 'help' => 'One server per token. Create a second token for the other server.']) ?>
                    </form>
                </div>
            </div>
        </div>
        <div class="col-xxl-8 col-xl-6">
            <div class="card" id="settings-mcp-tokens-endpoints-card">
                <div class="card-header"><h5 class="card-title">Connect your own AI tools</h5></div>
                <div class="card-body">
                    <p class="text-muted">Claude Desktop, Claude Code and other MCP clients can read ProcessCore's memory through two read-only servers. Each call needs a token in the <code>Authorization</code> header.</p>
                    <?= detail_row('settings-mcp-tokens-records-url', 'Records server', '<code id="settings-mcp-tokens-records-url-value" class="text-break">' . e(mcp_token_endpoint($baseUrl, 'records')) . '</code>') ?>
                    <?= detail_row('settings-mcp-tokens-activity-url', 'Activity server', '<code id="settings-mcp-tokens-activity-url-value" class="text-break">' . e(mcp_token_endpoint($baseUrl, 'activity')) . '</code>') ?>
                    <?= detail_row('settings-mcp-tokens-header', 'Header', '<code class="text-break">Authorization: Bearer &lt;token&gt;</code>', true) ?>
                    <p class="fs-12 text-muted mt-4 mb-0">Nothing these servers do can change data. Revoke a token to cut its access immediately.</p>
                </div>
            </div>
        </div>
    </div>
    <div class="row">
        <?= view('mcp-tokens/partials/table.php', ['result' => $result, 'query' => $query]) ?>
    </div>
</div>
