# certbot + Discord notifications

Unattended Let's Encrypt renewal via the Cloudflare DNS-01 challenge, with
Discord alerts on failure.

Built for a Ubuntu 24.04 host running nginx as a reverse proxy in front of
Docker services, where **inbound port 80 is blocked**, so HTTP-01 validation
cannot work. DNS-01 validates through the Cloudflare API and never touches
port 80.

## Why this exists

The setup it replaced used `certbot --manual --preferred-challenges dns`,
which requires pasting TXT records by hand. certbot refuses to run the manual
plugin non-interactively:

```
An authentication script must be provided with --manual-auth-hook
when using the manual plugin non-interactively.
```

So the daily `certbot.timer` failed every single run, silently, and the
certificate expired. Nothing reported it. This repo fixes both halves:
renewal that can actually run unattended, and alerting so a future failure is
visible.

## Contents

| File | Purpose |
|------|---------|
| `scripts/discord-notify` | Post to a Discord webhook. Bodies over 1900 chars become file attachments. |
| `scripts/install-discord-notify.sh` | Installs the notifier, the systemd `OnFailure` template unit, and wires certbot to it. |
| `scripts/setup-cloudflare-certbot.sh` | Installs the DNS plugin, stores the API token, issues a wildcard cert. |
| `scripts/cloudflare-token-monitor.sh` | Weekly check that warns before the Cloudflare API token expires or if it is revoked. |
| `scripts/install-cf-token-monitor.sh` | Installs the above as a systemd timer. |
| `scripts/cert-monitor.sh` | Weekly certificate expiry check with Discord alerting. |
| `scripts/generate-emergency-config.sh` | Regenerates the emergency HTTP-only nginx config from the live one. |
| `scripts/install-emergency-sync.sh` | Installs the above as a `.path` watch plus a weekly `.timer` backstop. |
| `scripts/nginx-config-manager.sh` | Applies and reverts the emergency config; also tests vhosts and drives renewal. |
| `hooks/certbot-pre-hook.sh` | Diagnostic only: verifies the ACME challenge path is served. Never modifies nginx. |
| `hooks/certbot-post-hook.sh` | Cleans up after the older, destructive version of the pre-hook. |

## Install order

```bash
# 1. Notifications first, so failures in later steps are visible.
sudo ./scripts/install-discord-notify.sh
#    Prompts for the webhook URL (Discord: Server Settings > Integrations >
#    Webhooks > New Webhook > Copy Webhook URL) and posts a test.

# 2. Certificate issuance + unattended renewal.
sudo ./scripts/setup-cloudflare-certbot.sh
#    Needs a Cloudflare API token: My Profile > API Tokens > Create Token >
#    "Edit zone DNS" template > Zone Resources: Include > Specific zone.
#    Use a scoped token, never the Global API Key.

# 3. Token expiry monitoring.
sudo ./scripts/install-cf-token-monitor.sh

# 4. Keep the emergency nginx fallback in sync with the live config.
sudo ./scripts/install-emergency-sync.sh

# 5. Verify. Do not skip this.
sudo certbot renew --dry-run
sudo systemctl start discord-failure@certbot.service   # posts a real alert
```

Step 5 matters more than it looks. The `discord-notify` attachment path was
broken on first install and the failure alert never arrived — but the short
setup test message passed, because it used a different code path. A
notification system is only proven by seeing an alert land.

## Values to change on a new host

**These scripts will not work as checked in.** The domain, contact address and
home directory are placeholders — `example.com`, `admin@example.com` and
`/home/youruser` — and every one of them has to be replaced before anything here
is deployed. None of them are secrets; they are simply not real.

| File | Line | Value |
|------|------|-------|
| `scripts/setup-cloudflare-certbot.sh` | 16-18 | `CERT_NAME`, `DOMAIN`, `EMAIL` |
| `scripts/cert-monitor.sh` | 5 | `CERT_PATH` lineage name |
| `scripts/cert-monitor.sh` | 74-83 | domain/email in the instructions text |
| `scripts/cloudflare-token-monitor.sh` | 20 | `FALLBACK_EXPIRY` — the current token's expiry date |
| `scripts/cloudflare-token-monitor.sh` | 103,152-165 | zone name in the alert text |
| `scripts/install-cf-token-monitor.sh` | 28 | `Documentation=` path |
| `scripts/setup-cloudflare-certbot.sh` | 107 | nginx config path in the printed next steps |
| `scripts/generate-emergency-config.sh` | 16-18 | `SRC`, `OUT`, `OWNER` — live config, generated fallback, owner |
| `scripts/install-emergency-sync.sh` | 17 | `WATCH` — must match `SRC` above |
| `scripts/nginx-config-manager.sh` | 5-7 | `EMERGENCY_CONFIG`, `NORMAL_CONFIG` — must match `OUT` above |

Find every one of them before deploying — the list above is a map, not a
substitute for the grep:

```bash
grep -rn 'example\.com\|admin@example\|/home/youruser' scripts/ hooks/
```

## Secrets — NOT in this repo

Created at install time, never committed:

| Path | Contents | Mode |
|------|----------|------|
| `/etc/discord-webhook` | Discord webhook URL | 0600 |
| `/root/.secrets/certbot/cloudflare.ini` | Cloudflare API token | 0600 |

