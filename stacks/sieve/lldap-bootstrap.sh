#!/usr/bin/env bash
#
# lldap-bootstrap.sh — idempotently ensures the LLDAP_INFRA_ADMIN_GROUP
# group exists in lldap and that `barista` is a member of it, via lldap's
# own REST auth + GraphQL API instead of clicking through the admin UI by
# hand. Closes the gap flagged 2026-08-30: Authelia's access_control reads
# the group name from .env.local, but nothing pushed that name into lldap
# itself — this does, and is safe to re-run any time (every step checks
# current state before acting).
#
# Run this on sieve itself, after `./compose.sh lldap up -d` and before
# bringing up (or restarting) Authelia — its access_control checks group
# membership on login, so the group needs to exist first. See README.md.
#
# NOTE: this is the first script in this stack that calls lldap's own API
# rather than just generating a config file for it — the field/mutation
# names below are lldap's documented GraphQL schema, reconstructed from
# memory and not yet exercised against a real instance. If a call below
# fails, the error printed is lldap's own GraphQL error (it usually names
# the exact field/type it didn't recognize) — read that first before
# assuming the script itself is broken, and let's fix it together off the
# real output rather than guessing further.
#
# --dry-run: runs every read (auth, listing groups, looking up barista) for
# real — those are harmless — but prints what it WOULD create/change
# instead of calling createGroup / addUserToGroup. Given the note above,
# use this for the actual first run on sieve before letting it write
# anything.
#
set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v jq >/dev/null 2>&1 || {
  echo "jq not found — install it (apt-get install jq) and re-run." >&2
  exit 1
}

set -a
[[ -f "${DIR}/.env.local" ]] && source "${DIR}/.env.local"
[[ -f "${DIR}/lldap/secrets.env.local" ]] && source "${DIR}/lldap/secrets.env.local"
set +a

: "${LLDAP_INFRA_ADMIN_GROUP:?LLDAP_INFRA_ADMIN_GROUP not set in .env.local — run ./generate-secrets.sh first}"
: "${LLDAP_ADMIN_PASSWORD:?LLDAP_ADMIN_PASSWORD not set in lldap/secrets.env.local — run ./generate-secrets.sh first}"

# Run locally on sieve, against lldap's published admin-UI port — the same
# one you've been reaching in a browser. LLDAP_LDAP_USER_DN isn't set in
# lldap/docker-compose.yml, so the admin login defaults to "admin".
LLDAP_URL="http://localhost:17170"
LLDAP_ADMIN_USER="admin"
TARGET_USER="barista"

log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "DRY RUN — reads happen for real, no group/membership will actually be created or changed"
fi

# graphql <query-string> — POSTs to /api/graphql with the bearer token,
# and fails loudly (printing lldap's own error) on a GraphQL-level error.
# GraphQL returns HTTP 200 even when a query/mutation errors, so checking
# the HTTP status alone wouldn't catch it — the response body's `errors`
# field is the real signal.
graphql() {
  local body response
  body="$(jq -n --arg q "$1" '{query: $q}')"
  response="$(curl -sS -X POST "${LLDAP_URL}/api/graphql" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$body")"
  if echo "$response" | jq -e '.errors' >/dev/null 2>&1; then
    echo "$response" | jq '.errors' >&2
    fail "GraphQL call failed — see lldap's error above."
  fi
  echo "$response"
}

log "Authenticating to lldap as ${LLDAP_ADMIN_USER}"
AUTH_RESPONSE="$(curl -sS -X POST "${LLDAP_URL}/auth/simple/login" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg u "$LLDAP_ADMIN_USER" --arg p "$LLDAP_ADMIN_PASSWORD" '{username: $u, password: $p}')")"
TOKEN="$(echo "$AUTH_RESPONSE" | jq -r '.token // empty')"
[[ -n "$TOKEN" ]] || fail "No token in lldap's auth response — got: $AUTH_RESPONSE"

log "Checking whether group '${LLDAP_INFRA_ADMIN_GROUP}' already exists"
GROUPS_JSON="$(graphql 'query { groups { id displayName } }')"
GROUP_ID="$(echo "$GROUPS_JSON" | jq -r --arg name "$LLDAP_INFRA_ADMIN_GROUP" '.data.groups[] | select(.displayName == $name) | .id')"

if [[ -z "$GROUP_ID" ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [dry-run] would create group '${LLDAP_INFRA_ADMIN_GROUP}'"
    echo "  [dry-run] can't check '${TARGET_USER}' membership against a group that doesn't exist yet — stopping here."
    log "Done (dry run)"
    exit 0
  fi
  log "Creating group '${LLDAP_INFRA_ADMIN_GROUP}'"
  CREATE_JSON="$(graphql "mutation { createGroup(name: \"${LLDAP_INFRA_ADMIN_GROUP}\") { id displayName } }")"
  GROUP_ID="$(echo "$CREATE_JSON" | jq -r '.data.createGroup.id')"
  [[ -n "$GROUP_ID" && "$GROUP_ID" != "null" ]] || fail "Group creation didn't return an id — got: $CREATE_JSON"
  echo "  Created, id=${GROUP_ID}"
else
  echo "  Already exists, id=${GROUP_ID}"
fi

log "Checking whether '${TARGET_USER}' exists and is already a member"
USER_RESPONSE="$(curl -sS -X POST "${LLDAP_URL}/api/graphql" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg q "query { user(userId: \"${TARGET_USER}\") { id groups { id displayName } } }" '{query: $q}')")"

if echo "$USER_RESPONSE" | jq -e '.errors' >/dev/null 2>&1; then
  echo "  '${TARGET_USER}' doesn't exist in lldap yet — lookup returned:"
  echo "$USER_RESPONSE" | jq '.errors' >&2
  echo "  Create the account by hand in the admin UI (http://<sieve-lan-ip>:17170)"
  echo "  first — barista gets its own password there, separate from its Linux"
  echo "  login (see runbook.md, 2026-08-30 identity model entry) — then re-run"
  echo "  this script; it'll pick up from here and just do the group membership."
else
  ALREADY_MEMBER="$(echo "$USER_RESPONSE" | jq -r --arg gid "$GROUP_ID" \
    '[.data.user.groups[]? | select((.id|tostring) == $gid)] | length')"
  if [[ "$ALREADY_MEMBER" -gt 0 ]]; then
    echo "  '${TARGET_USER}' is already a member — nothing to do."
  elif [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [dry-run] would add '${TARGET_USER}' to '${LLDAP_INFRA_ADMIN_GROUP}' (id=${GROUP_ID})"
  else
    log "Adding '${TARGET_USER}' to '${LLDAP_INFRA_ADMIN_GROUP}'"
    ADD_RESPONSE="$(curl -sS -X POST "${LLDAP_URL}/api/graphql" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg q "mutation { addUserToGroup(userId: \"${TARGET_USER}\", groupId: ${GROUP_ID}) { ok } }" '{query: $q}')")"
    if echo "$ADD_RESPONSE" | jq -e '.errors' >/dev/null 2>&1; then
      echo "$ADD_RESPONSE" | jq '.errors' >&2
      fail "Failed to add ${TARGET_USER} to the group — see lldap's error above."
    fi
    echo "  Added."
  fi
fi

log "Done"
