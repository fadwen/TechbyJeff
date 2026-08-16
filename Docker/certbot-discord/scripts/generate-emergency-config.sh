#!/bin/bash
# Regenerate the emergency (HTTP-only) nginx config from the live config.
#
# The emergency config is a snapshot: add, remove or renumber a service and it
# silently goes stale, which is worst possible timing since it is only ever
# used during an outage. This keeps it in sync.
#
# Run automatically by emergency-config-sync.path whenever the live config
# changes, and weekly by emergency-config-sync.timer as a backstop.
#
#   generate-emergency-config.sh            regenerate if needed
#   generate-emergency-config.sh --check    report drift, change nothing (exit 3 if stale)

set -uo pipefail

SRC=/etc/nginx/sites-available/arr-services.conf
OUT=/home/youruser/nginx/arr-services-emergency.conf
OWNER=youruser:youruser
LOG=/var/log/emergency-config-sync.log
HOST=$(hostname -s)
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG" 2>/dev/null
    echo "$1"
}

alert() {   # alert <color> <title> <body>
    [ -x /usr/local/bin/discord-notify ] || return 0
    [ -r /etc/discord-webhook ] || return 0
    printf '%s\n' "$3" | /usr/local/bin/discord-notify "$2 on ${HOST}" --color "$1" >/dev/null 2>&1 \
        || log "WARNING: Discord post failed"
}

[ -r "$SRC" ] || { log "ERROR: cannot read $SRC"; exit 2; }

# If the live config has no TLS at all, emergency mode is currently APPLIED.
# Regenerating from it would be regenerating from ourselves - harmless but
# pointless, and it would overwrite the good copy if the live one were ever
# truncated. Skip.
if ! grep -qE '^\s*ssl_certificate\s' "$SRC"; then
    log "Live config has no TLS - emergency mode appears to be active. Skipping."
    exit 0
fi

TMP=$(mktemp /tmp/emergency-config.XXXXXX) || exit 2
trap 'rm -f "$TMP"' EXIT

python3 - "$SRC" > "$TMP" <<'PYEOF'
import re, sys

src = open(sys.argv[1]).read()
seen = {}   # server_name -> upstream

for blk in re.findall(r'server\s*\{.*?\n\}', src, re.S):
    m = re.search(r'server_name\s+([^;]+);', blk)
    p = re.search(r'proxy_pass\s+(http://[\d.]+:\d+);', blk)
    if not m or not p:
        continue          # redirect-only vhosts have nothing to proxy to
    seen[m.group(1).strip()] = p.group(1)

print("""# EMERGENCY nginx config - HTTP only, no TLS.
#
# GENERATED FILE - do not edit by hand.
# Regenerated from arr-services.conf by generate-emergency-config.sh,
# triggered on change by emergency-config-sync.path.
#
# Applied by:  ~/scripts/nginx-config-manager.sh emergency
# Reverted by: ~/scripts/nginx-config-manager.sh normal
#
# Use when a TLS problem is blocking access: an expired certificate browsers
# refuse, or missing/corrupt cert files that make "nginx -t" fail so nginx
# will not reload or start. Contains no ssl_certificate directives, so it
# cannot fail for certificate reasons.
#
# Redirect-only vhosts are intentionally omitted - they have no upstream.""")

for name, upstream in seen.items():
    print(f"""
# {name}
server {{
    listen 80;
    server_name {name};

    location /.well-known/acme-challenge/ {{
        root /var/www/html;
    }}

    location / {{
        proxy_pass {upstream};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto http;
    }}
}}""")

print(f"\n# {len(seen)} vhosts", file=sys.stderr)
PYEOF

if [ $? -ne 0 ] || [ ! -s "$TMP" ]; then
    log "ERROR: generation failed or produced an empty file"
    alert red "Emergency config generation FAILED" \
"Could not regenerate the emergency nginx config from ${SRC}.
The existing ${OUT} is unchanged and may now be stale."
    exit 2
fi

# --- sanity checks before this is allowed to replace anything ---------------
BLOCKS=$(grep -c '^server {' "$TMP")
OPEN=$(tr -cd '{' < "$TMP" | wc -c)
CLOSE=$(tr -cd '}' < "$TMP" | wc -c)

if [ "$BLOCKS" -lt 1 ] || [ "$OPEN" -ne "$CLOSE" ] || grep -qE '^\s*(ssl_certificate|listen 443)' "$TMP"; then
    log "ERROR: generated config failed sanity checks (blocks=$BLOCKS braces=$OPEN/$CLOSE)"
    alert red "Emergency config generation FAILED" \
"Generated config failed validation and was discarded:
  server blocks : ${BLOCKS}
  braces        : ${OPEN} open / ${CLOSE} close
  TLS directives: $(grep -cE '^\s*(ssl_certificate|listen 443)' "$TMP")

${OUT} is unchanged."
    exit 2
fi

# --- compare ---------------------------------------------------------------
if [ -f "$OUT" ] && diff -q "$TMP" "$OUT" >/dev/null 2>&1; then
    log "Emergency config already up to date (${BLOCKS} vhosts)"
    exit 0
fi

DIFF=$(diff -u "${OUT:-/dev/null}" "$TMP" 2>/dev/null | head -40)

if [ "$CHECK_ONLY" -eq 1 ]; then
    log "DRIFT: emergency config is stale (${BLOCKS} vhosts in live config)"
    printf '%s\n' "$DIFF"
    exit 3
fi

mkdir -p "$(dirname "$OUT")"
install -m 0644 -o "${OWNER%%:*}" -g "${OWNER##*:}" "$TMP" "$OUT" || {
    log "ERROR: could not write $OUT"
    exit 2
}

log "Regenerated $OUT (${BLOCKS} vhosts)"
alert grey "Emergency nginx config updated" \
"The live nginx config changed, so the emergency (HTTP-only) fallback was
regenerated to match. ${BLOCKS} vhosts.

$(printf '%s' "$DIFF" | head -25)"

exit 0
