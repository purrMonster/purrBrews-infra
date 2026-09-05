#!/usr/bin/env bash
#
# setup-secrets.sh — master first-time-setup script. Copied 2026-09-05
# from stacks/silo/setup-secrets.sh (identical logic — a generic
# .env.local + secrets.env.local bring-up flow, nothing silo-specific in
# the mechanics), with the header comment rewritten from scratch rather
# than left as a mechanical find-and-replace: silo's original comment
# told silo's own history (a real Homepage host-validation bug, a real
# SOPS+age-to-local-generation migration on 2026-09-02) — none of that
# ever happened on roastery, this is the first script of its kind here,
# so that history doesn't belong in this file even reworded.
#
# Does, in order:
#   1. Creates .env.local from local.env.example if it doesn't exist yet.
#   2. Prompts for any REPLACE_ME value still in .env.local — generic
#      scan, not a hardcoded list of variable names, so a future addition
#      to local.env.example (e.g. once Ollama is built here) gets picked
#      up automatically without touching this script.
#   3. Runs ./generate-secrets.sh — currently near-empty, since immich-ml
#      needs no secrets at all (see that script's own header comment).
#   4. Checks the results of step 3 for any lingering REPLACE_ME and warns
#      if found — relevant once a future app here needs a value that
#      can't be auto-generated (an API token, say).
#   5. Runs ./render-configs.sh so every template picks up whatever changed
#      in steps 1-4 — one command for first-time setup, not several you
#      have to remember to run in order.
#
# Idempotent throughout — safe to re-run any time. Only ever fills a
# REPLACE_ME that's still actually REPLACE_ME; a value you've already set,
# by hand or via a previous run, is never touched.
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

log ".env.local"

if [[ ! -f "${DIR}/.env.local" ]]; then
  [[ -f "${DIR}/local.env.example" ]] || fail "local.env.example not found in ${DIR} — can't create .env.local from it."
  cp "${DIR}/local.env.example" "${DIR}/.env.local"
  echo "  created .env.local from local.env.example"
fi
chmod 600 "${DIR}/.env.local"

# Generic REPLACE_ME scan — matches any KEY=value line where the value
# contains REPLACE_ME anywhere in it (covers both a bare placeholder like
# ROASTERY_TAILNET_IP=REPLACE_ME and an embedded one like
# DOMAIN=REPLACE_ME.example.com). Prompts once per matching key; a blank
# answer keeps the placeholder so a later re-run asks again instead of
# silently staying wrong, same rule as sieve's prompt_if_placeholder.
fill_replace_me() {
  local file="$1" tmpfile changed=0
  tmpfile="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*REPLACE_ME.*)$ ]]; then
      local key="${BASH_REMATCH[1]}" placeholder="${BASH_REMATCH[2]}"
      if [[ -t 0 ]]; then
        local value
        read -r -p "  ${key} (currently '${placeholder}'): " value
        if [[ -n "$value" ]]; then
          echo "${key}=${value}" >> "$tmpfile"
          changed=1
        else
          echo "  (left blank — keeping placeholder; re-run this script once you have it)"
          echo "$line" >> "$tmpfile"
        fi
      else
        # Not an interactive terminal (piped/unattended) — leave it, don't hang.
        echo "$line" >> "$tmpfile"
      fi
    else
      echo "$line" >> "$tmpfile"
    fi
  done < "$file"
  mv "$tmpfile" "$file"
  chmod 600 "$file"
  [[ "$changed" -eq 1 ]] && echo "  updated $(basename "$file")"
  return 0
}

fill_replace_me "${DIR}/.env.local"

still_replace_me="$(grep -l 'REPLACE_ME' "${DIR}/.env.local" 2>/dev/null || true)"
if [[ -n "$still_replace_me" ]]; then
  echo "  still has a REPLACE_ME value — re-run this script once you have it, or edit .env.local directly"
fi

log "Generating secrets (./generate-secrets.sh)"
"${DIR}/generate-secrets.sh"

log "Checking generated secrets for lingering REPLACE_ME values"
found_placeholder=0
shopt -s nullglob
for f in "${DIR}"/*/secrets.env.local; do
  if grep -q 'REPLACE_ME' "$f" 2>/dev/null; then
    found_placeholder=1
    app="$(basename "$(dirname "$f")")"
    echo "  WARNING: ${app}/secrets.env.local still has a REPLACE_ME value."
    echo "           Re-run ./generate-secrets.sh once you have it (it'll prompt again)."
  fi
done
shopt -u nullglob
[[ "$found_placeholder" -eq 0 ]] && echo "  none found"

log "Rendering configs (./render-configs.sh)"
"${DIR}/render-configs.sh"

log "Done."
