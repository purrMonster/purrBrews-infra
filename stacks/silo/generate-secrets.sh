#!/usr/bin/env bash
#
# generate-secrets.sh — fills in every secret silo's apps need, at runtime,
# on the node itself. Same pattern as stacks/sieve/generate-secrets.sh:
# random values generated locally, written straight into each app's
# secrets.env.local, never committed to git (covered by this stack's
# .gitignore).
#
# History: silo originally used a different mechanism — secrets generated
# and SOPS+age-encrypted on roastery (generate-secrets.ps1), committed as
# ciphertext, then decrypted on silo itself (decrypt-secrets.sh). Replaced
# with this file 2026-09-02, per decision to drop SOPS+age fleet-wide as
# unnecessary complexity for a home-lab this size — see that day's runbook
# entry for the full reasoning. Functionally this file now does the combined
# job of both old scripts: generate + land directly in secrets.env.local,
# no intermediate encrypted-in-git step, no key management at all. Every
# secret this produces is brand new — nothing here reads or migrates
# anything from the old SOPS-era files (secrets/silo/ never actually held
# committed ciphertext; the switch happened before any real secret was ever
# generated for silo).
#
# Idempotent — a key that already holds a real (non-placeholder) value,
# generated or hand-edited, is never touched. Re-running this later (e.g.
# once a new silo app needs a new secret) is always safe.
#
# None of silo's current apps need a value that can't be randomly generated
# (no external API token, no Cloudflare-style account credential), so
# nothing here prompts interactively today — but prompt_if_placeholder is
# kept below anyway, copied verbatim from sieve's own script, so the next
# app that does need one (an API key, etc.) can use it without inventing
# the pattern again. See sieve's generate-secrets.sh for the fuller comment
# on why prompts skip cleanly when stdin isn't a real terminal.
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
  # Written so a non-matching grep (the common case for a key that hasn't
  # been set yet) never propagates a nonzero exit through `set -eo
  # pipefail` — that would silently kill the whole script.
  local file="$1" key="$2" line=""
  [[ -f "$file" ]] || return 0
  line="$(grep -E "^${key}=" "$file" 2>/dev/null || true)"
  [[ -z "$line" ]] && return 0
  printf '%s\n' "$line" | tail -n1 | cut -d= -f2-
}

prompt_if_placeholder() {
  # prompt_if_placeholder <file> <KEY> <prompt text> <placeholder> [--secret]
  # Prompts only when the key is missing or still equals <placeholder>.
  # A real value (generated, hand-edited, or previously typed in) is left
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

log "netalertx/secrets.env.local"
# Added 2026-09-01, same bring-up that added the app itself. Randomly
# generated, not prompted: same category as sieve's own PIHOLE_WEBPASSWORD
# (a login credential this project sets, not one that has to match an
# external account). NetAlertX does not require login by default
# (docs.netalertx.com/SECURITY/) and has real CVE history for
# unauthenticated RCE/auth-bypass (CVE-2024-46506, CVE-2025-32440) — the
# pinned image tag postdates both fixes, but running it open on the LAN
# regardless wasn't worth it. 16 bytes, not the usual 32 — this one's a
# password a human might actually type into a login form sometimes,
# mirroring PIHOLE_WEBPASSWORD's own shorter length for the same reason.
set_if_absent "${DIR}/netalertx/secrets.env.local" "NETALERTX_PASSWORD" "$(rand 16)"

log "speedtest-tracker/secrets.env.local"
# Added 2026-09-01. APP_KEY is a Laravel encryption key, REQUIRED (the app
# doesn't run correctly without one, no insecure default to worry about
# here) — "base64:" prefix is the exact format Laravel expects, confirmed
# via the project's own docs before assuming a plain random value would
# work as-is. ADMIN_PASSWORD replaces the LinuxServer image's fixed default
# account (admin@example.com / password) — same "don't ship a known
# default credential" reasoning as netalertx above.
set_if_absent "${DIR}/speedtest-tracker/secrets.env.local" "SPEEDTEST_TRACKER_APP_KEY" "base64:$(rand 32)"
set_if_absent "${DIR}/speedtest-tracker/secrets.env.local" "SPEEDTEST_TRACKER_ADMIN_PASSWORD" "$(rand 16)"

log "komodo/secrets.env.local"
# Added 2026-09-01. Five secrets, more than any other silo app so far,
# proportional to what Komodo actually holds: root-equivalent access (via
# Periphery's docker.sock mount) to every node it manages, not just silo.
# The official reference file ships every one of these as an insecure
# placeholder (admin/admin, a_random_secret, a_random_jwt_secret,
# changeme) — none of those are used here. Database credentials are
# treated as real secrets (not just a fixed non-secret username) given
# what's actually at stake if this specific app's data is compromised.
set_if_absent "${DIR}/komodo/secrets.env.local" "KOMODO_DATABASE_USERNAME" "komodo"
set_if_absent "${DIR}/komodo/secrets.env.local" "KOMODO_DATABASE_PASSWORD" "$(rand 32)"
set_if_absent "${DIR}/komodo/secrets.env.local" "KOMODO_JWT_SECRET" "$(rand 32)"
set_if_absent "${DIR}/komodo/secrets.env.local" "KOMODO_WEBHOOK_SECRET" "$(rand 32)"
set_if_absent "${DIR}/komodo/secrets.env.local" "KOMODO_INIT_ADMIN_PASSWORD" "$(rand 16)"

# scrutiny, diun — no secrets needed. scrutiny has no auth at all to
# protect (see stacks/silo/README.md's Known gaps); diun has no web UI or
# API surface whatsoever, so there's nothing to log into either — see the
# runbook's 2026-09-01 entry for both.

# --- Future apps go here ------------------------------------------------
# One set_if_absent call per secret value, added as each new app gets
# built — same pattern as the three apps above, or as sieve's own
# generate-secrets.sh for the shared-value and prompted-value cases:
#
#   set_if_absent "${DIR}/somesvc/secrets.env.local" "SOME_PASSWORD" "$(rand 16)"
#
# For a value that can't be randomly generated (an API token, etc.), use
# prompt_if_placeholder instead:
#
#   prompt_if_placeholder "${DIR}/somesvc/secrets.env.local" "SOME_API_TOKEN" \
#     "Some service API token" "REPLACE_ME_some_api_token" --secret
# --------------------------------------------------------------------------

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
  echo "Done — every value is set. Run ./render-configs.sh next."
else
  echo "Done, but these still need a real value — re-run this script anytime"
  echo "you have them (or edit the file directly):"
  for item in "${still_needed[@]}"; do
    echo "  - $item"
  done
  echo
  echo "See stacks/silo/README.md for where each one comes from. Once"
  echo "they're all set, run ./render-configs.sh before bringing any app up."
fi
