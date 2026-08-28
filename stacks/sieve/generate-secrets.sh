#!/usr/bin/env bash
#
# generate-secrets.sh — fills in every secret this stack needs, at runtime,
# on the node itself. Deliberately NOT SOPS/age-encrypted-in-git: per
# decision 2026-08-28, secrets are generated locally instead and kept out
# of the repo entirely (covered by the repo's `*.env.local` .gitignore
# rule), rather than committed as ciphertext.
#
# Idempotent — only fills in a KEY= that doesn't already exist in its file.
# Re-running this after editing a value by hand leaves your edit alone.
#
# What this CAN'T generate — you have to supply these two by hand (see
# stacks/sieve/README.md):
#   - .env.local: DOMAIN (your real domain)
#   - traefik/secrets.env.local: CF_DNS_API_TOKEN (Cloudflare dashboard)
#   - cloudflared/secrets.env.local: TUNNEL_TOKEN (`cloudflared tunnel` CLI)
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
  # get_value <file> <KEY> — prints the current value, empty if absent
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 0
  grep -E "^${key}=" "$file" | tail -n1 | cut -d= -f2-
}

log ".env.local (shared)"
set_if_absent "${DIR}/.env.local" "DOMAIN" "REPLACE_ME.example.com"
set_if_absent "${DIR}/.env.local" "SIEVE_LAN_IP" "192.168.0.10"
set_if_absent "${DIR}/.env.local" "TZ" "Asia/Kolkata"

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
set_if_absent "${DIR}/authelia/secrets.env.local" "REDIS_PASSWORD" "$(rand 24)"

log "traefik/secrets.env.local"
set_if_absent "${DIR}/traefik/secrets.env.local" "CF_DNS_API_TOKEN" "REPLACE_ME_cloudflare_dns_edit_token"

log "cloudflared/secrets.env.local"
set_if_absent "${DIR}/cloudflared/secrets.env.local" "TUNNEL_TOKEN" "REPLACE_ME_cloudflared_tunnel_token"

chmod 600 "${DIR}/.env.local" "${DIR}"/*/secrets.env.local 2>/dev/null || true

cat <<'EOF'

Done. Everything with a REPLACE_ME value still needs your input by hand —
see stacks/sieve/README.md for exactly where each one comes from:
  - .env.local                     DOMAIN
  - traefik/secrets.env.local      CF_DNS_API_TOKEN
  - cloudflared/secrets.env.local  TUNNEL_TOKEN

Everything else above was randomly generated and needs no editing. Once
DOMAIN and the two Cloudflare values are filled in, run ./render-configs.sh
before bringing any app up.
EOF
