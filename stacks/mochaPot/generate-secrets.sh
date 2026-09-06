#!/usr/bin/env bash
#
# generate-secrets.sh — fills in every secret mochaPot's apps need, at
# runtime, on the node itself. Copied from stacks/silo/generate-secrets.sh
# 2026-09-02 when mochaPot's stack directory was first scaffolded (or
# re-scaffolded onto local generation, if this replaced an earlier
# SOPS+age-era copy — see the runbook's 2026-09-02 entry) — the mechanics
# below are identical to silo's own script and to every other node's copy
# of it; only the per-app secrets section differs per node. See
# stacks/silo/generate-secrets.sh for the fuller rationale comments
# (idempotency, why local generation instead of SOPS+age, etc.) — not
# re-explained here to avoid drifting out of sync across five copies of
# the same header.
#
# Wired 2026-09-03 for all 10 of mochaPot's apps (jellyfin, musicassistant,
# immich, vikunja, n8n, freshrss, mealie, actualbudget, stirlingpdf,
# roundcube) plus the deliberately-deferred traefik/. Most have no
# secrets of their own (first-run web UI setup, confirmed per-app) --
# see the "Per-app secrets go here" section below for exactly which do.
#
# Usage: run directly on mochaPot itself (never on roastery — per Section
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

log "vikunja/secrets.env.local"
set_if_absent "${DIR}/vikunja/secrets.env.local" "VIKUNJA_SERVICE_SECRET" "$(rand 32)"
# OIDC client secret -- generated on sieve (Authelia's own node), not
# here. Paste the value sieve's generate-secrets.sh prints in its "OIDC
# client secrets" summary table, then re-run this script -- see
# mochaPot/README.md.
set_if_absent "${DIR}/vikunja/secrets.env.local" "VIKUNJA_OIDC_CLIENT_SECRET" "REPLACE_ME_FROM_SIEVE_AUTHELIA"


log "n8n/secrets.env.local"
# Pinned, not left to auto-generate -- see n8n/docker-compose.yml's own
# comment: losing this key makes every stored credential unreadable.
set_if_absent "${DIR}/n8n/secrets.env.local" "N8N_ENCRYPTION_KEY" "$(rand 32)"

log "roundcube/secrets.env.local"
# Real external mail provider values -- can't be randomly generated,
# prompted instead. This fleet has no mail server of its own; Roundcube
# is purely a webmail client (confirmed 2026-09-03).
prompt_if_placeholder "${DIR}/roundcube/secrets.env.local" "ROUNDCUBE_IMAP_HOST" \
  "IMAP server (e.g. imap.gmail.com:993)" "REPLACE_ME_imap_host"
prompt_if_placeholder "${DIR}/roundcube/secrets.env.local" "ROUNDCUBE_SMTP_HOST" \
  "SMTP server (e.g. smtp.gmail.com:587)" "REPLACE_ME_smtp_host"

log "immich/secrets.env.local"
# OIDC client secret -- generated on sieve, same handoff as vikunja's
# above. Immich itself has no env var for this (its OIDC config is
# Admin-UI-only, Administration -> Settings -> OAuth) -- kept here purely
# so the real value is recorded somewhere locally for you to paste into
# that UI, not because any compose file reads it.
set_if_absent "${DIR}/immich/secrets.env.local" "IMMICH_OIDC_CLIENT_SECRET" "REPLACE_ME_FROM_SIEVE_AUTHELIA"
# Added 2026-09-05, moved here from percolator's old shared
# postgres/secrets.env.local -- Immich's whole db layer (its own
# dedicated postgres-immich + valkey, see immich/docker-compose.yml) now
# lives colocated with immich-server itself, on this node, not
# percolator. See the runbook's 2026-09-05 entry for why.
set_if_absent "${DIR}/immich/secrets.env.local" "IMMICH_DB_USERNAME" "immich"
set_if_absent "${DIR}/immich/secrets.env.local" "IMMICH_DB_PASSWORD" "$(rand 32)"
set_if_absent "${DIR}/immich/secrets.env.local" "IMMICH_DB_DATABASE_NAME" "immich"

log "mealie/secrets.env.local"
# OIDC client secret -- generated on sieve, same handoff pattern as
# vikunja's above.
set_if_absent "${DIR}/mealie/secrets.env.local" "MEALIE_OIDC_CLIENT_SECRET" "REPLACE_ME_FROM_SIEVE_AUTHELIA"

log "freshrss/secrets.env.local"
set_if_absent "${DIR}/freshrss/secrets.env.local" "FRESHRSS_OIDC_CLIENT_SECRET" "REPLACE_ME_FROM_SIEVE_AUTHELIA"
# Unlike the client secret, this one is FreshRSS's own local session
# crypto key -- never shared with Authelia, generatable right here.
set_if_absent "${DIR}/freshrss/secrets.env.local" "FRESHRSS_OIDC_CRYPTO_KEY" "$(rand 32)"

log "actualbudget/secrets.env.local"
set_if_absent "${DIR}/actualbudget/secrets.env.local" "ACTUALBUDGET_OIDC_CLIENT_SECRET" "REPLACE_ME_FROM_SIEVE_AUTHELIA"

log "komodo-periphery/secrets.env.local"
# Added 2026-09-04, alongside pre-emptively building mochaPot's Komodo
# Periphery agent (before it was ever brought up for the first time --
# see komodo-periphery/docker-compose.yml's own comment). Real external
# value from silo's Komodo UI, not generatable here -- same category as
# roundcube's mail-provider values just above.
prompt_if_placeholder "${DIR}/komodo-periphery/secrets.env.local" "PERIPHERY_ONBOARDING_KEY" \
  "Komodo onboarding key (from silo's Komodo UI -> Settings)" "REPLACE_ME_onboarding_key"

log "traefik/secrets.env.local"
# Added 2026-09-06 -- real HTTPS via Cloudflare DNS-01, same pattern and
# same required scope (Zone:DNS:Edit on ${DOMAIN}'s zone) as every other
# node's Traefik/Caddy instance (sieve, silo, cellar, percolator). Safe
# to reuse the exact same real token value across all of them if it
# already has that scope -- Cloudflare tokens aren't tied to one server,
# only to a zone and a permission set.
prompt_if_placeholder "${DIR}/traefik/secrets.env.local" "CF_DNS_API_TOKEN" \
  "Cloudflare API token (Zone:DNS:Edit on \${DOMAIN}'s zone)" "REPLACE_ME_cf_token"

# jellyfin/ moved to roastery 2026-09-05, no secrets.env.local here.
# musicassistant/ and stirlingpdf/ still have no secrets.env.local of
# their own -- no auth config exists at the compose level for either
# (confirmed per-app 2026-09-03; stirlingpdf's OIDC is excluded from this
# rollout entirely -- see authelia/config/configuration.yml.template's
# own comment, paid-tier gate). freshrss/, mealie/, actualbudget/ gained
# theirs 2026-09-06 for OIDC client secrets only, not for their original
# first-run-wizard/UI-set auth. immich/'s db credentials are generated
# above too, colocated on this node as of 2026-09-05.
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
