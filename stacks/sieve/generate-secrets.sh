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

log "authelia/secrets.env.local -- OIDC clients"
# Added 2026-09-06. Each app below gets ONE randomly generated plaintext
# secret (stored here, in authelia/secrets.env.local, alongside its own
# PBKDF2 hash) -- the hash is what configuration.yml.template actually
# uses (identity_providers.oidc.clients[].client_secret); the PLAINTEXT
# is what the app itself needs, on whatever node it actually lives on.
# Since Authelia and almost none of these apps share a node, this script
# can't put the plaintext directly into the app's own secrets.env.local
# the way every other secret in this repo works -- there's no SSH access
# between nodes, by design (see runbook.md's operating model). Instead,
# the Summary section at the bottom of this script prints a copy-paste
# table; run this script, then go copy each value into the named
# app/secrets.env.local on its own node, then run that node's own
# generate-secrets.sh again so it picks up the real value in place of its
# REPLACE_ME_FROM_SIEVE_AUTHELIA placeholder.
#
# Hashing needs `docker run authelia/authelia:4.39.20` -- fine here since
# that image is already pulled for the authelia container itself on this
# same node. If docker isn't reachable when this runs, the plaintext is
# still generated and saved; the hash step is skipped with a warning and
# the exact manual command to run once docker is available.
hash_oidc_secret() {
  # hash_oidc_secret <plaintext> -- prints the $pbkdf2-sha512$... digest,
  # or nothing if the hash couldn't be produced.
  docker run --rm authelia/authelia:4.39.20 \
    authelia crypto hash generate pbkdf2 --password "$1" 2>/dev/null \
    | grep -oE '\$pbkdf2-sha512\$[^[:space:]]+' | head -n1
}

set_oidc_client() {
  # set_oidc_client <APP_VAR_PREFIX>
  # Generates <PREFIX>_OIDC_CLIENT_SECRET (plaintext, if absent) and
  # <PREFIX>_OIDC_CLIENT_SECRET_HASH (if absent) in
  # authelia/secrets.env.local. Idempotent, same as every set_if_absent
  # call elsewhere in this script -- a real value already present is
  # never touched or re-hashed.
  local prefix="$1" file="${DIR}/authelia/secrets.env.local"
  local plain_key="${prefix}_OIDC_CLIENT_SECRET"
  local hash_key="${prefix}_OIDC_CLIENT_SECRET_HASH"

  local plain
  plain="$(get_value "$file" "$plain_key")"
  if [[ -z "$plain" ]]; then
    plain="$(rand 32)"
    set_if_absent "$file" "$plain_key" "$plain"
  fi

  local hash
  hash="$(get_value "$file" "$hash_key")"
  if [[ -z "$hash" ]]; then
    if command -v docker >/dev/null 2>&1; then
      hash="$(hash_oidc_secret "$plain")"
    fi
    if [[ -n "$hash" ]]; then
      # Single-quoted, written directly (not via set_if_absent, which
      # doesn't quote) -- this value contains literal $ characters that
      # bash `source` (render-configs.sh reads this file that way) would
      # otherwise try to expand as variable references, silently
      # corrupting the hash into garbage that looks like it worked.
      printf "%s='%s'\n" "$hash_key" "$hash" >> "$file"
    else
      echo "  ! could not hash ${plain_key} -- is docker reachable from this shell?" >&2
      echo "    Run manually once it is:" >&2
      echo "      docker run --rm authelia/authelia:4.39.20 authelia crypto hash generate pbkdf2 --password '$plain'" >&2
      echo "    then add the result as ${hash_key}='<digest>' (single-quoted) to authelia/secrets.env.local" >&2
    fi
  fi
}

