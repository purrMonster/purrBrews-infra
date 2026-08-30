#!/usr/bin/env bash
#
# headscale-bootstrap.sh — idempotently ensures the given headscale users
# (namespaces, not login accounts — a grouping label devices belong to,
# mainly relevant once ACL policy gets written; headscale has none
# configured yet, no acl_policy_path in config.yaml.template) exist,
# creating whichever of them don't.
#
# Takes usernames as arguments deliberately, not a hardcoded list (fixed
# 2026-08-30 — see runbook.md) — a headscale user is a provisioning
# action, same category of thing as an lldap account, not a fixed
# structural fact about this stack the way the DNS subdomain list in
# pihole-dns-bootstrap.sh is. In particular: `barista` (the fleet's own
# server nodes — sieve, silo, cellar, percolator, mochaPot) is needed soon
# since those nodes are about to join the tailnet, but `penguin`/`bubbles`
# (personal devices) should only get created when those two are actually
# being onboarded — same standing call as their lldap accounts ("once
# everything's up and we're ready to use the system like production"),
# not just because this script happened to run.
#
# Usage:
#   ./headscale-bootstrap.sh [--dry-run] <user> [<user> ...]
#
# Examples:
#   ./headscale-bootstrap.sh --dry-run barista
#   ./headscale-bootstrap.sh barista
#   ./headscale-bootstrap.sh penguin bubbles   # whenever they're ready
#
# NOTE: unlike lldap-bootstrap.sh (GraphQL, reconstructed from memory) this
# talks to headscale's own `headscale` CLI inside the container, which is
# a much smaller surface — but the exact `users list --output json` shape
# is still partly reconstructed from headscale 0.27.x's documented
# behavior. Confirmed 2026-08-30 against a real instance: zero users
# prints the literal `null`, not `[]` (a Go nil-slice quirk) — handled
# below. If another command errors, read headscale's own error message
# first rather than assuming something structural is broken.
#
# Idempotent — safe to re-run; only creates users that don't already exist.
#
# --dry-run: lists current users for real (harmless) but doesn't create
# anything. Use this first, same as every other bootstrap script here.
#
set -euo pipefail

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
  shift
fi

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 [--dry-run] <user> [<user> ...]" >&2
  echo "Example: $0 barista" >&2
  echo "Example: $0 --dry-run penguin bubbles" >&2
  exit 1
fi

USERS=("$@")

command -v jq >/dev/null 2>&1 || {
  echo "jq not found — install it (apt-get install jq) and re-run." >&2
  exit 1
}

log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

DOCKER_CMD="docker"
docker info >/dev/null 2>&1 || DOCKER_CMD="sudo docker"

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "DRY RUN — reading current users for real, nothing will actually be created"
fi

log "Reading current headscale users"
LIST_JSON="$(${DOCKER_CMD} exec headscale headscale users list --output json)" \
  || fail "Couldn't list users from the headscale container — is it running? (./compose.sh headscale up -d)"

echo "$LIST_JSON" | jq -e '(. == null) or (type == "array")' >/dev/null 2>&1 \
  || fail "Expected a JSON array (or null for zero users) from 'headscale users list --output json' but got something else — real output was:
$LIST_JSON"

# headscale prints the literal `null`, not `[]`, when there are zero users
# (a Go nil-slice-marshals-to-null quirk) — confirmed 2026-08-30 on a genuinely
# fresh instance. `// []` treats null the same as an empty array.
EXISTING_NAMES="$(echo "$LIST_JSON" | jq -r '(. // [])[].name')"
echo "  Currently exist: $(echo "$EXISTING_NAMES" | grep -c . || true) user(s)"

declare -a MISSING=()
for u in "${USERS[@]}"; do
  if ! grep -qx "$u" <<< "$EXISTING_NAMES"; then
    MISSING+=("$u")
  fi
done

if [[ "${#MISSING[@]}" -eq 0 ]]; then
  log "All requested user(s) (${USERS[*]}) already exist — nothing to do."
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
