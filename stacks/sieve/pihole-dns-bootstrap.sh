#!/usr/bin/env bash
#
# pihole-dns-bootstrap.sh — idempotently ensures Pi-hole's split-horizon DNS
# entries (pihole/authelia/traefik/headscale .${DOMAIN} -> SIEVE_LAN_IP) are
# present in its live config, via pihole-FTL's own config CLI instead of a
# dropped-in dnsmasq.d file.
#
# Why this exists (2026-08-30): the original approach was a rendered
# custom-dns/*.conf file bind-mounted into /etc/dnsmasq.d/. That's a v5-era
# Pi-hole pattern. This stack runs Pi-hole v6 (FTL v6.7), which generates
# dnsmasq's actual config entirely from /etc/pihole/pihole.toml at every
# startup and never scans /etc/dnsmasq.d — the old file sat there completely
# inert, no error or warning, just silently never read. First real login
# test failed with NXDOMAIN on pihole.${DOMAIN} despite the file being
# correctly rendered and mounted, which is how this got caught. The real v6
# mechanism is pihole.toml's `misc.dnsmasq_lines` array — a raw
# dnsmasq-config-line passthrough (same `address=/domain/ip` syntax as
# before, just relocated), set live via `pihole-FTL --config misc.dnsmasq_lines
# '[...]'`. See pihole/docker-compose.yml's comment and the 2026-08-30
# runbook entry for the full story.
#
# Idempotent — safe to re-run. Only appends entries that are actually
# missing; never removes or reorders anything already in dnsmasq_lines (so
# it won't clobber an entry you added by hand for something outside this
# stack), and only restarts the pihole container if something actually
# changed.
#
# --dry-run: reads the current config for real (harmless) but prints what
# it WOULD set instead of calling `pihole-FTL --config` or restarting the
# container.
#
set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v jq >/dev/null 2>&1 || {
  echo "jq not found — install it (apt-get install jq) and re-run." >&2
  exit 1
}

set -a
[[ -f "${DIR}/.env.local" ]] && source "${DIR}/.env.local"
set +a

: "${DOMAIN:?DOMAIN not set in .env.local — fill it in first, see README.md}"
: "${SIEVE_LAN_IP:?SIEVE_LAN_IP not set in .env.local — fill it in first, see README.md}"

log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

# DOCKER_CMD: prefer plain `docker` (works once barista's docker group
# membership is live in the current shell), fall back to `sudo docker`
# otherwise — same permission caveat as every other script in this stack
# that touches the docker socket.
DOCKER_CMD="docker"
docker info >/dev/null 2>&1 || DOCKER_CMD="sudo docker"

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "DRY RUN — reading current config for real, nothing will actually be changed"
fi

# Same subdomain list as the old custom-dns template — add to this array if
# more sieve-hosted apps get their own Traefik-fronted subdomain later.
SUBDOMAINS=(pihole authelia traefik headscale)

log "Reading current misc.dnsmasq_lines from the running pihole container"
CURRENT_RAW="$(${DOCKER_CMD} exec pihole pihole-FTL --config misc.dnsmasq_lines)" \
  || fail "Couldn't read config from the pihole container — is it running? (./compose.sh pihole up -d)"

# FTL prints this back as "[ item1, item2, ... ]" — not JSON, not quoted.
# Strip the brackets and split on ", " to get the existing raw entries.
STRIPPED="${CURRENT_RAW#*[}"
STRIPPED="${STRIPPED%]*}"
declare -a CURRENT_LINES=()
if [[ -n "$(echo "$STRIPPED" | tr -d '[:space:]')" ]]; then
  IFS=',' read -ra RAW_ITEMS <<< "$STRIPPED"
  for item in "${RAW_ITEMS[@]}"; do
    # xargs trims leading/trailing whitespace
    item="$(echo "$item" | xargs)"
    [[ -n "$item" ]] && CURRENT_LINES+=("$item")
  done
fi
echo "  Currently set: ${#CURRENT_LINES[@]} line(s)"

# Build the desired lines and figure out which ones are actually missing —
# preserving every existing line (including ones this script didn't add)
# rather than overwriting the array wholesale.
declare -a MERGED=("${CURRENT_LINES[@]}")
declare -a MISSING=()
for sub in "${SUBDOMAINS[@]}"; do
  desired="address=/${sub}.${DOMAIN}/${SIEVE_LAN_IP}"
  found=0
  for existing in "${CURRENT_LINES[@]}"; do
    [[ "$existing" == "$desired" ]] && { found=1; break; }
  done
  if [[ "$found" -eq 0 ]]; then
    MISSING+=("$desired")
    MERGED+=("$desired")
  fi
done

if [[ "${#MISSING[@]}" -eq 0 ]]; then
  log "All ${#SUBDOMAINS[@]} split-horizon entries already present — nothing to do."
  exit 0
fi

log "Missing ${#MISSING[@]} entr$([[ ${#MISSING[@]} -eq 1 ]] && echo y || echo ies):"
for m in "${MISSING[@]}"; do
  echo "  + ${m}"
done

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "  [dry-run] would set misc.dnsmasq_lines to the ${#MERGED[@]} lines above (existing + missing) and restart pihole"
  log "Done (dry run)"
  exit 0
fi

log "Setting misc.dnsmasq_lines (${#MERGED[@]} total lines)"
NEW_JSON="$(jq -nc '$ARGS.positional' --args "${MERGED[@]}")"
${DOCKER_CMD} exec pihole pihole-FTL --config misc.dnsmasq_lines "$NEW_JSON" \
  || fail "pihole-FTL --config rejected the new value — see its own error above."

log "Restarting pihole so dnsmasq picks up the new config"
${DOCKER_CMD} restart pihole >/dev/null \
  || fail "Config was set but the container restart failed — restart it by hand: ${DOCKER_CMD} restart pihole"

log "Done — verify with: nslookup pihole.${DOMAIN}"
