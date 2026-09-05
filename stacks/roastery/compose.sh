#!/usr/bin/env bash
#
# compose.sh — thin wrapper so every app dir's docker-compose.yml sees the
# shared .env.local (TZ/ROASTERY_TAILNET_IP) plus its own secrets.env.local,
# without you needing to remember --env-file flags every time. Same
# pattern as every other node's compose.sh — copied from stacks/silo's,
# with one deliberate omission: no shared docker network is created here.
#
# Every other node's compose.sh creates a node-wide bridge network
# (silo_net, percolator_net, etc.) so sibling apps can reach each other by
# container name without publishing ports to the LAN. roastery has no such
# need yet — immich-ml is the only app here, and it's reached from OUTSIDE
# roastery (by mochaPot, over the tailnet), never by another container on
# this same host. If Ollama or another roastery app is ever added that
# needs to talk to immich-ml locally, add a roastery_net network here
# then, the same way silo's was added — don't create one speculatively
# now for a need that doesn't exist yet.
#
# Usage: ./compose.sh <app> <docker compose args...>
#   ./compose.sh immich-ml   up -d
#   ./compose.sh immich-ml   logs -f
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
