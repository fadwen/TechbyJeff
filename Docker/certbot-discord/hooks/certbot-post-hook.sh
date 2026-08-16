#!/bin/bash
# Post-hook for certbot renewal.
#
# The pre-hook no longer swaps the nginx config out, so there is nothing to
# restore. This now only cleans up leftovers from the old destructive hook and
# leaves nginx in a known-good state.
#
# Note: reloading nginx after a successful renewal is handled by the deploy
# hook at /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh, which runs
# ONLY when a certificate was actually replaced. This post-hook runs on every
# attempt, so it deliberately does not reload.

set -uo pipefail

NGINX_CONF="/etc/nginx/sites-available/arr-services.conf"
STALE_BACKUP="${NGINX_CONF}.backup"

# The old pre-hook left this behind if it died between backup and restore.
# Its presence means the live config may still be the stale stub.
if [[ -f "$STALE_BACKUP" ]]; then
    echo "[post-hook] Found ${STALE_BACKUP} left by the old hook."
    if grep -q 'Temporary configuration for Let' "$NGINX_CONF" 2>/dev/null; then
        echo "[post-hook] Live config is the temporary stub - restoring backup."
        cp "$STALE_BACKUP" "$NGINX_CONF"
        nginx -t && systemctl reload nginx
    else
        echo "[post-hook] Live config looks intact; archiving the backup."
    fi
    mv "$STALE_BACKUP" "${STALE_BACKUP}.$(date +%Y%m%d%H%M%S)"
fi

# Sanity check: never leave nginx holding a config it cannot parse.
if ! nginx -t 2>/dev/null; then
    echo "[post-hook] ERROR: nginx config test FAILED. Not reloading." >&2
    nginx -t
    exit 1
fi

echo "[post-hook] nginx config OK"
exit 0
