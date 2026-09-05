#!/usr/bin/env bash
#
# generate-secrets.sh — fills in every secret percolator's apps need, at
# runtime, on the node itself. Copied from stacks/silo/generate-secrets.sh
# 2026-09-02 when percolator's stack directory was first scaffolded (or
# re-scaffolded onto local generation, if this replaced an earlier
# SOPS+age-era copy — see the runbook's 2026-09-02 entry) — the mechanics
# below are identical to silo's own script and to every other node's copy
# of it; only the per-app secrets section differs per node. See
# stacks/silo/generate-secrets.sh for the fuller rationale comments
# (idempotency, why local generation instead of SOPS+age, etc.) — not
# re-explained here to avoid drifting out of sync across five copies of
# the same header.
#
# THIS FILE HAS NO APPS YET. percolator's own app list isn't built out — see
# stacks/percolator/README.md and the initiation doc for what's actually
# planned. Add one set_if_absent (or prompt_if_placeholder) call per
# secret as each app gets built, same pattern as
# stacks/silo/generate-secrets.sh's own per-app section — copy the helper
# functions below as-is, they're generic.
#
# Usage: run directly on percolator itself (never on roastery — per Section
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

# Restructured 2026-09-05 -- each app's db credentials now live in that
# app's OWN secrets.env.local, colocated with its own docker-compose.yml,
# not a single shared postgres/secrets.env.local anymore. See the
# runbook's 2026-09-05 entry: the old single-file-for-4-instances layout
# is what let postgres-immich and postgres-homeassistant collide on host
# port 5432 without anyone noticing -- splitting this up is part of the
# same fix. IMMICH_DB_* moved entirely to mochaPot's own
# generate-secrets.sh -- Immich's whole db layer (postgres + valkey) now
# lives there, colocated with immich-server itself.

log "homeassistant/secrets.env.local"
set_if_absent "${DIR}/homeassistant/secrets.env.local" "HA_DB_USERNAME" "homeassistant"
set_if_absent "${DIR}/homeassistant/secrets.env.local" "HA_DB_PASSWORD" "$(rand 32)"
set_if_absent "${DIR}/homeassistant/secrets.env.local" "HA_DB_DATABASE_NAME" "homeassistant"

# valkey/ has no secrets.env.local of its own -- no auth configured (see
# that compose file's own comment: same-host-only trust, never exposed
# past percolator_net). Nothing to generate there.

log "nextcloud/secrets.env.local"
set_if_absent "${DIR}/nextcloud/secrets.env.local" "NEXTCLOUD_ADMIN_PASSWORD" "$(rand 16)"
set_if_absent "${DIR}/nextcloud/secrets.env.local" "NEXTCLOUD_DB_USERNAME" "nextcloud"
set_if_absent "${DIR}/nextcloud/secrets.env.local" "NEXTCLOUD_DB_PASSWORD" "$(rand 32)"
set_if_absent "${DIR}/nextcloud/secrets.env.local" "NEXTCLOUD_DB_DATABASE_NAME" "nextcloud"

log "paperless/secrets.env.local"
set_if_absent "${DIR}/paperless/secrets.env.local" "PAPERLESS_ADMIN_PASSWORD" "$(rand 16)"
set_if_absent "${DIR}/paperless/secrets.env.local" "PAPERLESS_SECRET_KEY" "$(rand 32)"
set_if_absent "${DIR}/paperless/secrets.env.local" "PAPERLESS_DB_USERNAME" "paperless"
set_if_absent "${DIR}/paperless/secrets.env.local" "PAPERLESS_DB_PASSWORD" "$(rand 32)"
set_if_absent "${DIR}/paperless/secrets.env.local" "PAPERLESS_DB_DATABASE_NAME" "paperless"

log "traefik/secrets.env.local"
# Added 2026-09-04, alongside pre-emptively giving percolator's Traefik
# real TLS via Cloudflare DNS-01 (before it was ever brought up for the
# first time -- see traefik/config/traefik.yml.template's own comment
# for why the original plain-HTTP decision was wrong). Real external
# credential, can't be randomly generated -- same required scope
# (Zone:DNS:Edit on ${DOMAIN}'s zone) as sieve's/silo's/cellar's own
# Cloudflare tokens; safe to reuse the exact same real token value if it
# already has that scope, Cloudflare tokens aren't tied to one server.
prompt_if_placeholder "${DIR}/traefik/secrets.env.local" "CF_DNS_API_TOKEN" \
  "Cloudflare API token (Zone:DNS:Edit on \${DOMAIN}'s zone)" "REPLACE_ME_cf_token"

log "komodo-periphery/secrets.env.local"
# Added 2026-09-04, alongside pre-emptively building percolator's Komodo
# Periphery agent (before it was ever brought up for the first time --
# see komodo-periphery/docker-compose.yml's own comment). Real external
# value from silo's Komodo UI, not generatable here -- same category as
# traefik's CF_DNS_API_TOKEN just above.
prompt_if_placeholder "${DIR}/komodo-periphery/secrets.env.local" "PERIPHERY_ONBOARDING_KEY" \
  "Komodo onboarding key (from silo's Komodo UI -> Settings)" "REPLACE_ME_onboarding_key"

# homeassistant/'s HA_DB_* credentials are generated above now (for its
# colocated postgres-homeassistant) -- what's still NOT generated here is
# the recorder's configuration.yaml wiring itself, which stays a manual
# post-first-boot step (see homeassistant/docker-compose.yml's own
# comment: HA doesn't support this via compose/env at all). ForwardAuth's
# only per-node value is SIEVE_LAN_IP, which lives in .env.local (not a
# secret) since render-configs.sh needs it at template-render time, not
# generate-secrets.sh.
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
  echo "Done — nothing still needs a real value."
else
  echo "Done, but these still need a real value — re-run this script anytime"
  echo "you have them (or edit the file directly):"
  for item in "${still_needed[@]}"; do
    echo "  - $item"
  done
fi
