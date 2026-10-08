<?php
/** @var string $title  @var string $screen  @var string $content */
$user = current_user();
$flashes = take_flashes();
$appName = (string) config('app.name', 'ProcessCore');
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta http-equiv="x-ua-compatible" content="IE=edge" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="csrf-token" content="<?= e(csrf_token()) ?>" id="csrf-token-meta" />
    <meta name="htmx-config" content='{"responseHandling":[{"code":"204","swap":false},{"code":"[23]..","swap":true},{"code":"(403|404|409|422)","swap":true,"error":false},{"code":"[45]..","swap":false,"error":true}]}' />
    <title><?= e($appName) ?> || <?= e($title) ?></title>
    <link rel="shortcut icon" type="image/png" href="/assets/images/favicon.png" />
    <link rel="stylesheet" type="text/css" href="/assets/css/bootstrap.min.css" />
    <link rel="stylesheet" type="text/css" href="/assets/vendors/css/vendors.min.css" />
    <link rel="stylesheet" type="text/css" href="/assets/css/theme.min.css" />
    <link rel="stylesheet" type="text/css" href="/assets/css/app-overrides.css?v=20261005a" />
</head>
<body hx-boost="false">
    <nav class="nxl-navigation" id="left-sidenav">
        <div class="navbar-wrapper">
            <div class="m-header">
                <a href="/" class="b-brand" id="sidenav-brand">
                    <img src="/assets/images/logo-full.png" alt="<?= e($appName) ?>" class="logo logo-lg" />
                    <img src="/assets/images/logo-abbr.png" alt="<?= e($appName) ?>" class="logo logo-sm" />
                </a>
            </div>
            <div class="navbar-content">
                <ul class="nxl-navbar" id="sidenav-menu">
                    <li class="nxl-item nxl-caption"><label>Navigation</label></li>
                    <?php foreach (navigation_groups() as $group): ?>
                        <?php $groupId = strtolower(preg_replace('/[^a-z0-9]+/i', '-', $group['label'])); ?>
                        <li class="nxl-item nxl-hasmenu" id="nav-group-<?= e($groupId) ?>">
                            <a href="javascript:void(0);" class="nxl-link">
                                <span class="nxl-micon"><i class="<?= e($group['icon']) ?>"></i></span>
                                <span class="nxl-mtext"><?= e($group['label']) ?></span><span class="nxl-arrow"><i class="feather-chevron-right"></i></span>
                            </a>
                            <ul class="nxl-submenu">
                                <?php foreach ($group['items'] as $item): ?>
                                    <?php if (isset($item['roles']) && ($user === null || !user_can($user, ...$item['roles']))) { continue; } ?>
                                    <li class="nxl-item">
                                        <?php if ($item['url'] === '/'): ?>
                                            <a id="nav-<?= e($item['screen']) ?>" class="nxl-link" href="/"><?= e($item['label']) ?></a>
                                        <?php else: ?>
                                            <a id="nav-<?= e($item['screen']) ?>" class="nxl-link" href="<?= e($item['url']) ?>"
                                               hx-get="<?= e($item['url']) ?>" hx-target="#page-content" hx-swap="innerHTML" hx-push-url="<?= e($item['url']) ?>"><?= e($item['label']) ?></a>
                                        <?php endif; ?>
                                    </li>
                                <?php endforeach; ?>
                            </ul>
                        </li>
                    <?php endforeach; ?>
                </ul>
            </div>
        </div>
    </nav>
    <header class="nxl-header" id="top-header">
        <div class="header-wrapper">
            <div class="header-left d-flex align-items-center gap-4">
                <a href="javascript:void(0);" class="nxl-head-mobile-toggler" id="mobile-collapse">
                    <div class="hamburger hamburger--arrowturn">
                        <div class="hamburger-box"><div class="hamburger-inner"></div></div>
                    </div>
                </a>
                <div class="nxl-navigation-toggle">
                    <a href="javascript:void(0);" id="menu-mini-button"><i class="feather-align-left"></i></a>
                    <a href="javascript:void(0);" id="menu-expend-button" style="display: none"><i class="feather-arrow-right"></i></a>
                </div>
            </div>
            <div class="header-right ms-auto">
                <div class="d-flex align-items-center">
                    <div class="nxl-h-item dark-light-theme">
                        <a href="javascript:void(0);" class="nxl-head-link me-0 dark-button" id="header-dark-btn"><i class="feather-moon"></i></a>
                        <a href="javascript:void(0);" class="nxl-head-link me-0 light-button" id="header-light-btn" style="display: none"><i class="feather-sun"></i></a>
                    </div>
                    <div class="dropdown nxl-h-item">
                        <a id="header-profile-toggle" href="javascript:void(0);" data-bs-toggle="dropdown" role="button" data-bs-auto-close="outside">
                            <img src="/assets/images/avatar/1.png" alt="" class="img-fluid user-avtar me-0" />
                        </a>
                        <div class="dropdown-menu dropdown-menu-end nxl-h-dropdown nxl-user-dropdown" id="header-profile-menu">
                            <div class="dropdown-header">
                                <div class="d-flex align-items-center">
                                    <img src="/assets/images/avatar/1.png" alt="" class="img-fluid user-avtar" />
                                    <div>
                                        <h6 class="text-dark mb-0" id="header-profile-name"><?= e($user['display_name'] ?? '') ?> <span class="badge bg-soft-success text-success ms-1"><?= e(ucfirst($user['role'] ?? '')) ?></span></h6>
                                        <span class="fs-12 fw-medium text-muted" id="header-profile-email"><?= e($user['email'] ?? '') ?></span>
                                    </div>
                                </div>
                            </div>
                            <div class="dropdown-divider"></div>
                            <a href="/settings/profile" class="dropdown-item" id="header-profile-details" hx-get="/settings/profile" hx-target="#page-content" hx-swap="innerHTML" hx-push-url="/settings/profile">
                                <i class="feather-user"></i><span>My profile</span>
                            </a>
                            <a href="/settings/2fa" class="dropdown-item" id="header-2fa-settings" hx-get="/settings/2fa" hx-target="#page-content" hx-swap="innerHTML" hx-push-url="/settings/2fa">
                                <i class="feather-shield"></i><span>Two-factor authentication</span>
                            </a>
                            <div class="dropdown-divider"></div>
                            <form method="post" action="/logout" id="header-logout-form">
                                <?= csrf_field() ?>
                                <button type="submit" class="dropdown-item" id="header-logout">
                                    <i class="feather-log-out"></i><span>Logout</span>
                                </button>
                            </form>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </header>
    <main class="nxl-container">
        <div class="nxl-content" id="page-content">
            <?php foreach ($flashes as $flash): ?>
                <?= view('shared/flash.php', $flash) ?>
            <?php endforeach; ?>
            <?= $content ?>
        </div>
        <footer class="footer" id="page-footer">
            <p class="fs-11 text-muted fw-medium text-uppercase mb-0 copyright">
                <span>Copyright &copy; <?= date('Y') ?> <?= e($appName) ?></span>
            </p>
            <div class="d-flex align-items-center gap-4">
                <a href="/ama/" class="fs-11 fw-semibold text-uppercase" id="footer-ama" hx-get="/ama/" hx-target="#page-content" hx-swap="innerHTML" hx-push-url="/ama/">Ask me anything</a>
            </div>
        </footer>
    </main>
    <?= view('assistant/bar.php', ['screen' => $screen]) ?>
    <script>
        // Keep --assistant-bar-height equal to the bar's real height (it grows when a reply
        // shows), so body padding and the pinned footer always clear it (app-overrides.css).
        (function () {
            var bar = document.getElementById('assistant-bar');
            if (!bar) { return; }
            var apply = function () { document.documentElement.style.setProperty('--assistant-bar-height', bar.offsetHeight + 'px'); };
            apply();
            if (window.ResizeObserver) { new ResizeObserver(apply).observe(bar); } else { window.addEventListener('resize', apply); }
        })();
    </script>
    <script src="/assets/vendors/js/htmx.min.js"></script>
    <script>
        // CSRF for every non-GET HTMX request (php-session-auth wiring).
        document.body.addEventListener('htmx:configRequest', function (e) {
            if (e.detail.verb !== 'get') {
                e.detail.headers['X-CSRF-Token'] = document.querySelector('#csrf-token-meta').content;
            }
        });
        // Re-run the imperative bits of the theme for swapped-in content.
        document.body.addEventListener('htmx:afterSwap', function (evt) {
            evt.detail.target.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(function (el) { new bootstrap.Tooltip(el); });
            if (evt.detail.target.id === 'page-content') {
                window.scrollTo(0, 0);
                var nav = document.querySelector('nav.nxl-navigation');
                if (nav && nav.classList.contains('mob-navigation-active')) { document.getElementById('mobile-collapse').click(); }
                var input = document.getElementById('assistant-input');
                if (input) { input.setAttribute('data-screen', (document.getElementById('screen-context') || {}).dataset ? document.getElementById('screen-context').dataset.screen : ''); }
            }
        });
        // Unsaved changes on a form page (shared/page-header.php marks its header .page-header-form
        // with data-form = the form id). Editing the form flags the header; leaving the page
        // (navigation into #page-content, a reload, closing the tab) asks first. A 422 re-render
        // keeps the flag because the input is still unsaved.
        function formHeader() { return document.querySelector('#page-content .page-header-form'); }
        function isDirty() { var h = formHeader(); return !!(h && h.classList.contains('is-dirty')); }
        function markDirty(evt) {
            var h = formHeader(), form = evt.target && evt.target.form;
            if (h && form && form.getAttribute('id') === h.dataset.form && evt.target.type !== 'hidden') { h.classList.add('is-dirty'); }
        }
        document.addEventListener('input', markDirty);
        document.addEventListener('change', markDirty);
        document.body.addEventListener('htmx:confirm', function (evt) {
            var h = formHeader();
            if (!isDirty() || evt.detail.target !== document.getElementById('page-content')) { return; }
            var src = evt.detail.elt, form = src && (src.tagName === 'FORM' ? src : src.form || (src.closest && src.closest('form')));
            if (form && form.getAttribute('id') === h.dataset.form) { return; }   // the form's own save
            if (src && src.getAttribute && src.getAttribute('form') === h.dataset.form) { return; }
            evt.preventDefault();
            if (window.confirm('You have unsaved changes. Leave this page without saving?')) { h.classList.remove('is-dirty'); evt.detail.issueRequest(); }
        });
        // A successful save answers with HX-Location; clear the flag before that navigation starts.
        document.body.addEventListener('htmx:beforeOnLoad', function (evt) {
            var h = formHeader(), elt = evt.detail.elt, xhr = evt.detail.xhr;
            if (!h || !xhr || xhr.status >= 400) { return; }
            var form = elt && (elt.tagName === 'FORM' ? elt : elt.form || (elt.closest && elt.closest('form')));
            if ((form && form.getAttribute('id') === h.dataset.form) || (elt && elt.getAttribute && elt.getAttribute('form') === h.dataset.form)) { h.classList.remove('is-dirty'); }
        });
        // (afterSettle, not afterSwap: htmx's settle step resets the header's class attribute.)
        document.body.addEventListener('htmx:afterSettle', function (evt) {
            if (evt.detail.target.id === 'page-content' && evt.detail.xhr && evt.detail.xhr.status === 422) {
                var h = formHeader(); if (h) { h.classList.add('is-dirty'); }
            }
        });
        window.addEventListener('beforeunload', function (e) { if (isDirty()) { e.preventDefault(); e.returnValue = ''; } });
        // Session expiry: a 401/403 on a swap means re-authenticate with a full navigation.
        document.body.addEventListener('htmx:responseError', function (evt) {
            if (evt.detail.xhr.status === 401) { window.location.href = '/login'; }
        });
        // Command bar focus: Ctrl/Cmd+K anywhere, or "/" outside inputs.
        document.addEventListener('keydown', function (e) {
            var input = document.getElementById('assistant-input');
            if (!input) return;
            var typing = ['INPUT', 'TEXTAREA', 'SELECT'].indexOf(document.activeElement.tagName) !== -1 || document.activeElement.isContentEditable;
            if (((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') || (e.key === '/' && !typing)) {
                e.preventDefault();
                input.focus();
            }
        });
    </script>
    <script src="/assets/vendors/js/vendors.min.js"></script>
    <script src="/assets/js/common-init.min.js"></script>
    <script src="/assets/js/theme-customizer-init.min.js"></script>
</body>
</html>
