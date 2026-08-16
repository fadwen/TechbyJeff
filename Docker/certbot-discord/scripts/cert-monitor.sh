#!/bin/bash
# Certificate monitoring and renewal script
# This script checks certificate expiration and provides renewal options

CERT_PATH="/etc/letsencrypt/live/example.com/fullchain.pem"
DAYS_BEFORE_EXPIRY=30
LOG_FILE="/var/log/cert-monitor.log"

# Function to log messages
log_message() {
    echo "$(date): $1" >> "$LOG_FILE"
    echo "$1"
}

# Post to Discord if the notifier is installed. Silent no-op otherwise, so this
# script still works on a host without notifications configured.
#   discord_alert <colour> <title> <body>
discord_alert() {
    [ -x /usr/local/bin/discord-notify ] || return 0
    [ -r /etc/discord-webhook ] || return 0
    printf '%s\n' "$3" | /usr/local/bin/discord-notify \
        "$2 on $(hostname -s)" --color "$1" >/dev/null 2>&1
}

# Check if certificate exists
if [ ! -f "$CERT_PATH" ]; then
    log_message "ERROR: Certificate not found at $CERT_PATH"
    discord_alert red "Certificate MISSING" \
"Expected certificate not found:
  $CERT_PATH

The lineage may have been deleted or renamed. nginx will fail to start or
reload while this is true. Check:
  sudo certbot certificates"
    exit 1
fi

# Get certificate expiration date
EXPIRY_DATE=$(openssl x509 -enddate -noout -in "$CERT_PATH" | cut -d= -f2)
EXPIRY_TIMESTAMP=$(date -d "$EXPIRY_DATE" +%s)
CURRENT_TIMESTAMP=$(date +%s)
DAYS_UNTIL_EXPIRY=$(( ($EXPIRY_TIMESTAMP - $CURRENT_TIMESTAMP) / 86400 ))

log_message "Certificate expires in $DAYS_UNTIL_EXPIRY days ($EXPIRY_DATE)"

# Check if renewal is needed
if [ $DAYS_UNTIL_EXPIRY -le $DAYS_BEFORE_EXPIRY ]; then
    log_message "WARNING: Certificate needs renewal! ($DAYS_UNTIL_EXPIRY days remaining)"
    
    # Try automatic renewal first
    log_message "Attempting automatic renewal..."
    if certbot renew --quiet; then
        log_message "SUCCESS: Certificate renewed automatically"
        systemctl reload nginx
        exit 0
    else
        log_message "FAILED: Automatic renewal failed. Manual intervention required."
        
        # Create renewal instructions
        cat > /tmp/cert-renewal-instructions.txt << EOF
CERTIFICATE RENEWAL REQUIRED

Your SSL certificate expires in $DAYS_UNTIL_EXPIRY days.
Automatic renewal failed - manual action needed.

Renewal is automated via the Cloudflare DNS-01 challenge, so port 80 and
router/ISP forwarding are NOT involved. Check these in order:

1. Retry and read the error:
   sudo certbot renew --dry-run

2. Verify the Cloudflare API token is still valid and unexpired.
   Credentials: /root/.secrets/certbot/cloudflare.ini
   Token scope needed: Zone / DNS / Edit on the example.com zone.

3. Confirm the DNS plugin is still installed:
   certbot plugins | grep dns-cloudflare

4. Re-issue by hand if needed (wildcard covers every subdomain):
   sudo certbot certonly --dns-cloudflare \\
     --dns-cloudflare-credentials /root/.secrets/certbot/cloudflare.ini \\
     --cert-name example.com -d example.com -d '*.example.com' \\
     --email admin@example.com --agree-tos

nginx reloads automatically via the deploy hook; no manual reload needed.

This message was generated on $(date)
EOF
        
        log_message "Manual renewal instructions created at /tmp/cert-renewal-instructions.txt"
        cat /tmp/cert-renewal-instructions.txt

        # The certbot.service OnFailure handler does not cover this path: the
        # renewal here is run by cron, not by the systemd unit. Alert directly.
        discord_alert red "Certificate renewal FAILED" \
"$(cat /tmp/cert-renewal-instructions.txt)"
        exit 1
    fi
else
    log_message "Certificate is valid for $DAYS_UNTIL_EXPIRY more days"
fi