#!/bin/bash
# Warn before the Cloudflare API token used by certbot expires.
#
# If that token expires or is revoked, DNS-01 validation stops working and
# certificate renewal fails silently until the cert itself expires. This gives
# advance warning instead.
#
# The expiry is read live from the Cloudflare API, so rotating the token
# updates this automatically - no need to edit a date in here. FALLBACK_EXPIRY
# is used only if the API cannot be reached or returns no expiry.
#
#   cloudflare-token-monitor.sh          normal check (quiet unless action needed)
#   cloudflare-token-monitor.sh --test   force an alert to prove the path works
#
# Exit: 0 = fine, 1 = token invalid/expired, 2 = could not check.

set -uo pipefail

CRED=/root/.secrets/certbot/cloudflare.ini
FALLBACK_EXPIRY="2029-01-01"     # known expiry of the current token
# 35, not 30: the check runs weekly, so a 30-day threshold could first fire
# with only 24 days left. 35 guarantees the first warning lands 29-35 days out,
# i.e. always at least a month of notice.
WARN_DAYS=35                     # start warning this many days out
CRITICAL_DAYS=7                  # escalate inside this window
LOG_FILE=/var/log/cloudflare-token-monitor.log
HOST=$(hostname -s)

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE" 2>/dev/null
    echo "$1"
}

alert() {   # alert <color> <title> <body>
    [ -x /usr/local/bin/discord-notify ] || { log "(discord-notify not installed)"; return 0; }
    [ -r /etc/discord-webhook ] || { log "(no webhook configured)"; return 0; }
    printf '%s\n' "$3" | /usr/local/bin/discord-notify "$2 on ${HOST}" --color "$1" >/dev/null 2>&1 \
        || log "WARNING: failed to post Discord alert"
}

days_until() {   # days_until <YYYY-MM-DD or ISO8601> -> integer days from now
    local target
    target=$(date -d "$1" +%s 2>/dev/null) || return 1
    echo $(( (target - $(date +%s)) / 86400 ))
}

# --- read the token ----------------------------------------------------------
if [ ! -r "$CRED" ]; then
    log "ERROR: cannot read $CRED (run as root?)"
    alert red "Cloudflare token check FAILED" \
"Cannot read ${CRED}

Certificate renewal depends on this credential. If the file is gone, renewal
is already broken. Check:
  sudo ls -l ${CRED}
  sudo certbot renew --dry-run"
    exit 2
fi

TOKEN=$(grep -oP 'dns_cloudflare_api_token\s*=\s*\K\S+' "$CRED" 2>/dev/null)
if [ -z "$TOKEN" ]; then
    log "ERROR: no dns_cloudflare_api_token found in $CRED"
    alert red "Cloudflare token check FAILED" \
"No dns_cloudflare_api_token entry in ${CRED}"
    exit 2
fi

# --- ask Cloudflare ----------------------------------------------------------
RESP=$(curl -sS -m 30 -H "Authorization: Bearer ${TOKEN}" \
    "https://api.cloudflare.com/client/v4/user/tokens/verify" 2>&1)
CURL_RC=$?

EXPIRES=""
STATUS=""
if [ $CURL_RC -eq 0 ]; then
    read -r STATUS EXPIRES < <(printf '%s' "$RESP" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("parse-error -"); raise SystemExit
if not d.get("success"):
    errs = "; ".join(e.get("message", "?") for e in d.get("errors", [])) or "unknown"
    print("invalid", "-")
    sys.stderr.write(errs + "\n")
    raise SystemExit
r = d.get("result") or {}
print(r.get("status", "unknown"), r.get("expires_on") or "-")
' 2>/dev/null)
fi

# --- token rejected outright -------------------------------------------------
if [ "$STATUS" = "invalid" ] || [ "$STATUS" = "expired" ]; then
    log "CRITICAL: Cloudflare rejected the token (status=$STATUS)"
    alert red "Cloudflare token INVALID" \
"Cloudflare rejected the API token used by certbot (status: ${STATUS}).

Certificate renewal is broken RIGHT NOW. Renewal will keep failing until a
new token is installed.

Fix:
  1. Cloudflare > My Profile > API Tokens > create a new 'Edit zone DNS'
     token scoped to the example.com zone.
  2. sudo nano ${CRED}      (replace dns_cloudflare_api_token)
  3. sudo certbot renew --dry-run"
    exit 1
fi

# --- work out the expiry -----------------------------------------------------
SOURCE="Cloudflare API"
if [ -z "$EXPIRES" ] || [ "$EXPIRES" = "-" ]; then
    EXPIRES="$FALLBACK_EXPIRY"
    SOURCE="fallback date in this script"
fi

DAYS=$(days_until "$EXPIRES")
if [ -z "$DAYS" ]; then
    log "ERROR: could not parse expiry '$EXPIRES'"
    exit 2
fi

if [ "${1:-}" = "--test" ]; then
    alert yellow "Cloudflare token check (TEST)" \
"This is a test of the token-expiry alert path.

token status : ${STATUS:-unknown}
expires      : ${EXPIRES} (${SOURCE})
days left    : ${DAYS}
warns at     : ${WARN_DAYS} days"
    log "Test alert sent (expires $EXPIRES, $DAYS days)"
    exit 0
fi

log "Cloudflare token expires $EXPIRES ($DAYS days, source: $SOURCE, status: ${STATUS:-unknown})"

# --- already expired ---------------------------------------------------------
if [ "$DAYS" -lt 0 ]; then
    alert red "Cloudflare token EXPIRED" \
"The Cloudflare API token expired on ${EXPIRES} (${DAYS#-} days ago).

Certificate renewal is broken. Create a replacement token and update:
  ${CRED}"
    exit 1
fi

# --- warning windows ---------------------------------------------------------
if [ "$DAYS" -le "$CRITICAL_DAYS" ]; then
    alert red "Cloudflare token expires in ${DAYS} days" \
"The Cloudflare API token certbot uses expires ${EXPIRES}.

When it expires, DNS-01 validation stops and the wildcard certificate for
example.com will fail to renew.

Replace it:
  1. Cloudflare > My Profile > API Tokens > 'Edit zone DNS' scoped to example.com
  2. sudo nano ${CRED}
  3. sudo certbot renew --dry-run"
elif [ "$DAYS" -le "$WARN_DAYS" ]; then
    alert yellow "Cloudflare token expires in ${DAYS} days" \
"The Cloudflare API token certbot uses expires ${EXPIRES}.

Plenty of time, but worth replacing before it lapses - renewal fails silently
once it does.

  1. Cloudflare > My Profile > API Tokens > 'Edit zone DNS' scoped to example.com
  2. sudo nano ${CRED}
  3. sudo certbot renew --dry-run"
fi

exit 0
