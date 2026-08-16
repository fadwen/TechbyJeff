#!/bin/bash
# Install Discord notifications on this host (pterodactyl).
#
# Adapted from the Proxmox setup. This box is a plain Ubuntu KVM guest, so the
# PVE-specific pieces do not apply and were dropped:
#   - setup_pve_discord.sh  needs pvesh / /etc/pve  (no Proxmox here)
#   - 20discord             needs smartd run.d      (VM, no physical disks)
# Both are kept for reference in ~/archive/pve-only/.
#
# What this installs instead:
#   /usr/local/bin/discord-notify           the notifier (unchanged, portable)
#   /usr/local/bin/systemd-discord-failure  journal -> Discord helper
#   discord-failure@.service                systemd template unit
#   certbot.service OnFailure drop-in       alerts on ANY failed renewal
#   certbot deploy hook                     alerts on successful renewal
#
# Usage:
#   sudo ./install-discord-notify.sh                 wire up certbot
#   sudo ./install-discord-notify.sh nginx docker    also wire other units

set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN=/usr/local/bin
CONF=/etc/discord-webhook
HOST=$(hostname -s)

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: run with sudo." >&2
    exit 1
fi

# --- 1. The notifier itself --------------------------------------------------
echo "==> Installing ${BIN}/discord-notify"
install -m 0755 "${SRC_DIR}/discord-notify" "${BIN}/discord-notify"

# --- 2. Webhook URL ----------------------------------------------------------
if [[ -r "$CONF" ]]; then
    echo "==> ${CONF} already exists, keeping it"
else
    echo "==> No webhook configured yet - starting setup"
    "${BIN}/discord-notify" --setup || {
        echo "ERROR: webhook setup failed. Re-run: sudo discord-notify --setup" >&2
        exit 1
    }
fi

# --- 3. journal -> Discord helper -------------------------------------------
echo "==> Installing ${BIN}/systemd-discord-failure"
cat > "${BIN}/systemd-discord-failure" <<'EOF'
#!/bin/bash
# Post the tail of a failed unit's journal to Discord.
# Invoked by discord-failure@<unit>.service via OnFailure=.
set -uo pipefail

UNIT="${1:?usage: systemd-discord-failure <unit>}"
HOST=$(hostname -s)

STATUS=$(systemctl is-failed "$UNIT" 2>/dev/null || true)
RESULT=$(systemctl show "$UNIT" -p Result --value 2>/dev/null || true)
EXITC=$(systemctl show "$UNIT" -p ExecMainStatus --value 2>/dev/null || true)

{
    echo "unit:   ${UNIT}"
    echo "state:  ${STATUS:-unknown} (result=${RESULT:-?} exit=${EXITC:-?})"
    echo
    echo "--- last 60 journal lines ---"
    journalctl -u "$UNIT" -n 60 --no-pager -o cat 2>/dev/null \
        || echo "(could not read journal)"
} | /usr/local/bin/discord-notify "FAILED: ${UNIT} on ${HOST}" --color red
EOF
chmod 0755 "${BIN}/systemd-discord-failure"

# --- 4. Template unit --------------------------------------------------------
echo "==> Installing discord-failure@.service"
cat > /etc/systemd/system/discord-failure@.service <<'EOF'
[Unit]
Description=Report %i failure to Discord

[Service]
Type=oneshot
ExecStart=/usr/local/bin/systemd-discord-failure %i
EOF

# --- 5. Wire units to it -----------------------------------------------------
# %N expands to the unit name without its suffix, so a drop-in on
# certbot.service yields discord-failure@certbot.service.
wire_unit() {
    local unit="$1"
    local base="${unit%.service}"
    if ! systemctl list-unit-files "${base}.service" >/dev/null 2>&1; then
        echo "    skip ${base}.service (not installed)"
        return
    fi
    mkdir -p "/etc/systemd/system/${base}.service.d"
    cat > "/etc/systemd/system/${base}.service.d/discord-on-failure.conf" <<'EOF'
[Unit]
OnFailure=discord-failure@%N.service
EOF
    echo "    wired ${base}.service"
}

echo "==> Wiring OnFailure handlers"
wire_unit certbot
for extra in "$@"; do wire_unit "$extra"; done

systemctl daemon-reload

# --- 6. Certbot success notification ----------------------------------------
# Deploy hooks run only when a certificate was actually replaced, so this is
# roughly 6 posts a year - a useful heartbeat that renewal still works.
DEPLOY_HOOK=/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
echo "==> Updating ${DEPLOY_HOOK}"
mkdir -p "$(dirname "$DEPLOY_HOOK")"
cat > "$DEPLOY_HOOK" <<'EOF'
#!/bin/bash
# Runs only when certbot actually installed a renewed certificate.
HOST=$(hostname -s)

if nginx -t 2>/dev/null && systemctl reload nginx; then
    MSG="nginx reloaded with the renewed certificate."
    COLOR=green
else
    MSG="CERT RENEWED BUT NGINX RELOAD FAILED - services may serve the old cert.
$(nginx -t 2>&1)"
    COLOR=red
fi

if [ -x /usr/local/bin/discord-notify ] && [ -r /etc/discord-webhook ]; then
    {
        echo "domains: ${RENEWED_DOMAINS:-unknown}"
        echo "path:    ${RENEWED_LINEAGE:-unknown}"
        echo
        echo "$MSG"
    } | /usr/local/bin/discord-notify "Certificate renewed on ${HOST}" --color "$COLOR"
fi
EOF
chmod 0755 "$DEPLOY_HOOK"

# --- 7. Prove it works -------------------------------------------------------
echo "==> Sending a test notification"
printf 'Discord notifications installed on %s.\n\nWired for failure alerts: %s\n' \
    "$HOST" "certbot${*:+ $*}" \
    | "${BIN}/discord-notify" "Notifications configured on ${HOST}" --color green \
    && echo "    test posted - check your Discord channel"

cat <<EOF

Done.

Verify the certbot alert path end to end (posts a real message):
  sudo systemctl start discord-failure@certbot.service

See what is wired:
  systemctl show certbot.service -p OnFailure --value
EOF
