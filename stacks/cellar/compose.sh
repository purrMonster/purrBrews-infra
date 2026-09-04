#!/usr/bin/env bash
#
# compose.sh — thin wrapper so every app dir's docker-compose.yml sees the
# shared .env.local (DOMAIN/SILO_LAN_IP/TZ) plus its own secrets.env.local,
# without you needing to remember --env-file flags every time. Identical to
# stacks/sieve/compose.sh — copied verbatim, nothing silo-specific in the
# logic itself.
#
# Usage: ./compose.sh <app> <docker compose args...>
#   ./compose.sh komodo   up -d
#   ./compose.sh unbound  logs -f
#   ./compose.sh crowdsec down
#
set -euo pipefail

[[ $# -ge 1 ]] || { echo "Usage: $0 <app> <docker compose args...>" >&2; exit 1; }

APP="$1"; shift
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${DIR}/${APP}"

[[ -d "$APP_DIR" ]] || { echo "No such app: $APP (looked in $APP_DIR)" >&2; exit 1; }
[[ -f "${APP_DIR}/docker-compose.yml" ]] || { echo "No docker-compose.yml in $APP_DIR" >&2; exit 1; }

# cellar_net -- added 2026-09-04, same idempotent-create pattern as
# percolator's percolator_net and silo's silo_net. Vaultwarden and Caddy
# join this so Caddy can reach Vaultwarden by container name with no
# host port published for Vaultwarden at all -- Caddy is the only path
# in, terminating real TLS via Let's Encrypt (Cloudflare DNS-01), which
# Bitwarden clients require regardless (WebCrypto needs a secure
# context). See caddy/ and vaultwarden/'s own docker-compose.yml files.
docker network inspect cellar_net >/dev/null 2>&1 || docker network create cellar_net >/dev/null

ENV_ARGS=()
[[ -f "${DIR}/.env.local" ]] && ENV_ARGS+=(--env-file "${DIR}/.env.local")
[[ -f "${APP_DIR}/secrets.env.local" ]] && ENV_ARGS+=(--env-file "${APP_DIR}/secrets.env.local")

exec docker compose --project-directory "$APP_DIR" -f "${APP_DIR}/docker-compose.yml" "${ENV_ARGS[@]}" "$@"
