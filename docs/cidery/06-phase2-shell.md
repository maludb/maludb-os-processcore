# Phase 2: authentication and the application shell

**Date:** 2026-10-01
**Status:** built and verified on the `cidery_dev` database; waiting on the owner's look-and-feel review (desktop and 375px) before Phase 3.

## What exists

| Area | Files | Notes |
|---|---|---|
| Bootstrap and helpers | `app/bootstrap.php`, `db.php`, `http.php`, `csrf.php`, `auth.php`, `activity.php`, `mail.php`, `totp.php`, `units.php`, `navigation.php` | Fixed helper names from php-patterns (`db`, `view`, `e`, `is_htmx_request`, `require_post`, `request_integer`, `csrf_token`, `verify_csrf`) plus `render_screen()`, `log_activity()`, `log_screen_entered()`, `send_mail()` |
| Configuration | `config/application.php` + `config/local.php` | `config('key.path')`; secrets only in local.php |
| Routing | `html/.htaccess`, `html/_router.php` | Canonical URLs from the manifest map onto `html/{feature}/{index,form,view,verb}.php`; planned features without a controller render `html/stub.php` |
| Auth | `html/login.php`, `logout.php`, `auth/2fa.php`, `auth/reset.php`, `auth/reset-confirm.php`, `auth/invite.php`, `auth/google/{start,callback}.php` | Password + Google OIDC + TOTP, per php-session-auth: normalized emails, cost-12 bcrypt with a precomputed dummy hash, per-email and per-IP lockout (429), session regeneration and CSRF rotation on login, POST-only logout, no-store headers, pending-2FA state with a 10-minute expiry, ±1 timestep window with a replay guard, 10 hashed recovery codes |
| Shell | `app/views/layout.php` | nxl sidebar with every manifest feature grouped, header with dark mode and the user menu, `#page-content` swap target, footer, command bar, locally vendored HTMX 2.0.4, CSRF header listener, tooltip re-init after swaps, Ctrl/Cmd+K focus |
| Command bar | `app/views/assistant/bar.php`, `html/assistant/{message,transcript,undo}.php` | `#assistant-bar`, `#assistant-input`, `#assistant-send-btn`, `#assistant-reply`, offcanvas `#assistant-transcript`; screen context travels via `#screen-context` and `hx-vals`; the Phase 2 handler logs the utterance (`assistant_message` / `ama_question`) and replies with a placeholder |
| Screens | dashboard (`/`), AMA page (`/ama/`), activity list (`/activity/`), profile (`/settings/profile`), 2FA (`/settings/2fa`), stubs for every other manifest screen | Dashboard: four stat cards over the canonical table; activity list: server-rendered search and pagination over `app.activity_log` |
| Email | `app/views/emails/{password-reset,invite}.{html,txt}.php` | MaluMail when configured; error log otherwise |
| Operator script | `scripts/create-owner.php` | Creates the first owner as `invited` and prints the invite link |

Design-system compliance: shell and partials copied from the plugin examples; no modals; the only CSS added is in `assets/css/app-overrides.css` (command bar placement, mobile touch targets); no `hx-push-url="true"` anywhere; every meaningful element carries a scheme id.

## Verified

Automated, against Apache on this host (curl plus headless Chromium at 1366px and 375px):

- Anonymous requests redirect to `/login` with a safe `next`; `/logout` by GET is 405; a POST without the CSRF token is 403.
- Invite link sets the password and signs in; the dashboard renders with the owner's name; `screen_entered`, `login`, `invite_accepted`, `assistant_message` rows land in `app.activity_log`.
- Six wrong passwords: the sixth and later return 429; a correct login on another account still works.
- Sidebar navigation swaps `#page-content`, pushes the canonical URL, and stamps the screen context; direct loads of the same URL render the full shell.
- 2FA enrollment renders a server-side SVG QR and a 32-character manual key; cancel discards the pending secret.
- No horizontal scroll on any checked screen at 375px; the sidebar is hidden and opens from the hamburger; the command bar spans the viewport bottom; no console errors.

Not verified: Google sign-in end to end (no client id yet), real MaluMail delivery (no API key yet), the 2FA challenge with a live authenticator (the TOTP library's `now()` was checked, not a phone).

## Decisions made during the build

1. **Pretty URLs through one router.** `_router.php` applies the manifest's URL conventions to the php-patterns file layout, so controllers keep their simple names and no feature needs its own rewrite rules.
2. **First owner by script, users by invitation.** There is no self-registration; `create-owner.php` seeds the owner, and slice 1's users screen invites the rest. A Google sign-in with no matching account creates a `viewer` so an owner can promote it.
3. **Screen context is a hidden element**, `#screen-context`, emitted by `render_screen()` at the top of every partial; the command bar reads it with `hx-vals`.
4. **The dev environment** keeps `config/local.php` readable by `www-data` (mode 640, group www-data) and `storage/` group-writable.

## Open for the owner

- The look and feel: screenshots are in the session scratchpad; the live shell is at `http://127.0.0.1/` on this host (sign in with the owner account).
- Application name and client-facing domain (still "Cidery" and `http://127.0.0.1`).
- Google OAuth client id and secret, and the MaluMail API key and verified sender, when available.
