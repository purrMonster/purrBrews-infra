# Caddy's own official image has no DNS-provider plugins built in (Cloudflare
# included) -- confirmed 2026-09-04 via Caddy's own docs and the Vaultwarden
# wiki's own "Caddy 2.x with Cloudflare DNS" page, which uses this exact
# xcaddy builder pattern. Built locally (docker compose `build:`, see
# ../caddy/docker-compose.yml) rather than pulling a random third-party
# prebuilt image with the plugin baked in -- several exist but weren't
# checked for maintenance/trustworthiness the way every other image in this
# fleet has been, and this is a 4-line build, not worth that tradeoff.
#
# Pinned tags for both stages -- not `:latest`/`:builder`, this fleet's
# usual discipline. Confirmed 2026-09-04 via Docker Hub directly: 2.11.4
# is current stable, and a matching 2.11.4-builder tag exists.
FROM caddy:2.11.4-builder AS builder

# github.com/caddy-dns/cloudflare -- the DNS-01 provider module for
# Cloudflare-managed zones, confirmed 2026-09-04 via the Vaultwarden wiki
# and the module's own repo. No version pin here -- xcaddy builds against
# whatever's current at build time; re-run `docker compose build --no-cache
# caddy` periodically rather than assuming this stays fresh forever.
RUN xcaddy build --with github.com/caddy-dns/cloudflare

FROM caddy:2.11.4

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
