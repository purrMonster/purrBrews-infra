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

# silo_net -- added 2026-09-04, same idempotent-create pattern as
# percolator's compose.sh. Komodo (mongo/core/periphery), Scrutiny,
# Homepage, Speedtest-tracker, and Traefik all join this external network
# (each app's own docker-compose.yml overrides its project-local "default"
# network to point at it, rather than listing it per-service) so Traefik
# can reach them by container name with no host port published at all --
# closes the Docker-NAT-bypasses-ufw gap found 2026-09-04 (see silo's
# README Known gaps and the runbook's same-day entry). NetAlertX stays off
# it deliberately -- network_mode: host can't join a custom bridge network,
# same structural exception as sieve's Pi-hole/percolator's Home Assistant.
docker network inspect silo_net >/dev/null 2>&1 || docker network create silo_net >/dev/null

ENV_ARGS=()
[[ -f "${DIR}/.env.local" ]] && ENV_ARGS+=(--env-file "${DIR}/.env.local")
[[ -f "${APP_DIR}/secrets.env.local" ]] && ENV_ARGS+=(--env-file "${APP_DIR}/secrets.env.local")

exec docker compose --project-directory "$APP_DIR" -f "${APP_DIR}/docker-compose.yml" "${ENV_ARGS[@]}" "$@"
