# ProcessCore

**A base manufacturing application for converting processes — steel processing the default profile.** Forked from
[maludb-os-cidery](https://github.com/maludb/maludb-os-cidery) on 2026-10-08 with its history; the plan for turning it into
the generic application is [docs/processcore-design.md](docs/processcore-design.md) (awaiting the owner's decisions). Until
that plan's first step lands, the code and everything below is the cidery's.

---

# Cidery

A memory-first, ask-me-anything inventory and production application for small cideries (beer and wine later), built on the htmx-php-builder plugin stack: PostgreSQL 17 + MaluDB, Apache, vanilla PHP 8.3, Bootstrap 5.3 (nxl theme), HTMX, and a set of Python services (MCP servers and a Claude-powered assistant).

## Beside the MaluDB Business OS (since 2026-10-04)

Cidery is one of the applications of the Business OS suite. On a server that runs the kernel it is installed by the
kernel's installer — `sudo php /var/www/bin/app_install.php apply https://github.com/maludb/maludb-os-cidery.git --by <super-admin> --domain <domain>` —
which reads `maludb-os.json`, puts the code at `/srv/apps/cidery`, provisions `<tenant>_cidery` with `deploy/os-provision.sh`,
writes `config/.env`, renders the vhost and units in `deploy/`, registers the application, mints its token and proves the
sign-on. People then open Cidery from the kernel's launcher (no password here), their roles come from the kernel's grants,
and the command bar runs Cidery's expert agent in the kernel. Everything below describes the **standalone** product, which
is unchanged and is what runs when `OS_ENABLED` is not set. The adoption record: `docs/os-adoption.md`.

## Layout

The repository root is the deployment root. Everything below assumes it is checked out at `/var/www`; the systemd units, Apache include and scripts use that path.

```
/var/www/
  app/            PHP application (outside the web root): bootstrap, helpers, features/*/queries.php, views/
  config/         application.php (defaults), manifest.json (generated), local.php + services.env (secrets, gitignored)
  db/             schema files, one per concern, applied in numeric order; db/host/ is the operator registry
  deploy/         provision-client.sh, activity ingestion script, systemd units, Apache include
  docs/           research, decisions, phase plans, MCP tool surface, action manifest, build specs
  html/           Apache DocumentRoot: page controllers per feature, assets/, .htaccess + _router.php
  scripts/        operator CLI scripts (create-owner.php, mint-action-token.php, planning-json.php, conformance.sh)
  services/       Python services: records_mcp, activity_mcp, actions_mcp, assistant, common; one venv in services/.venv
  storage/        uploads per client (storage/<subdomain>/...), owned by www-data, gitignored
  vendor/         composer packages, gitignored
```

## Requirements

Tested on Ubuntu 24.04 with the versions in the right column. Anything of the same major version should work.

| Component | Needed for | Tested with |
|---|---|---|
| PostgreSQL 17 with the `maludb_core` extension | one database per client, record + activity memory | 17.10, maludb_core 0.104.0 |
| PHP 8.3 (Apache module) with `pdo_pgsql`, `pgsql`, `sodium`, `curl`, `mbstring`, `gd`, `zip`, `xml`, `dom`, `simplexml`, `fileinfo` | the web application; gd/zip/xml are for phpspreadsheet (order imports) | 8.3.6 |
| Composer 2 | PHP dependencies | 2.10 |
| Apache 2.4 with `rewrite`, `headers`, `proxy`, `proxy_http` | serving `html/`, proxying the services | 2.4.58 |
| Python 3.12 with `venv` | the MCP servers and the assistant | 3.12.3 |
| An Anthropic API key | the assistant (command bar, Ask me anything) | optional at install time |
| MaluMail API key | outbound email (invites, password resets) | optional |
| Google OAuth client | Google sign-in | optional |

`maludb_core` must be installable in the cluster before provisioning (`SELECT * FROM pg_available_extensions WHERE name = 'maludb_core'`). It pulls in `vector`, `btree_gist`, `pg_trgm` and `pgcrypto`. The provisioning script runs `psql` as the `postgres` OS user through `sudo`, so the installing user needs that.

An operating-system user owns the checkout and runs the Python services and the ingestion timer. The shipped units name that user `maludb`; change `User=` in `deploy/*.service` and `deploy/systemd/*.service` if yours differs. Apache runs as `www-data` and only needs to read `config/local.php` and write under `storage/`.

## Secrets and generated files

These are gitignored and must be created on every host. Nothing in the repository contains credentials.

| File | Template | Owner and mode | Read by |
|---|---|---|---|
| `config/local.php` | `config/local.example.php` | `<owner>:www-data`, `0640` | PHP (web and the `scripts/*.php` CLIs) |
| `config/services.env` | `config/services.env.example` | `<owner>:<owner>`, `0600` | Python services, `deploy/activity-ingest.sh`, systemd `EnvironmentFile` |
| `vendor/` | `composer install` | | PHP |
| `services/.venv/` | `pip install -r services/requirements.txt` | | Python services |
| `storage/` | `mkdir` (see below) | `www-data:<owner>`, `2770` | PHP uploads |

`config/manifest.json` is generated but committed, because the actions MCP server needs it at start. Regenerate it after adding screens or actions (see "Keeping the manifest current").

Two values must match between the two secret files: `security.action_token_key` in `local.php` equals `CIDERY_ACTION_TOKEN_KEY` in `services.env`, and the database settings describe the same database.

## Installation

Steps 1 to 7 give a working web application. Steps 8 to 11 add the assistant and the MCP servers, which can be done later.

### 1. Check out and install PHP dependencies

```
sudo git clone https://github.com/maludb-ed/beverage-process.git /var/www
sudo chown -R $USER:$USER /var/www
cd /var/www && composer install --no-dev
```

### 2. Provision the client database

One PostgreSQL database per client (`cidery_<slug>`) plus the shared operator registry `cidery_host`. The script creates the cluster roles, the databases, installs `maludb_core`, enables the MaluDB memory schema, applies every `db/*.sql` file in order, applies the read-only grants and registers the client.

```
deploy/provision-client.sh dev "Dev Cidery" owner@example.com [subdomain]
```

The optional fourth argument is the client's subdomain and doubles as the folder name under `storage/`; it defaults to the slug. The script refuses to run against an existing database, so drop it first to re-provision.

Then set passwords on the three roles. The SQL files create the roles without passwords.

```
sudo -u postgres psql -c "ALTER ROLE cidery_app PASSWORD '...'" \
                      -c "ALTER ROLE cidery_records_ro PASSWORD '...'" \
                      -c "ALTER ROLE cidery_activity_ro PASSWORD '...'"
```

Local connections must be allowed with a password for these roles in `pg_hba.conf` (`scram-sha-256` on `127.0.0.1`).

### 3. Write config/local.php

```
cp config/local.example.php config/local.php
chown $USER:www-data config/local.php && chmod 0640 config/local.php
```

Fill in the database password, `app.base_url` (the public URL, no trailing slash) and the three security keys. Generate them with:

```
openssl rand -hex 32       # security.totp_key
openssl rand -hex 32       # security.action_token_key (copy into services.env too)
php -r "echo password_hash(bin2hex(random_bytes(16)), PASSWORD_BCRYPT, ['cost' => 12]), PHP_EOL;"   # security.dummy_password_hash
```

Every other key and its default is in `config/application.php`. Only override what differs. Never edit `local.php` with tools that recreate the file, such as `sed -i`, because that resets the owner and mode.

### 4. Create the uploads directory

Uploads (COA documents, approval attachments, order import files) are written to `storage/<subdomain>/...`. Create the root so Apache can write and the owning user can read:

```
sudo mkdir -p storage && sudo chown www-data:$USER storage && sudo chmod 2770 storage
```

The per-client subfolders are created by the application on first use.

### 5. Configure Apache

Enable the modules, point the default site at `html/`, allow `.htaccess` overrides (the pretty-URL router depends on them) and include the services proxy file. The include is harmless before the services exist.

```
sudo a2enmod rewrite headers proxy proxy_http
```

`/etc/apache2/sites-available/000-default.conf` (and the TLS vhost if you terminate TLS here) should contain:

```
DocumentRoot /var/www/html
<Directory /var/www/html>
    Options -Indexes +FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
Include /var/www/deploy/apache/cidery-services.conf
```

Then `sudo systemctl reload apache2`. The include proxies only `/mcp/records`, `/mcp/activity` and `/assistant/stream`; the actions server and the rest of the assistant stay on localhost.

### 6. Create the first owner

```
php scripts/create-owner.php owner@example.com "Owner Name"
```

Run it as the user who owns `config/local.php`. It creates the owner account and prints an invite link built from `app.base_url`. Open the link to set a password and enrol a TOTP second factor. Further users are invited from the Users screen.

### 7. Optional integrations

- **Google sign-in** activates when `google.client_id` and `google.client_secret` are set. Register `{base_url}/auth/google/callback` as the redirect URI in the Google Cloud console.
- **Email** goes through MaluMail when `malumail.api_key` is set. Without it, messages are written to the Apache error log and the activity log records them as `mode: dev_log`, which is enough for development: the invite and reset links appear in the log.

At this point the web application is complete. The command bar and Ask me anything will say the assistant is not configured until steps 8 to 11 are done.

### 8. Install the Python services

```
cd /var/www && python3 -m venv services/.venv
services/.venv/bin/pip install -r services/requirements.txt
```

`claude-agent-sdk` bundles the Claude Code CLI binary the assistant runs, so Node is not required.

### 9. Write config/services.env

```
cp config/services.env.example config/services.env && chmod 0600 config/services.env
```

Fill in the three role passwords from step 2, copy `security.action_token_key` from `local.php` into `CIDERY_ACTION_TOKEN_KEY`, set `CIDERY_APP_BASE_URL` to the same value as `app.base_url`, and set `ANTHROPIC_API_KEY`. Both an API key (`sk-ant-api...`) and a Claude Code OAuth token (`sk-ant-oat...`) are accepted. Without a key the services still start and the assistant answers that it is not configured.

### 10. Register the assistant's own MCP tokens

The assistant reads records and activity through the same bearer-token MCP endpoints external AI clients use. Tokens issued to people are created on the AI access tokens screen (`/settings/mcp-tokens`). The assistant's two tokens are named `assistant-service` and are registered once by hand, because the screen cannot create tokens it is not allowed to revoke.

Generate two tokens and put them in `services.env` as `CIDERY_SERVICE_RECORDS_TOKEN` and `CIDERY_SERVICE_ACTIVITY_TOKEN`:

```
openssl rand -hex 32
openssl rand -hex 32
```

Then store their hashes, with the owner created in step 6 as `created_by`:

```
sudo -u postgres psql -d cidery_dev <<'SQL'
SET ROLE cidery_app;
INSERT INTO app.mcp_access_tokens (name, scope, token_prefix, token_hash, created_by)
SELECT 'assistant-service', 'records',  left('<records token>', 8),  encode(sha256('<records token>'::bytea), 'hex'),  id FROM app.users WHERE role = 'owner' ORDER BY id LIMIT 1;
INSERT INTO app.mcp_access_tokens (name, scope, token_prefix, token_hash, created_by)
SELECT 'assistant-service', 'activity', left('<activity token>', 8), encode(sha256('<activity token>'::bytea), 'hex'), id FROM app.users WHERE role = 'owner' ORDER BY id LIMIT 1;
SQL
```

The screen lists them flagged as service tokens.

### 11. Install the systemd units

The units run as `maludb` from `/var/www/services` and load `config/services.env`. Edit `User=` first if your owner differs.

```
sudo cp deploy/systemd/*.service deploy/cidery-activity-ingest.service deploy/cidery-activity-ingest.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now cidery-records-mcp cidery-activity-mcp cidery-actions-mcp cidery-assistant cidery-activity-ingest.timer
```

| Unit | Listens on | Purpose |
|---|---|---|
| `cidery-records-mcp` | 127.0.0.1:8701 | read-only record memory; exposed by Apache at `/mcp/records` |
| `cidery-activity-mcp` | 127.0.0.1:8702 | read-only activity memory; exposed at `/mcp/activity` |
| `cidery-actions-mcp` | 127.0.0.1:8703 | navigation, voice actions and undo for the assistant; never exposed |
| `cidery-assistant` | 127.0.0.1:8765 | the Claude Agent SDK assistant; only `/assistant/stream` is exposed |
| `cidery-activity-ingest.timer` | | every minute, ships `app.activity_log` rows into the MaluDB memory schema of every active client |

Check with `systemctl status 'cidery-*'` and `journalctl -u cidery-assistant -f`. Smoke tests: `services/.venv/bin/python -m records_mcp.test_client --suite` and `-m activity_mcp.test_client --suite` call every tool with the service tokens; `-m assistant.run_eval` runs the assistant evaluation (it writes to the database and undoes afterwards).

## Keeping the manifest current

`config/manifest.json` describes every screen and action for the actions MCP server. Rebuild it after adding a screen, URL or action, with the web application and the database running:

```
cd /var/www/services && .venv/bin/python -m actions_mcp.build_manifest
```

It walks the screens as a user through an action token minted by `scripts/mint-action-token.php`, so it needs `config/local.php` readable and PHP on the path. Commit the result and restart `cidery-actions-mcp`.

## Upgrading an existing install

```
git pull
composer install --no-dev
services/.venv/bin/pip install -r services/requirements.txt
sudo systemctl restart cidery-records-mcp cidery-activity-mcp cidery-actions-mcp cidery-assistant
```

Schema changes arrive as new numbered files in `db/`. Apply any file newer than the client's `schema_version` in `cidery_host.clients` as `cidery_app`, then re-run `db/020_grants.sql` as superuser and update `schema_version`. Files already applied are never edited (see `db/README.md`).

## Development notes

- `scripts/conformance.sh <feature> ...` runs the mechanical per-slice checks from `docs/07-phase3-conventions.md` (lint, CSRF, POST guards, no modals).
- `scripts/mint-action-token.php <user_id>` mints an assistant action token for calling the actions MCP server by hand.
- `CIDERY_ASSISTANT_FAKE=1` in `config/services.env` makes the assistant service return deterministic results with no model call, so the command bar and PHP integration can be tested without a key.
- Session transcripts under `docs/claude-log/` are written by the preserve-the-evidence plugin and gitignored.

## Build order and design documents

Phase 0 plan: `docs/03-phase0-plan.md`. Phase 1 design: `db/`, `docs/04-mcp-tool-surface.md`, `docs/05-action-manifest.md`, `docs/build-specs/`. Phase 2 (auth + shell): `docs/06-phase2-shell.md`. Phase 3 conventions and progress: `docs/07-phase3-conventions.md`, `docs/08-phase3-progress.md`. Phase 4 services: `docs/09-phase4-conventions.md`, `docs/10-phase4-progress.md`. Customer orders: `docs/11` to `docs/13`.
