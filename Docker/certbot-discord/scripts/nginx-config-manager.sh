#!/bin/bash
# Certificate and nginx configuration management script

NGINX_AVAILABLE="/etc/nginx/sites-available"
EMERGENCY_CONFIG="/home/youruser/nginx/arr-services-emergency.conf"
NORMAL_CONFIG="/home/youruser/nginx/arr-services.conf"
BACKUP_CONFIG="$NGINX_AVAILABLE/arr-services.conf.backup"

case "$1" in
    emergency|http)
        echo "Switching to emergency HTTP-only configuration..."

        # Fail loudly. Previously a missing source file left the live config
        # untouched, then "nginx -t" passed against it and the script reported
        # success - the worst outcome during an actual outage.
        if [ ! -f "$EMERGENCY_CONFIG" ]; then
            echo "ERROR: emergency config not found at $EMERGENCY_CONFIG" >&2
            echo "Nothing was changed. Live config is untouched." >&2
            exit 1
        fi

        sudo cp "$NGINX_AVAILABLE/arr-services.conf" "$BACKUP_CONFIG"
        if ! sudo cp "$EMERGENCY_CONFIG" "$NGINX_AVAILABLE/arr-services.conf"; then
            echo "ERROR: failed to install emergency config." >&2
            exit 1
        fi

        if ! sudo nginx -t; then
            echo "ERROR: emergency config failed validation. Rolling back." >&2
            sudo cp "$BACKUP_CONFIG" "$NGINX_AVAILABLE/arr-services.conf"
            sudo nginx -t && sudo systemctl reload nginx
            exit 1
        fi
        sudo systemctl reload nginx

        echo "Emergency configuration applied. Services now accessible via HTTP:"
        grep -o 'server_name [^;]*;' "$EMERGENCY_CONFIG" \
            | sed 's/server_name //; s/;//' | sort -u | sed 's#^#  - http://#'
        ;;
    
    normal|https|ssl)
        echo "Switching to normal HTTPS configuration..."
        if [ -f "$BACKUP_CONFIG" ]; then
            sudo cp "$BACKUP_CONFIG" "$NGINX_AVAILABLE/arr-services.conf"
        elif [ -f "$NORMAL_CONFIG" ]; then
            sudo cp "$NORMAL_CONFIG" "$NGINX_AVAILABLE/arr-services.conf"
        else
            echo "ERROR: No backup or normal config found!"
            exit 1
        fi
        sudo nginx -t && sudo systemctl reload nginx
        echo "Normal HTTPS configuration applied. Services accessible via HTTPS."
        ;;
    
    test)
        echo "Testing access to all services..."
        # Derived from the live config so the list cannot go stale.
        hosts=$(grep -o 'server_name [^;]*;' "$NGINX_AVAILABLE/arr-services.conf" \
            | sed 's/server_name //; s/;//' | tr ' ' '\n' | grep -v '^$' | sort -u)
        for host in $hosts; do
            echo -n "Testing $host: "
            code=$(curl -s -o /dev/null -w "%{http_code}" -m 10 \
                --resolve "$host:80:127.0.0.1" --resolve "$host:443:127.0.0.1" \
                "http://$host" 2>/dev/null)
            case "$code" in
                200|301|302|307) echo "✓ OK ($code)" ;;
                *)               echo "✗ FAILED ($code)" ;;
            esac
        done
        ;;
    
    cert-status)
        echo "Checking certificate status..."
        sudo /home/youruser/scripts/cert-monitor.sh
        ;;
    
    cert-renew)
        echo "Attempting certificate renewal..."
        echo "1. Trying automatic renewal first..."
        if sudo certbot renew; then
            echo "✓ Success! Switching back to HTTPS configuration..."
            "$0" normal
        else
            echo "Automatic renewal failed."
            echo ""
            echo "Renewal uses the Cloudflare DNS-01 challenge - no TXT records"
            echo "by hand, and port 80 is not involved. Check:"
            echo "  1. certbot plugins | grep dns-cloudflare"
            echo "  2. Cloudflare API token valid? /root/.secrets/certbot/cloudflare.ini"
            echo "     (needs Zone / DNS / Edit on the example.com zone)"
            echo "  3. Re-issue by hand:"
            echo "     sudo certbot certonly --dns-cloudflare \\"
            echo "       --dns-cloudflare-credentials /root/.secrets/certbot/cloudflare.ini \\"
            echo "       --cert-name example.com -d example.com -d '*.example.com'"
            echo ""
            echo "If services are unreachable meanwhile: '$0 emergency'"
        fi
        ;;
    
    *)
        echo "Nginx Configuration Manager for *arr Services"
        echo ""
        echo "USAGE: $0 {emergency|normal|test|cert-status|cert-renew}"
        echo ""
        echo "Commands:"
        echo "  emergency    - Switch to HTTP-only mode (for expired SSL certs)"
        echo "  normal       - Switch to HTTPS mode (normal operation)"
        echo "  test         - Test access to all services"
        echo "  cert-status  - Check SSL certificate expiration"
        echo "  cert-renew   - Attempt certificate renewal"
        echo ""
        echo "Current status:"
        if sudo nginx -t 2>/dev/null; then
            echo "✓ Nginx configuration is valid"
        else
            echo "✗ Nginx configuration has errors"
        fi
        
        if sudo certbot certificates 2>/dev/null | grep -q "VALID"; then
            echo "✓ SSL certificates are valid"
        else
            echo "⚠ SSL certificates need attention"
        fi
        ;;
esac