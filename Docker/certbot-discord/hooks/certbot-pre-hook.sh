#!/bin/bash
# Pre-hook for certbot renewal.
#
# This used to overwrite arr-services.conf with a hardcoded stub in order to
# "temporarily allow ACME challenges". That was both unnecessary and unsafe:
# the live config already serves /.well-known/acme-challenge/ from every TLS
# vhost, and the hardcoded hostname list went stale the moment services were
# added or renamed. If the post-hook ever failed, the stub became permanent.
#
# This version never modifies nginx. It only verifies that the challenge path
# is actually reachable, and reports what it finds. It always exits 0 so a
# diagnostic failure can never block a renewal.

set -uo pipefail

NGINX_CONF="/etc/nginx/sites-available/arr-services.conf"
WEBROOT="/var/www/html"
CHALLENGE_DIR="${WEBROOT}/.well-known/acme-challenge"

echo "[pre-hook] verifying ACME challenge path (config is NOT modified)"

if [[ ! -r "$NGINX_CONF" ]]; then
    echo "[pre-hook] WARNING: cannot read ${NGINX_CONF}"
    exit 0
fi

# Derive the port-80 vhost names from the live config rather than hardcoding.
mapfile -t VHOSTS < <(
    awk '
        /^[[:space:]]*server[[:space:]]*\{/ { inblk=1; blk=""; port80=0 }
        inblk { blk = blk $0 "\n" }
        inblk && /listen[[:space:]]+80[;[:space:]]/ { port80=1 }
        inblk && /^[[:space:]]*\}/ {
            if (port80 && match(blk, /server_name[[:space:]]+[^;]+;/)) {
                s = substr(blk, RSTART, RLENGTH)
                sub(/server_name[[:space:]]+/, "", s); sub(/;/, "", s)
                print s
            }
            inblk=0
        }
    ' "$NGINX_CONF" | tr ' ' '\n' | grep -v '^$' | sort -u
)

if [[ ${#VHOSTS[@]} -eq 0 ]]; then
    echo "[pre-hook] WARNING: no port-80 vhosts found in ${NGINX_CONF}"
    exit 0
fi

# Drop a canary and confirm nginx actually serves it back per vhost.
#
# Compare the response BODY, not just the status code. Vhosts that proxy
# everything to an app (cleanuparr, huntarr) happily answer 200 with their own
# HTML for an unknown path, so a status-only check reports a false OK.
mkdir -p "$CHALLENGE_DIR"
CANARY="pre-hook-canary-$$"
TOKEN="acme-canary-$$-$(date +%s)"
echo "$TOKEN" > "${CHALLENGE_DIR}/${CANARY}"
chmod 644 "${CHALLENGE_DIR}/${CANARY}"

FAILED=()
for host in "${VHOSTS[@]}"; do
    body=$(curl -s -m 10 \
        -H "Host: ${host}" \
        "http://127.0.0.1/.well-known/acme-challenge/${CANARY}" 2>/dev/null)
    if [[ "$body" == "$TOKEN" ]]; then
        echo "[pre-hook]   ${host}: OK"
    else
        echo "[pre-hook]   ${host}: challenge path not served from ${WEBROOT}"
        FAILED+=("$host")
    fi
done

rm -f "${CHALLENGE_DIR}/${CANARY}"

if [[ ${#FAILED[@]} -gt 0 ]]; then
    cat <<EOF
[pre-hook] NOTE: ${#FAILED[@]} vhost(s) cannot serve HTTP-01: ${FAILED[*]}
[pre-hook] Harmless if those hosts are HTTP-only, or if you are using the
[pre-hook] Cloudflare DNS-01 authenticator, which ignores port 80 entirely.
EOF
fi

exit 0
