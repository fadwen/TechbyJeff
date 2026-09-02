# Caddy with the Cloudflare DNS plugin, needed for DNS-01 issuance.
# These hostnames have no public A records, so HTTP-01 cannot work.
#
# Companion to "Letting Caddy Own the Certificates I Used to Renew Myself"
# https://www.techbyjeff.net/letting-caddy-own-the-certificates/
#
# The official Caddy image ships with no DNS provider modules, so `acme_dns
# cloudflare` in a stock container is a startup error, not a feature to switch
# on. The -builder variant carries Go and xcaddy so the module can be compiled
# in here. Keep both stages pinned to the same version: a binary built against
# one Caddy running in an image built for another fails strangely.
FROM caddy:2.11.4-builder AS builder
RUN xcaddy build --with github.com/caddy-dns/cloudflare

FROM caddy:2.11.4
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