# JWKS signing key -- reads the RAW PEM you generated by hand (README.md's
# one-time openssl step) from /srv/data/authelia/oidc/private.pem and
# stores an ESCAPED, single-line copy in authelia/secrets.env.local.
# CORRECTED 2026-09-06: the first version of this pipeline tried to mount
# the raw PEM file straight into the container via a `key_path` config
# field -- that field doesn't exist in Authelia's schema, confirmed by a
# real crash on first bring-up. Authelia wants the key CONTENT under a
# `key` field, and a real multi-line PEM breaks a YAML block scalar once
# envsubst substitutes it in (envsubst doesn't know about YAML
# indentation) -- so this stores the PEM as one line with literal
# backslash-n in place of real newlines, which a double-quoted YAML
# string correctly un-escapes back to real newlines at parse time. See
# configuration.yml.template's own comment on the jwks block.
JWK_PEM_PATH="/srv/data/authelia/oidc/private.pem"
if [[ -z "$(get_value "${DIR}/authelia/secrets.env.local" "AUTHELIA_OIDC_JWK_PRIVATE_KEY")" ]]; then
  if [[ -f "$JWK_PEM_PATH" ]]; then
    JWK_ESCAPED="$(sed ':a;N;$!ba;s/\n/\\n/g' "$JWK_PEM_PATH")"
    printf "AUTHELIA_OIDC_JWK_PRIVATE_KEY='%s'\n" "$JWK_ESCAPED" >> "${DIR}/authelia/secrets.env.local"
  else
    echo "  ! ${JWK_PEM_PATH} not found -- generate it first (README.md's" >&2
    echo "    'Authelia as an OpenID Connect Provider' section, step 1)," >&2
    echo "    then re-run this script." >&2
  fi
fi

set_if_absent "${DIR}/authelia/secrets.env.local" "AUTHELIA_OIDC_HMAC_SECRET" "$(rand 48)"
set_oidc_client "VIKUNJA"
set_oidc_client "MEALIE"
set_oidc_client "IMMICH"
set_oidc_client "FRESHRSS"
set_oidc_client "ACTUALBUDGET"
set_oidc_client "NEXTCLOUD"
set_oidc_client "PAPERLESS"
set_oidc_client "HOMEASSISTANT"
set_oidc_client "VAULTWARDEN"
set_oidc_client "KOMODO"
set_oidc_client "HEADSCALE"
set_oidc_client "JELLYFIN"

log "headscale/secrets.env.local"
# Headscale is the one OIDC client that lives on THIS node, same as
# Authelia -- so unlike every other app above, its plaintext secret can
# go straight into its own secrets.env.local here, no manual copy-paste
# needed. Read back what set_oidc_client just generated/found above.
HEADSCALE_OIDC_PLAIN="$(get_value "${DIR}/authelia/secrets.env.local" "HEADSCALE_OIDC_CLIENT_SECRET")"
set_if_absent "${DIR}/headscale/secrets.env.local" "HEADSCALE_OIDC_CLIENT_SECRET" "$HEADSCALE_OIDC_PLAIN"

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

log "OIDC client secrets -- copy these to each app's own node"
echo "Authelia needs the HASH (already written above); each app needs the"
echo "PLAINTEXT below instead, in its OWN secrets.env.local, on its OWN"
echo "node. Headscale is excluded here -- it's on this same node, already"
echo "handled automatically above."
echo
printf '%-14s %-10s %-30s %s\n' "APP" "NODE" "FILE" "KEY=VALUE TO PASTE"
for entry in \
  "Vikunja:mochaPot:vikunja" \
  "Mealie:mochaPot:mealie" \
  "Immich:mochaPot:immich" \
  "FreshRSS:mochaPot:freshrss" \
  "ActualBudget:mochaPot:actualbudget" \
  "Nextcloud:percolator:nextcloud" \
  "Paperless:percolator:paperless" \
  "HomeAssistant:percolator:homeassistant" \
  "Vaultwarden:cellar:vaultwarden" \
  "Komodo:silo:komodo" \
  "Jellyfin:roastery:jellyfin" \
; do
  app_name="${entry%%:*}"
  rest="${entry#*:}"
  node="${rest%%:*}"
  appdir="${rest#*:}"
  prefix="$(echo "$app_name" | tr '[:lower:]' '[:upper:]')"
  value="$(get_value "${DIR}/authelia/secrets.env.local" "${prefix}_OIDC_CLIENT_SECRET")"
  printf '%-14s %-10s %-30s %s\n' "$app_name" "$node" "${appdir}/secrets.env.local" "${prefix}_OIDC_CLIENT_SECRET=${value}"
done
echo
echo "After pasting, re-run that node's own generate-secrets.sh -- it'll"
echo "leave the pasted real value alone (idempotent, same as everything"
echo "else) and stop flagging it as still-needed."
