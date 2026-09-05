#!/usr/bin/env bash
#
# generate-secrets.sh — fills in every secret this stack needs, at runtime,
# on the node itself. Deliberately NOT SOPS/age-encrypted-in-git: per
# decision 2026-08-28, secrets are generated locally instead and kept out
# of the repo entirely (covered by the repo's `*.env.local` .gitignore
# rule), rather than committed as ciphertext.
#
# Idempotent — a key that already holds a real (non-placeholder) value,
# generated or hand-edited, is never touched. Re-running this later is safe.
#
# Three values can't be randomly generated — they only exist inside your
# Cloudflare account / are a domain you own:
#   - .env.local: DOMAIN
#   - traefik/secrets.env.local: CF_DNS_API_TOKEN
#   - cloudflared/secrets.env.local: TUNNEL_TOKEN
# For those, this script prompts you interactively (tokens use silent input
# — nothing echoed to the terminal or left in shell history). Leave a prompt
# blank to skip it for now; it keeps the REPLACE_ME placeholder, and a
# future re-run of this script will ask again rather than silently staying
# blank. If stdin isn't an actual terminal (piped input, run unattended),
# prompting is skipped entirely and placeholders are written instead, so
# this never hangs waiting for input that can't arrive.
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

log ".env.local (shared)"
set_if_absent "${DIR}/.env.local" "SIEVE_LAN_IP" "192.168.0.10"
set_if_absent "${DIR}/.env.local" "TZ" "Asia/Kolkata"
# Not a secret — just kept out of the .template files so the lldap group
# name Authelia checks isn't hardcoded. Rename here (and in lldap's admin
# UI, to match) if you ever want a different group name; nothing else needs
# to change.
set_if_absent "${DIR}/.env.local" "LLDAP_INFRA_ADMIN_GROUP" "purrbrews_infra_admins"
prompt_if_placeholder "${DIR}/.env.local" "DOMAIN" \
  "Domain (e.g. yourdomain.com)" "REPLACE_ME.example.com"

log "pihole/secrets.env.local"
set_if_absent "${DIR}/pihole/secrets.env.local" "PIHOLE_WEBPASSWORD" "$(rand 20)"

log "lldap/secrets.env.local"
set_if_absent "${DIR}/lldap/secrets.env.local" "LLDAP_ADMIN_PASSWORD" "$(rand 24)"
set_if_absent "${DIR}/lldap/secrets.env.local" "LLDAP_JWT_SECRET" "$(rand 32)"
set_if_absent "${DIR}/lldap/secrets.env.local" "LLDAP_KEY_SEED" "$(rand 32)"

log "authelia/secrets.env.local"
# Mirrors lldap's admin password so Authelia can bind as it — read back what
# was just written/already existed rather than generating a second,
# inconsistent one.
LLDAP_ADMIN_PW="$(get_value "${DIR}/lldap/secrets.env.local" "LLDAP_ADMIN_PASSWORD")"
set_if_absent "${DIR}/authelia/secrets.env.local" "AUTHELIA_LDAP_PASSWORD" "$LLDAP_ADMIN_PW"
set_if_absent "${DIR}/authelia/secrets.env.local" "AUTHELIA_SESSION_SECRET" "$(rand 32)"
set_if_absent "${DIR}/authelia/secrets.env.local" "AUTHELIA_STORAGE_ENCRYPTION_KEY" "$(rand 32)"
set_if_absent "${DIR}/authelia/secrets.env.local" "AUTHELIA_RESET_PASSWORD_JWT_SECRET" "$(rand 32)"
set_if_absent "${DIR}/authelia/secrets.env.local" "REDIS_PASSWORD" "$(rand 24)"

log "traefik/secrets.env.local"
prompt_if_placeholder "${DIR}/traefik/secrets.env.local" "CF_DNS_API_TOKEN" \
  "Cloudflare DNS API token (Edit zone DNS, scoped to your zone)" \
  "REPLACE_ME_cloudflare_dns_edit_token" --secret

log "cloudflared/secrets.env.local"
prompt_if_placeholder "${DIR}/cloudflared/secrets.env.local" "TUNNEL_TOKEN" \
  "Cloudflare Tunnel token (cloudflared tunnel token sieve)" \
  "REPLACE_ME_cloudflared_tunnel_token" --secret

log "komodo-periphery/secrets.env.local"
# Added 2026-09-04 -- yes, sieve too: silo's Komodo Core can manage
# sieve's own containers the same way it will percolator/cellar/
# mochaPot's, once this connects. Real external value from silo's Komodo
# UI, not generatable here -- same category as traefik's/cloudflared's
# own tokens just above.
prompt_if_placeholder "${DIR}/komodo-periphery/secrets.env.local" "PERIPHERY_ONBOARDING_KEY" \
  "Komodo onboarding key (from silo's Komodo UI -> Settings)" "REPLACE_ME_onboarding_key"

chmod 600 "${DIR}/.env.local" "${DIR}"/*/secrets.env.local 2>/dev/null || true

log "Summary"
still_needed=()
[[ "$(get_value "${DIR}/.env.local" "DOMAIN")" == "REPLACE_ME.example.com" ]] \
  && still_needed+=(".env.local: DOMAIN")
[[ "$(get_value "${DIR}/traefik/secrets.env.local" "CF_DNS_API_TOKEN")" == "REPLACE_ME_cloudflare_dns_edit_token" ]] \
  && still_needed+=("traefik/secrets.env.local: CF_DNS_API_TOKEN")
[[ "$(get_value "${DIR}/cloudflared/secrets.env.local" "TUNNEL_TOKEN")" == "REPLACE_ME_cloudflared_tunnel_token" ]] \
  && still_needed+=("cloudflared/secrets.env.local: TUNNEL_TOKEN")

if [[ ${#still_needed[@]} -eq 0 ]]; then
  echo "Done — every value is set. Run ./render-configs.sh next."
else
  echo "Done, but these still need a real value — re-run this script anytime"
  echo "you have them (or edit the file directly):"
  for item in "${still_needed[@]}"; do
    echo "  - $item"
  done
  echo
  echo "See stacks/sieve/README.md for where each one comes from. Once"
  echo "they're all set, run ./render-configs.sh before bringing any app up."
fi
