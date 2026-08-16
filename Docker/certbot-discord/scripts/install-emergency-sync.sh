#!/bin/bash
# Keep the emergency nginx config in sync with the live one, automatically.
#
# Installs:
#   - a .path unit that regenerates the moment arr-services.conf changes
#   - a weekly .timer as a backstop, in case the path unit is ever masked,
#     or the file is replaced by something that does not trip inotify
#
# Both report their own failures to Discord via discord-failure@.
#
# Usage: sudo ./install-emergency-sync.sh

set -uo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)/generate-emergency-config.sh"
BIN=/usr/local/bin/generate-emergency-config
WATCH=/etc/nginx/sites-available/arr-services.conf

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: run with sudo." >&2
    exit 1
fi
[[ -r "$SRC" ]] || { echo "ERROR: $SRC not found" >&2; exit 1; }

echo "==> Installing ${BIN}"
install -m 0755 "$SRC" "$BIN"

echo "==> Creating emergency-config-sync.service"
cat > /etc/systemd/system/emergency-config-sync.service <<'EOF'
[Unit]
Description=Regenerate the emergency nginx config from the live config
OnFailure=discord-failure@%N.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/generate-emergency-config
EOF

echo "==> Creating emergency-config-sync.path"
cat > /etc/systemd/system/emergency-config-sync.path <<EOF
[Unit]
Description=Watch the nginx config and resync the emergency fallback

[Path]
PathChanged=${WATCH}
# Also fire at boot if the file changed while the path unit was not running.
Unit=emergency-config-sync.service

[Install]
WantedBy=paths.target
EOF

echo "==> Creating emergency-config-sync.timer"
cat > /etc/systemd/system/emergency-config-sync.timer <<'EOF'
[Unit]
Description=Weekly backstop resync of the emergency nginx config

[Timer]
OnCalendar=Mon 07:30
Persistent=true
RandomizedDelaySec=10m
Unit=emergency-config-sync.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now emergency-config-sync.path
systemctl enable --now emergency-config-sync.timer

echo
echo "==> Running once now to confirm it is in sync"
systemctl start emergency-config-sync.service
sleep 1
journalctl -u emergency-config-sync.service -n 10 --no-pager -o cat

cat <<'EOF'

Installed.

  Watch status : systemctl status emergency-config-sync.path
  Next backstop: systemctl list-timers emergency-config-sync.timer
  Check drift  : sudo /usr/local/bin/generate-emergency-config --check
  Force resync : sudo systemctl start emergency-config-sync.service
  Log          : /var/log/emergency-config-sync.log

The emergency config is now a GENERATED file. Edit the live nginx config and
it follows automatically; hand edits to it will be overwritten.
EOF
