#!/bin/bash
# Install the weekly Cloudflare API token expiry check.
#
# Uses a systemd timer rather than cron so the check itself gets an OnFailure
# Discord alert - if the monitor breaks, you hear about that too, instead of
# it quietly stopping and the expiry warning never arriving.
#
# Usage: sudo ./install-cf-token-monitor.sh

set -uo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)/cloudflare-token-monitor.sh"
BIN=/usr/local/bin/cloudflare-token-monitor

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: run with sudo." >&2
    exit 1
fi
[[ -r "$SRC" ]] || { echo "ERROR: $SRC not found" >&2; exit 1; }

echo "==> Installing ${BIN}"
install -m 0755 "$SRC" "$BIN"

echo "==> Creating cloudflare-token-monitor.service"
cat > /etc/systemd/system/cloudflare-token-monitor.service <<'EOF'
[Unit]
Description=Check Cloudflare API token expiry
Documentation=file:/home/youruser/scripts/cloudflare-token-monitor.sh
# If the check itself fails, report that to Discord too.
OnFailure=discord-failure@%N.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/cloudflare-token-monitor
EOF

echo "==> Creating cloudflare-token-monitor.timer"
cat > /etc/systemd/system/cloudflare-token-monitor.timer <<'EOF'
[Unit]
Description=Weekly Cloudflare API token expiry check

[Timer]
OnCalendar=Mon 08:00
# Run on next boot if the machine was off when it was due - a missed check
# on a long-horizon reminder is exactly how these get silently lost.
Persistent=true
RandomizedDelaySec=15m

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now cloudflare-token-monitor.timer

echo
echo "==> Running the check once now"
systemctl start cloudflare-token-monitor.service
sleep 2
journalctl -u cloudflare-token-monitor.service -n 15 --no-pager -o cat

cat <<'EOF'

Installed.

  Next run:   systemctl list-timers cloudflare-token-monitor.timer
  Run now:    sudo systemctl start cloudflare-token-monitor.service
  Test alert: sudo /usr/local/bin/cloudflare-token-monitor --test
  Log:        /var/log/cloudflare-token-monitor.log
EOF
