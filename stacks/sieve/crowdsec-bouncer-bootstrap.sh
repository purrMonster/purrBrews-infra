#!/usr/bin/env bash
#
# crowdsec-bouncer-bootstrap.sh — installs and registers the firewall
# bouncer that actually enforces crowdsec's decisions (bans) at the OS
# level. Different from every other *-bootstrap.sh in this stack in one
# important way, read this before running it:
#
#   EVERY OTHER bootstrap script here only ever calls a container's own
#   live API (headscale's CLI over `docker exec`, lldap's GraphQL API,
#   pihole-FTL's config API). This one installs a real Debian package on
#   sieve itself (apt) and enables a systemd service — i.e. it modifies
#   the host, not just a container. That's not a choice made lightly: see
#   the 2026-09-01 runbook entry for why the firewall bouncer specifically
#   can't be containerized sanely (it has to rewrite sieve's own
#   iptables/nftables rules — the "run it in Docker too" approaches found
#   during research are described by the crowdsec community itself as
#   emerging/experimental, not the proven path, whereas the native-package
#   route is what crowdsec's own docs and every mature deployment guide
#   use). Read the diff between what you have and what this does before
#   running it for real, same as you'd want for anything else that
#   touches firewall rules.
#
# What it does, in order:
#   1. Installs crowdsec-firewall-bouncer-iptables via crowdsec's own
#      install script + apt (skipped if already installed).
#      NOTE: this package's own postinstall script expects a NATIVE
#      crowdsec install on the same host and tries to auto-register
#      against it — that will silently fail/no-op here, since sieve's
#      crowdsec is the Dockerized one from ./crowdsec/docker-compose.yml,
#      not a native install. Harmless; step 2 below does real registration
#      instead, against the containerized LAPI.
#   2. Registers a bouncer named sieve-firewall-bouncer against the
#      crowdsec container's LAPI (docker exec crowdsec cscli bouncers
#      add), capturing the API key it returns.
#   3. Writes /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml with
#      that key, pointed at http://127.0.0.1:8080/ (crowdsec's LAPI port,
#      published loopback-only — see crowdsec/docker-compose.yml).
#   4. Enables + starts the crowdsec-firewall-bouncer systemd service.
#
# Idempotent: if a bouncer named sieve-firewall-bouncer already exists in
# crowdsec AND the local config file already has a real (non-placeholder)
# api_key, does nothing. crowdsec never lets you read a bouncer's key back
# after creation — so if the registration exists but the local key is
# missing (e.g. this file got reset), the only recovery is deleting and
# re-adding to get a fresh key; this script does that automatically in
# that specific case (logged clearly when it happens).
#
# Usage:
#   ./crowdsec-bouncer-bootstrap.sh --dry-run
#   ./crowdsec-bouncer-bootstrap.sh
#
# --dry-run: checks/reads everything for real (harmless) but doesn't
# install, register, write, or enable anything.
#
set -euo pipefail

BOUNCER_NAME="sieve-firewall-bouncer"
BOUNCER_CONFIG="/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml"

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || fail "jq not found — install it (apt-get install jq) and re-run."

DOCKER_CMD="docker"
docker info >/dev/null 2>&1 || DOCKER_CMD="sudo docker"

${DOCKER_CMD} exec crowdsec cscli version >/dev/null 2>&1 \
  || fail "Can't reach the crowdsec container — is it running? (./compose.sh crowdsec up -d)"

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "DRY RUN — checking current state for real, nothing will actually be installed/changed"
fi

log "Checking whether crowdsec-firewall-bouncer is already installed"
if dpkg -s crowdsec-firewall-bouncer-iptables >/dev/null 2>&1; then
  echo "  already installed"
  NEED_INSTALL=0
else
  echo "  not installed"
  NEED_INSTALL=1
fi

