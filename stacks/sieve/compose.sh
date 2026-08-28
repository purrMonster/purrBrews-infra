#!/usr/bin/env bash
#
# compose.sh — thin wrapper so every app dir's docker-compose.yml sees the
# shared .env.local (DOMAIN/SIEVE_LAN_IP/TZ) plus its own secrets.env.local,
# without you needing to remember --env-file flags every time.
#
# Usage: ./compose.sh <app> <docker compose args...>
#   ./compose.sh pihole   up -d
#   ./compose.sh authelia logs -f
#   ./compose.sh traefik  down
#
set -euo pipefail

[[ $# -ge 1 ]] || { echo "Usage: $0 <app> <docker compose args...>" >&2; exit 1; }

APP="$1"; shift
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${DIR}/${APP}"

[[ -d "$APP_DIR" ]] || { echo "No such app: $APP (looked in $APP_DIR)" >&2; exit 1; }
[[ -f "${APP_DIR}/docker-compose.yml" ]] || { echo "No docker-compose.yml in $APP_DIR" >&2; exit 1; }

ENV_ARGS=()
[[ -f "${DIR}/.env.local" ]] && ENV_ARGS+=(--env-file "${DIR}/.env.local")
[[ -f "${APP_DIR}/secrets.env.local" ]] && ENV_ARGS+=(--env-file "${APP_DIR}/secrets.env.local")

exec docker compose --project-directory "$APP_DIR" -f "${APP_DIR}/docker-compose.yml" "${ENV_ARGS[@]}" "$@"
