#!/bin/bash
# Automate Let's Encrypt renewals via the Cloudflare DNS-01 challenge.
#
# Replaces the manual "create a TXT record by hand" flow. Because validation
# happens over the Cloudflare API instead of port 80, this also works around
# the inbound port 80 blocking that broke the webroot/HTTP-01 renewals.
#
# Issues a single wildcard cert for example.com + *.example.com, so adding a new
# service subdomain never requires touching the certificate again.
#
# Usage:  sudo ./setup-cloudflare-certbot.sh
#         sudo CF_TOKEN=xxxx ./setup-cloudflare-certbot.sh   # non-interactive

set -euo pipefail

CERT_NAME="example.com"
DOMAIN="example.com"
EMAIL="admin@example.com"
SECRET_DIR="/root/.secrets/certbot"
SECRET_FILE="${SECRET_DIR}/cloudflare.ini"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: run this with sudo." >&2
    exit 1
fi

# --- 1. Cloudflare API token -------------------------------------------------
# Create at: Cloudflare dashboard > My Profile > API Tokens > Create Token
#   Template:        "Edit zone DNS"
#   Permissions:     Zone / DNS / Edit
#   Zone Resources:  Include > Specific zone > example.com
# Use a scoped *token*, never the Global API Key.
if [[ -z "${CF_TOKEN:-}" ]]; then
    read -rsp "Cloudflare API token: " CF_TOKEN
    echo
fi
if [[ -z "$CF_TOKEN" ]]; then
    echo "ERROR: no token supplied." >&2
    exit 1
fi

# --- 2. Install the DNS plugin ----------------------------------------------
if ! certbot plugins 2>/dev/null | grep -q dns-cloudflare; then
    echo "==> Installing python3-certbot-dns-cloudflare"
    apt-get update -qq
    apt-get install -y python3-certbot-dns-cloudflare
else
    echo "==> dns-cloudflare plugin already present"
fi

# --- 3. Store the credential -------------------------------------------------
echo "==> Writing ${SECRET_FILE}"
mkdir -p "$SECRET_DIR"
chmod 700 "$SECRET_DIR"
umask 077
cat > "$SECRET_FILE" <<EOF
# Cloudflare API token for certbot DNS-01. Keep mode 0600.
dns_cloudflare_api_token = ${CF_TOKEN}
EOF
chmod 600 "$SECRET_FILE"

# --- 4. Reload nginx automatically after each renewal ------------------------
# Hooks only run from the pre/post/deploy SUBDIRECTORIES. Scripts sitting
# loose in /etc/letsencrypt/renewal-hooks/ are ignored by certbot.
DEPLOY_HOOK="/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh"
echo "==> Installing deploy hook ${DEPLOY_HOOK}"
mkdir -p "$(dirname "$DEPLOY_HOOK")"
cat > "$DEPLOY_HOOK" <<'EOF'
#!/bin/bash
# Reload nginx after certbot installs a renewed certificate.
nginx -t && systemctl reload nginx
EOF
chmod +x "$DEPLOY_HOOK"

# --- 5. Dry run, then issue --------------------------------------------------
# Cloudflare needs a moment to propagate the TXT record before LE validates.
CERTBOT_ARGS=(
    certonly
    --dns-cloudflare
    --dns-cloudflare-credentials "$SECRET_FILE"
    --dns-cloudflare-propagation-seconds 30
    --cert-name "$CERT_NAME"
    -d "$DOMAIN"
    -d "*.${DOMAIN}"
    --email "$EMAIL"
    --agree-tos
    --non-interactive
    --key-type ecdsa
)

echo "==> Dry run (no rate limit consumed)"
certbot "${CERTBOT_ARGS[@]}" --dry-run

echo "==> Dry run passed. Issuing the real certificate."
certbot "${CERTBOT_ARGS[@]}"

echo
echo "==> Certificate installed at /etc/letsencrypt/live/${CERT_NAME}/"
openssl x509 -in "/etc/letsencrypt/live/${CERT_NAME}/fullchain.pem" \
    -noout -enddate -ext subjectAltName

cat <<'EOF'

Next steps
----------
1. Point nginx at the new cert and re-enable HTTPS for seerr:
     sudo cp /home/youruser/nginx/arr-services-tls.conf /etc/nginx/sites-available/arr-services.conf
     sudo nginx -t && sudo systemctl reload nginx

2. Confirm unattended renewal now works end to end:
     sudo certbot renew --dry-run

3. Remove the two dead lineages that fail on every timer run:
     sudo certbot delete --cert-name overseerr.example.com
     sudo certbot delete --cert-name overseerr.example.com-0001
   Do this only AFTER step 1, since nginx currently references the old path.
EOF