Anyone with the webhook URL can post to your channel; anyone with the
Cloudflare token can edit DNS for the zone. If either leaks, rotate it at the
source — regenerate the webhook in Discord, delete the token in Cloudflare.

## What gets installed where

```
/usr/local/bin/discord-notify               notifier
/usr/local/bin/systemd-discord-failure      journal -> Discord helper
/usr/local/bin/cloudflare-token-monitor     token expiry check
/usr/local/bin/generate-emergency-config    emergency config generator
/etc/systemd/system/discord-failure@.service            template unit
/etc/systemd/system/certbot.service.d/discord-on-failure.conf
/etc/systemd/system/cloudflare-token-monitor.{service,timer}
/etc/systemd/system/emergency-config-sync.{service,path,timer}
/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh   reload + notify
/var/log/emergency-config-sync.log                      generator log
~/scripts/nginx-config-manager.sh       copied by hand - no installer
```

`OnFailure=discord-failure@%N.service` uses systemd's `%N` specifier (unit
name minus suffix), so the drop-in on `certbot.service` instantiates
`discord-failure@certbot.service`. Wire any other unit the same way:

```bash
sudo ./scripts/install-discord-notify.sh nginx docker
```

## The emergency nginx config

`arr-services-emergency.conf` is a TLS-free copy of the live vhosts, applied
when a certificate problem is blocking access — an expired cert browsers refuse,
or missing cert files that make `nginx -t` fail so nginx will not reload at all.
It contains no `ssl_certificate` directives, so it cannot fail for certificate
reasons.

`nginx-config-manager.sh` is what applies and reverts it. Unlike everything else
here it has no installer; copy it to `~/scripts/` and run it from there.

```bash
./nginx-config-manager.sh emergency     # back up the live config, swap in HTTP-only, reload
./nginx-config-manager.sh normal        # restore the backup, or fall back to the TLS config
./nginx-config-manager.sh test          # curl every vhost in the live config, resolved locally
./nginx-config-manager.sh cert-status   # run cert-monitor.sh
./nginx-config-manager.sh cert-renew    # certbot renew, then switch back to HTTPS on success
```

`emergency` refuses to proceed when the emergency config is missing, rather than
leaving the live config in place. That case used to pass silently: nothing was
swapped, `nginx -t` then validated the untouched live config, and the script
reported success — during an outage, the worst available outcome. If the
emergency config is installed but fails validation, the backup is restored and
nginx reloaded before it exits non-zero.

It was a hand-maintained snapshot, which is the wrong shape for a file only ever
read during an outage: add, remove or renumber a service and it goes stale
silently, and you find out at the worst possible moment.
`generate-emergency-config.sh` regenerates it from the live config instead.

```bash
sudo ./scripts/install-emergency-sync.sh

# Report drift without changing anything (exit 3 if stale)
sudo /usr/local/bin/generate-emergency-config --check

sudo systemctl start emergency-config-sync.service    # force a resync
systemctl status emergency-config-sync.path           # is the watch live
systemctl list-timers emergency-config-sync.timer     # next backstop run
```

Two triggers, on purpose. The `.path` unit catches an edit the moment it lands;
the weekly timer is the backstop for anything inotify does not see — the unit
masked, or the file replaced by a method that does not raise a change event.

Three refusals are worth knowing, because each one is the generator declining to
make an outage worse:

- **The live config has no TLS.** Emergency mode is already applied, so the live
  config *is* the emergency config. Regenerating would be a no-op at best, and
  would overwrite the good copy if the live one had been truncated. It skips.
- **Generation produced nothing usable.** An empty file, unbalanced braces, no
  server blocks, or any `ssl_certificate` / `listen 443` that leaked through.
  The candidate is discarded, `$OUT` is left alone, and a red alert goes out.
- **Redirect-only vhosts.** Omitted deliberately — they have no `proxy_pass`, so
  there is nothing to serve over HTTP.

The output is a **generated file**. Edit the live config and it follows; hand
edits to the emergency copy are overwritten on the next change.

## Notes and gotchas

**`curl -F` vs `--form-string`.** The attachment path must use
`--form-string` for `payload_json`. With `-F`, curl treats `;` in the value as
the start of a modifier (`;type=`) and truncates the JSON, and Discord
rejects it with `Expected "payload_json" to be a valid JSON string`. Journal
output routinely contains semicolons, so this fires in real use but not in a
short test message.

**Hooks only run from subdirectories.** certbot executes hooks in
`renewal-hooks/pre/`, `post/` and `deploy/`. Scripts left in the parent
`renewal-hooks/` directory are silently ignored.

**Do not reload nginx from a post-hook.** Post-hooks run on every attempt,
including failures. The deploy hook runs only when a certificate was actually
replaced, which is where a reload belongs.

**Wildcard certs require DNS-01.** HTTP-01 cannot issue `*.example.com`. The
upside is that new subdomains need no certificate work at all.

**`WARN_DAYS=35`, not 30,** in the token monitor. The check runs weekly, so a
30-day threshold could first fire with only 24 days remaining. 35 guarantees
the first warning lands 29-35 days out.
