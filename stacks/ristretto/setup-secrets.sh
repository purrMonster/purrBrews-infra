#!/usr/bin/env bash
#
# setup-secrets.sh — master first-time-setup script, added 2026-08-31 after
# Homepage failed its host-validation check for a bug that traced back to
# this exact gap: `.env.local` (SILO_LAN_IP/TZ/DOMAIN/SIEVE_LAN_IP) had no
# automated fill-in on ristretto the way sieve's generate-secrets.sh handles its
# own `.env.local`'s DOMAIN — ristretto's README just said "fill in by hand,"
# and it's an easy step to skip past without noticing, especially coming
# from sieve's more automated flow. This script closes that gap and chains
# the rest of first-time setup after it, so there's one command instead of
# a sequence to remember and get half-right.
#
# Does, in order:
#   1. Creates .env.local from local.env.example if it doesn't exist yet.
#   2. Prompts for any REPLACE_ME value still in .env.local — generic scan,
#      not a hardcoded list of variable names, so a future addition to
#      local.env.example gets picked up automatically without touching
#      this script (same "don't hardcode provisioning facts into a script"
#      reasoning as headscale-bootstrap.sh's CLI-args redesign, 2026-08-30
#      — extended 2026-08-31 to SIEVE_LAN_IP too: a cross-node fact like
#      that belongs confirmed at setup time, not silently trusted from
#      whatever local.env.example happened to say).
#   3. Runs ./decrypt-secrets.sh — the SOPS+age half, decrypting
#      secrets/ristretto/*.sops.yaml into each app's secrets.env.local.
#   4. Checks the results of step 3 for any lingering REPLACE_ME and warns
#      if found — but does NOT try to fix those itself. A secret's
#      REPLACE_ME comes from generate-secrets.ps1 on roastery leaving a
#      prompt blank there; secrets.env.local is regenerated from
#      secrets/ristretto/*.sops.yaml on every decrypt, so patching it locally
#      would just be silently undone by the next `git pull` +
#      decrypt-secrets.sh. The real fix has to happen at the source
#      (roastery, generate-secrets.ps1, then commit/push/pull again) — see
#      secrets/README.md.
#   5. Runs ./render-configs.sh so every template picks up whatever changed
#      in steps 1-4 — added so this is genuinely one command for first-time
#      setup, not three you still have to remember to run in order.
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
# SILO_LAN_IP=REPLACE_ME and an embedded one like
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

log "Decrypting secrets (./decrypt-secrets.sh)"
"${DIR}/decrypt-secrets.sh"

log "Checking decrypted secrets for lingering REPLACE_ME values"
found_placeholder=0
shopt -s nullglob
for f in "${DIR}"/*/secrets.env.local; do
  if grep -q 'REPLACE_ME' "$f" 2>/dev/null; then
    found_placeholder=1
    app="$(basename "$(dirname "$f")")"
    echo "  WARNING: ${app}/secrets.env.local still has a REPLACE_ME value."
    echo "           Fix it at the source, not here: on roastery, fill in the matching"
    echo "           Set-SopsSecretIfAbsent prompt in generate-secrets.ps1, commit, push —"
    echo "           then git pull and re-run this script. Editing the local file directly"
    echo "           gets silently overwritten on the next decrypt."
  fi
done
shopt -u nullglob
[[ "$found_placeholder" -eq 0 ]] && echo "  none found"

log "Rendering configs (./render-configs.sh)"
"${DIR}/render-configs.sh"

log "Done."
