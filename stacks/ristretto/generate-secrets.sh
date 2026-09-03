#!/usr/bin/env bash
#
# generate-secrets.sh — fills in every secret ristretto's apps need, at
# runtime, on the node itself. Copied from stacks/silo/generate-secrets.sh
# 2026-09-02 when ristretto's stack directory was first scaffolded (or
# re-scaffolded onto local generation, if this replaced an earlier
# SOPS+age-era copy — see the runbook's 2026-09-02 entry) — the mechanics
# below are identical to silo's own script and to every other node's copy
# of it; only the per-app secrets section differs per node. See
# stacks/silo/generate-secrets.sh for the fuller rationale comments
# (idempotency, why local generation instead of SOPS+age, etc.) — not
# re-explained here to avoid drifting out of sync across five copies of
# the same header.
#
# THIS FILE HAS NO APPS YET. ristretto's own app list isn't built out — see
# stacks/ristretto/README.md and the initiation doc for what's actually
# planned. Add one set_if_absent (or prompt_if_placeholder) call per
# secret as each app gets built, same pattern as
# stacks/silo/generate-secrets.sh's own per-app section — copy the helper
# functions below as-is, they're generic.
#
# Usage: run directly on ristretto itself (never on roastery — per Section
# 19.6, "no live coding on fleet nodes" is about not editing code/configs
# on a running node; running an already-committed script to fill in local,
# gitignored runtime values isn't that, same as sieve's own script always
# has).
#   ./generate-secrets.sh
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

get_value() {
  # get_value <file> <KEY> — prints the current value, empty if absent.
  local file="$1" key="$2" line=""
  [[ -f "$file" ]] || return 0
  line="$(grep -E "^${key}=" "$file" 2>/dev/null || true)"
  [[ -z "$line" ]] && return 0
  printf '%s\n' "$line" | tail -n1 | cut -d= -f2-
}

prompt_if_placeholder() {
  # prompt_if_placeholder <file> <KEY> <prompt text> <placeholder> [--secret]
  # Prompts only when the key is missing or still equals <placeholder>. A
  # real value (generated, hand-edited, or previously typed in) is left
  # alone. Blank input keeps the placeholder rather than writing an empty
  # value, so a later re-run asks again instead of quietly staying blank.
  local file="$1" key="$2" prompt_text="$3" placeholder="$4" secret="${5:-}"
  ensure_file "$file"

  local current
  current="$(get_value "$file" "$key")"
  [[ -n "$current" && "$current" != "$placeholder" ]] && return 0

  if [[ ! -t 0 ]]; then
    [[ -z "$current" ]] && printf '%s=%s\n' "$key" "$placeholder" >> "$file"
    return 0
  fi

  local value
  if [[ "$secret" == "--secret" ]]; then
    read -r -s -p "$prompt_text: " value
    printf '\n'
  else
    read -r -p "$prompt_text: " value
  fi

  if [[ -z "$value" ]]; then
    value="$placeholder"
    echo "  (left blank — keeping the placeholder; re-run this script once you have it)"
  fi

  grep -qE "^${key}=" "$file" 2>/dev/null && sed -i "/^${key}=/d" "$file"
  printf '%s=%s\n' "$key" "$value" >> "$file"
}

# --- Per-app secrets go here ------------------------------------------
# One set_if_absent call per secret value, added as each app gets built —
# see stacks/silo/generate-secrets.sh's own per-app section for real
# worked examples (netalertx/speedtest-tracker/komodo). Nothing here yet:
# ristretto has no apps built out as of 2026-09-02.
#
#   set_if_absent "${DIR}/somesvc/secrets.env.local" "SOME_PASSWORD" "$(rand 16)"
#
# For a value that can't be randomly generated (an API token, etc.), use
# prompt_if_placeholder instead:
#
#   prompt_if_placeholder "${DIR}/somesvc/secrets.env.local" "SOME_API_TOKEN" \
#     "Some service API token" "REPLACE_ME_some_api_token" --secret
# ------------------------------------------------------------------------

chmod 600 "${DIR}"/*/secrets.env.local 2>/dev/null || true

log "Summary"
still_needed=()
for f in "${DIR}"/*/secrets.env.local; do
  [[ -f "$f" ]] || continue
  app="$(basename "$(dirname "$f")")"
  while IFS='=' read -r key value; do
    [[ "$value" == *REPLACE_ME* ]] && still_needed+=("${app}/secrets.env.local: ${key}")
  done < "$f"
done

if [[ ${#still_needed[@]} -eq 0 ]]; then
  echo "Done — nothing to generate yet (ristretto has no apps with secrets)."
else
  echo "Done, but these still need a real value — re-run this script anytime"
  echo "you have them (or edit the file directly):"
  for item in "${still_needed[@]}"; do
    echo "  - $item"
  done
fi