if [[ "$NEED_INSTALL" -eq 1 ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [dry-run] would run: curl -s https://install.crowdsec.net | sudo sh"
    echo "  [dry-run] would run: sudo apt install -y crowdsec-firewall-bouncer-iptables"
  else
    log "Installing (crowdsec's own install script, then apt)"
    curl -s https://install.crowdsec.net | sudo sh \
      || fail "install.crowdsec.net script failed — see its own output above."
    sudo apt-get install -y crowdsec-firewall-bouncer-iptables \
      || fail "apt install failed — see its own output above. If sieve's Debian is a pure-nftables setup and this conflicts, try crowdsec-firewall-bouncer-nftables instead (see the header comment)."
  fi
fi

log "Checking existing bouncer registration"
EXISTING_JSON="$(${DOCKER_CMD} exec crowdsec cscli bouncers list -o json)" \
  || fail "Couldn't list bouncers from the crowdsec container."
ALREADY_REGISTERED=0
echo "$EXISTING_JSON" | jq -e --arg n "$BOUNCER_NAME" '(. // [])[] | select(.name == $n)' >/dev/null 2>&1 \
  && ALREADY_REGISTERED=1

HAVE_LOCAL_KEY=0
if [[ -f "$BOUNCER_CONFIG" ]] && grep -qE '^api_key: .+' "$BOUNCER_CONFIG" 2>/dev/null \
  && ! grep -q 'REPLACE_ME' "$BOUNCER_CONFIG" 2>/dev/null; then
  HAVE_LOCAL_KEY=1
fi

if [[ "$ALREADY_REGISTERED" -eq 1 && "$HAVE_LOCAL_KEY" -eq 1 ]]; then
  log "'${BOUNCER_NAME}' is already registered and ${BOUNCER_CONFIG} already has a real key — nothing to do."
  echo "Verify it's actually connected: ${DOCKER_CMD} exec crowdsec cscli bouncers list"
  exit 0
fi

if [[ "$ALREADY_REGISTERED" -eq 1 && "$HAVE_LOCAL_KEY" -eq 0 ]]; then
  echo "  '${BOUNCER_NAME}' is registered in crowdsec but ${BOUNCER_CONFIG} has no usable key —"
  echo "  crowdsec can't return an existing key, so this needs a fresh registration."
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [dry-run] would run: cscli bouncers delete ${BOUNCER_NAME}, then re-add"
  else
    log "Deleting the old registration so a fresh one can be created"
    ${DOCKER_CMD} exec crowdsec cscli bouncers delete "$BOUNCER_NAME" \
      || fail "Failed to delete the old '${BOUNCER_NAME}' registration."
  fi
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "  [dry-run] would run: cscli bouncers add ${BOUNCER_NAME}"
  echo "  [dry-run] would write api_key + api_url into ${BOUNCER_CONFIG}"
  echo "  [dry-run] would run: systemctl enable --now crowdsec-firewall-bouncer"
  log "Done (dry run)"
  exit 0
fi

log "Registering '${BOUNCER_NAME}' with crowdsec's LAPI"
API_KEY="$(${DOCKER_CMD} exec crowdsec cscli bouncers add "$BOUNCER_NAME" -o raw)" \
  || fail "cscli bouncers add failed — see its own error above."
API_KEY="$(echo "$API_KEY" | tr -d '\r\n')"
[[ -n "$API_KEY" ]] || fail "cscli bouncers add returned an empty key — something's wrong, check crowdsec's logs (${DOCKER_CMD} logs crowdsec)."

log "Writing ${BOUNCER_CONFIG}"
sudo mkdir -p "$(dirname "$BOUNCER_CONFIG")"
sudo tee "$BOUNCER_CONFIG" >/dev/null <<EOF
# Written by crowdsec-bouncer-bootstrap.sh ($(date -Is)) — not tracked in
# git, this is a host config file with a live secret in it. Re-running the
# script is the supported way to change anything here; don't hand-edit
# api_key (a hand-edit survives until the next re-run, which is exactly
# when it'd get silently clobbered).
mode: iptables
api_url: http://127.0.0.1:8080/
api_key: ${API_KEY}
disable_ipv6: false
deny_action: DROP
EOF
sudo chmod 600 "$BOUNCER_CONFIG"

log "Enabling + starting crowdsec-firewall-bouncer"
sudo systemctl enable --now crowdsec-firewall-bouncer \
  || fail "systemctl enable/start failed — see 'systemctl status crowdsec-firewall-bouncer' and 'journalctl -u crowdsec-firewall-bouncer' for why."

log "Done."
echo "Verify it actually connected (should show a recent 'last_pull'/last-seen"
echo "time, not blank, within a minute or so):"
echo "  ${DOCKER_CMD} exec crowdsec cscli bouncers list"
