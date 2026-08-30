#!/usr/bin/env bash
#
# headscale-bootstrap.sh — idempotently ensures the three headscale users
# (namespaces, not login accounts) this tailnet is organized around exist:
# `barista` (the fleet's own server nodes — sieve, silo, cellar,
# percolator, mochaPot) and `penguin` / `bubbles` (personal devices) —
# decided 2026-08-30, see runbook.md. Splitting server nodes from personal
# devices into different headscale users now is what makes it possible to
# write ACL policy later like "only barista's nodes can reach the DB
# ports" — headscale has no ACL policy configured yet
# (headscale/config/config.yaml.template has no acl_policy_path), so today
# this is purely organizational, but it's much easier to get the grouping
# right from the start than to re-home devices into different users later.
#
# NOTE: unlike lldap-bootstrap.sh (GraphQL, reconstructed from memory) this
# talks to headscale's own `headscale` CLI inside the container, which is
# a much smaller surface — but the exact `users list --output json` shape
# below is still reconstructed from what's documented for headscale
# 0.27.x, not exercised against this real instance yet. If a command below
# errors, read headscale's own error message first (it's usually direct —
# "command not found", wrong flag name, etc.) rather than assuming
# something structural is broken.
#
# Run this any time after `./compose.sh headscale up -d`. Idempotent —
# safe to re-run; only creates users that don't already exist.
#
# --dry-run: lists current users for real (harmless) but doesn't create
# anything. Use this first, same as every other bootstrap script here.
#
set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

command -v jq >/dev/null 2>&1 || {
  echo "jq not found — install it (apt-get install jq) and re-run." >&2
  exit 1
}

log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

DOCKER_CMD="docker"
docker info >/dev/null 2>&1 || DOCKER_CMD="sudo docker"

# Edit this list if the household's user model changes — see the note at
# the top of this file for the reasoning behind the current split.
USERS=(barista penguin bubbles)

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "DRY RUN — reading current users for real, nothing will actually be created"
fi

log "Reading current headscale users"
LIST_JSON="$(${DOCKER_CMD} exec headscale headscale users list --output json)" \
  || fail "Couldn't list users from the headscale container — is it running? (./compose.sh headscale up -d)"

echo "$LIST_JSON" | jq -e 'type == "array"' >/dev/null 2>&1 \
  || fail "Expected a JSON array from 'headscale users list --output json' but got something else — real output was:
$LIST_JSON"

EXISTING_NAMES="$(echo "$LIST_JSON" | jq -r '.[].name')"
echo "  Currently exist: $(echo "$EXISTING_NAMES" | grep -c . || true) user(s)"

declare -a MISSING=()
for u in "${USERS[@]}"; do
  if ! grep -qx "$u" <<< "$EXISTING_NAMES"; then
    MISSING+=("$u")
  fi
done

if [[ "${#MISSING[@]}" -eq 0 ]]; then
  log "All ${#USERS[@]} users (${USERS[*]}) already exist — nothing to do."
  exit 0
fi

log "Missing ${#MISSING[@]} user(s): ${MISSING[*]}"

if [[ "$DRY_RUN" -eq 1 ]]; then
  for u in "${MISSING[@]}"; do
    echo "  [dry-run] would create user '${u}'"
  done
  log "Done (dry run)"
  exit 0
fi

for u in "${MISSING[@]}"; do
  log "Creating user '${u}'"
  ${DOCKER_CMD} exec headscale headscale users create "$u" \
    || fail "Failed to create user '${u}' — see headscale's own error above."
done

log "Done — verify with: ${DOCKER_CMD} exec headscale headscale users list"
echo "Next: generate a pre-auth key for whichever user/device you're adding first:"
echo "  ${DOCKER_CMD} exec headscale headscale preauthkeys create --user <name> --expiration 1h"
