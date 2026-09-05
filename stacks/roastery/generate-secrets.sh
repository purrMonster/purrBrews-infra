#!/usr/bin/env bash
#
# generate-secrets.sh — fills in every secret roastery's apps need, at
# runtime, on the node itself. Same pattern as every other node's
# generate-secrets.sh: random values generated locally, written straight
# into each app's secrets.env.local, never committed to git (covered by
# this stack's .gitignore).
#
# Currently a near-no-op: immich-ml needs no secrets at all. Confirmed
# 2026-09-05 against Immich's own remote-machine-learning docs — the ML
# container has no authentication, no login, no API key of its own
# ("no security measures whatsoever" is the docs' own wording); the
# mitigation is network-level (binding its port to ${ROASTERY_TAILNET_IP}
# only, see immich-ml/docker-compose.yml), not a secret this script could
# generate. Kept as a real file anyway, not deleted, for the same reason
# every node has one: so ./setup-secrets.sh's chained flow works
# identically everywhere, and so the next app added here (Ollama, per
# initiation.txt) has an established place to add its own secrets.
#
# Idempotent — a key that already holds a real (non-placeholder) value is
# never touched. Safe to re-run any time.
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

rand() { openssl rand -base64 "${1:-32}" | tr -d '\n'; }
log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }

ensure_file() {
  [[ -f "$1" ]] || { touch "$1"; }
  chmod 600 "$1"
}

set_if_absent() {
  # set_if_absent <file> <KEY> <value>
  local file="$1" key="$2" value="$3"
  ensure_file "$file"
  grep -qE "^${key}=" "$file" && return 0
  printf '%s=%s\n' "$key" "$value" >> "$file"
}

# immich-ml — no secrets needed (see header comment above). Nothing to
# call set_if_absent for.

# --- Future apps go here ------------------------------------------------
# One set_if_absent call per secret value, added as each new app gets
# built here — same pattern as every other node's generate-secrets.sh:
#
#   set_if_absent "${DIR}/somesvc/secrets.env.local" "SOME_PASSWORD" "$(rand 16)"
#
# For a value that can't be randomly generated (an API token, etc.), copy
# the prompt_if_placeholder helper from stacks/silo/generate-secrets.sh.
# --------------------------------------------------------------------------

chmod 600 "${DIR}"/*/secrets.env.local 2>/dev/null || true

log "Summary"
still_needed=()
shopt -s nullglob
for f in "${DIR}"/*/secrets.env.local; do
  [[ -f "$f" ]] || continue
  app="$(basename "$(dirname "$f")")"
  while IFS='=' read -r key value; do
    [[ "$value" == *REPLACE_ME* ]] && still_needed+=("${app}/secrets.env.local: ${key}")
  done < "$f"
done
shopt -u nullglob

if [[ ${#still_needed[@]} -eq 0 ]]; then
  echo "Done — no app-level secrets needed right now. Run ./render-configs.sh next."
else
  echo "Done, but these still need a real value — re-run this script anytime"
  echo "you have them (or edit the file directly):"
  for item in "${still_needed[@]}"; do
    echo "  - $item"
  done
fi
