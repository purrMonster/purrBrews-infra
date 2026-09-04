#!/usr/bin/env bash
#
# compose.sh — thin wrapper so every app dir's docker-compose.yml sees the
# shared .env.local (DOMAIN/PERCOLATOR_LAN_IP/TZ) plus its own
# secrets.env.local, without you needing to remember --env-file flags every
# time. Based on stacks/silo/compose.sh, with one real addition (2026-09-03):
# percolator is the first node where apps actually need to reach EACH OTHER
# by hostname across separate compose projects (Home Assistant/Nextcloud/
# Paperless-ngx each need their own Postgres instance and, for
# Nextcloud/Paperless, Valkey too — none of silo's apps needed this, they
# were either standalone or host-networked). ./compose.sh treats every app
# dir as its own docker compose project (--project-directory), which means
# its own default network by default — services in different projects can't
# see each other unless they share an explicit external network. This
# ensures that shared network exists before delegating, every single call,
# idempotently (docker network create fails harmlessly if it's already
# there) — so no separate manual "create the network first" step to
# forget. Every app compose file that needs to reach postgres/valkey (or be
# reached, like postgres/valkey themselves) joins percolator_net via
# `networks: { percolator_net: { external: true } }`.
#
# Usage: ./compose.sh <app> <docker compose args...>
#   ./compose.sh postgres up -d
#   ./compose.sh homeassistant logs -f
#   ./compose.sh nextcloud down
#
set -euo pipefail

[[ $# -ge 1 ]] || { echo "Usage: $0 <app> <docker compose args...>" >&2; exit 1; }

APP="$1"; shift
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${DIR}/${APP}"

[[ -d "$APP_DIR" ]] || { echo "No such app: $APP (looked in $APP_DIR)" >&2; exit 1; }
[[ -f "${APP_DIR}/docker-compose.yml" ]] || { echo "No docker-compose.yml in $APP_DIR" >&2; exit 1; }

docker network inspect percolator_net >/dev/null 2>&1 || docker network create percolator_net >/dev/null

ENV_ARGS=()
[[ -f "${DIR}/.env.local" ]] && ENV_ARGS+=(--env-file "${DIR}/.env.local")
[[ -f "${APP_DIR}/secrets.env.local" ]] && ENV_ARGS+=(--env-file "${APP_DIR}/secrets.env.local")

exec docker compose --project-directory "$APP_DIR" -f "${APP_DIR}/docker-compose.yml" "${ENV_ARGS[@]}" "$@"
