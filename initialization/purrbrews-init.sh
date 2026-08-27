#!/usr/bin/env bash
#
# purrbrews-init.sh — base node initialization for Project PurrBrews
#
# Targets: sieve, silo, cellar (Lenovo ThinkCentre M710Qs, Debian 13 "trixie")
# Covers WBS 18.1 (Pre-deployment): base hardening (SSH keys, updates, static
# IP), Docker + Compose, PROJECT_DIR/DATA_DIR/MEDIA_DIR + root .env, cloning
# the purrbrews-infra repo (see "Remote repo URL sources" below), and the
# age keypair (sieve only, once).
#
# Usage:
#   sudo ./purrbrews-init.sh <sieve|silo|cellar> [--yes]
#
#   --yes   skip the confirmation prompt before applying the static IP
#           change (useful if you're at the physical console, risky over
#           SSH — read the warning before using it).
#
# SSH keys are NOT hardcoded here — see "SSH key sources" below. Keep
# ssh_authorized_keys.txt next to this script (or point at it/inline the
# keys via environment variables), so the script itself stays generic and
# the key material can live/change separately (e.g. per-node dropbox,
# secrets manager, or just a file you .gitignore).
#
# Re-running this script on a node is safe: every step is idempotent
# (package installs, user/SSH key setup, directory creation, .env writing
# all check current state first). This is the supported way to add a new
# SSH key later — e.g. for americano — add a line to ssh_authorized_keys.txt
# (or $PURRBREWS_SSH_KEYS) and re-run; existing keys and everything else are
# left untouched. You can also just append the key by hand to
# /home/barista/.ssh/authorized_keys on the node(s) that need it, without
# touching this script at all.
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Config — edit this block as the fleet plan evolves
# ---------------------------------------------------------------------------

# Known fleet IPs (extend as more nodes get assigned addresses)
declare -A NODE_IP=(
  [sieve]=192.168.0.10
  [percolator]=192.168.0.11
  [silo]=192.168.0.12
  [cellar]=192.168.0.13
  [mochaPot]=192.168.0.14
)
# Nodes this script actually provisions (base OS layer per WBS 18.1).
# percolator/mochaPot get their own base-OS step later — not this script.
SUPPORTED_NODES=(sieve silo cellar percolator mochaPot)

GATEWAY="192.168.0.1"
SUBNET_CIDR="24"
# Bootstrap DNS only — every node switches to Pi-hole (sieve) once it's live.
BOOTSTRAP_DNS="1.1.1.1"

# Reserved, not managed by this script — network infra, not Debian nodes.
# Listed here purely so .10+ fleet IPs never accidentally collide with these:
#   192.168.0.1-3  routers (per floor plan / Section 0.12)
#   192.168.0.4-5  switches

# A normal user, with root reachable via `sudo su -` (or `sudo -i`) — not
# passwordless: sudo prompts for this account's own console password, not
# the SSH key, so there's still a second factor between "has the SSH key"
# and "is root." Deliberately NOT in the docker group: that membership is
# root-equivalent with no password gate at all (trivial root shell via a
# bind-mounted container), which would silently undo the point of sudo
# requiring a separate password. Docker/compose commands go through `sudo
# docker ...` instead — same audit trail and password gate as any other
# root action, no separate ungated path. Any other group this account
# might need gets added the same explicit, one-at-a-time way — never as
# a default.
OPS_USER="barista"

# --- SSH key sources (checked in this order, all three are merged) ---------
# 1. $PURRBREWS_SSH_KEYS        — inline keys, newline- or comma-separated
#                                 (handy for a one-off run without a file)
# 2. $PURRBREWS_SSH_KEYS_FILE   — path override for the keys file below
# 3. ssh_authorized_keys.txt    — default file, one public key per line,
#                                 sitting next to this script; '#' comments
#                                 and blank lines are ignored
#
# Nothing is hardcoded in the script itself — SSH_PUBKEYS is populated at
# runtime by load_ssh_keys() (see Helpers below). The script refuses to run
# if no keys are found anywhere, since it's about to disable password auth.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_KEYS_FILE="${PURRBREWS_SSH_KEYS_FILE:-${SCRIPT_DIR}/ssh_authorized_keys.txt}"
SSH_PUBKEYS=()

PROJECT_DIR="/opt/purrbrews"
DATA_DIR="/srv/data"
MEDIA_DIR="/srv/media"

# --- Remote repo URL sources (checked in this order, first match wins) -----
# 1. $PURRBREWS_REMOTE_URL       — literal URL, handy for a one-off run
# 2. $PURRBREWS_REMOTE_URL_FILE  — path override for the file below
# 3. remote_url.txt              — default file, one URL on its first
#                                   non-comment/non-blank line, sitting next
#                                   to this script (gitignore it same as
#                                   ssh_authorized_keys.txt — it's host setup
#                                   material, not project code)
# 4. ${PROJECT_DIR}/.env.local   — read if it already exists on this node
#                                   (e.g. scp'd in ahead of time), same
#                                   PURRBREWS_REMOTE_URL=... line the repo
#                                   skeleton's own .env.local uses
#
# Nothing is hardcoded — see load_remote_url() below. If none of these
# resolve, step_git_repo() skips cloning entirely rather than falling back
# to a disconnected `git init`; a node with no known remote gets a plain
# empty $PROJECT_DIR and a warning telling you exactly what to set.
REMOTE_URL_FILE="${PURRBREWS_REMOTE_URL_FILE:-${SCRIPT_DIR}/remote_url.txt}"

# The node that owns the one-and-only age keypair generation step (first in
# deploy order — sieve → silo → cellar → percolator → mochaPot → ristretto).
#
# Deliberately OUTSIDE $PROJECT_DIR: this is unexposed data (a private key),
# and PROJECT_DIR is a git working tree. Keeping it out of that tree entirely
# means it can never be swept up by a plain `git add .`, regardless of what
# .gitignore says at the time. Only secrets/*.sops.yaml (ciphertext) belongs
# inside the repo — see 19.3.
AGE_KEY_HOME_NODE="sieve"
AGE_KEY_DIR="/etc/purrbrews/age"
AGE_KEY_FILE="${AGE_KEY_DIR}/keys.txt"

# Set to "false" to skip the baseline UFW firewall step entirely.
ENABLE_UFW="true"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

SCRIPT_NAME="$(basename "$0")"
AUTO_YES="false"

log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

confirm() {
  local prompt="$1"
  if [[ "$AUTO_YES" == "true" ]]; then
    return 0
  fi
  read -r -p "$prompt [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "Run this as root (sudo $SCRIPT_NAME ...)."
}

detect_iface() {
  # Interface currently holding the default route — works whether the node
  # is presently on DHCP or already static.
  ip -o route show default 2>/dev/null | awk '{print $5; exit}'
}

load_ssh_keys() {
  SSH_PUBKEYS=()

  if [[ -n "${PURRBREWS_SSH_KEYS:-}" ]]; then
    local raw="${PURRBREWS_SSH_KEYS//,/$'\n'}"
    while IFS= read -r line; do
      line="${line%$'\r'}"
      [[ -z "$line" || "$line" == \#* ]] && continue
      SSH_PUBKEYS+=("$line")
    done <<< "$raw"
  fi

  if [[ -f "$SSH_KEYS_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      [[ -z "$line" || "$line" == \#* ]] && continue
      SSH_PUBKEYS+=("$line")
    done < "$SSH_KEYS_FILE"
  fi

  if [[ ${#SSH_PUBKEYS[@]} -eq 0 ]]; then
    die "No SSH public keys found. Put one per line in $SSH_KEYS_FILE, or set \$PURRBREWS_SSH_KEYS (newline- or comma-separated), then re-run. Refusing to continue — this script is about to lock out password auth."
  fi

  log "Loaded ${#SSH_PUBKEYS[@]} SSH public key(s) from: ${PURRBREWS_SSH_KEYS:+\$PURRBREWS_SSH_KEYS, }${SSH_KEYS_FILE}"
}

load_remote_url() {
  REMOTE_URL=""
  REMOTE_URL_SOURCE=""

  if [[ -n "${PURRBREWS_REMOTE_URL:-}" ]]; then
    REMOTE_URL="$PURRBREWS_REMOTE_URL"
    REMOTE_URL_SOURCE='$PURRBREWS_REMOTE_URL'
  elif [[ -f "$REMOTE_URL_FILE" ]]; then
    REMOTE_URL="$(grep -vE '^\s*#|^\s*$' "$REMOTE_URL_FILE" | head -n1)"
    [[ -n "$REMOTE_URL" ]] && REMOTE_URL_SOURCE="$REMOTE_URL_FILE"
  fi

  if [[ -z "$REMOTE_URL" && -f "${PROJECT_DIR}/.env.local" ]]; then
    REMOTE_URL="$(grep -E '^PURRBREWS_REMOTE_URL=' "${PROJECT_DIR}/.env.local" | tail -n1 | cut -d= -f2-)"
    [[ -n "$REMOTE_URL" ]] && REMOTE_URL_SOURCE="${PROJECT_DIR}/.env.local"
  fi
}

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

step_preflight() {
  log "Preflight checks"

  require_root

  [[ -f /etc/os-release ]] && . /etc/os-release || die "/etc/os-release not found."
  if [[ "${ID:-}" != "debian" ]]; then
    warn "This box reports ID=${ID:-unknown}, not debian. Continuing anyway, but double-check."
  elif [[ "${VERSION_ID:-}" != "13" ]]; then
    warn "This box reports Debian ${VERSION_ID:-unknown}, not 13 (trixie). Continuing anyway."
  fi

  local match=0
  for n in "${SUPPORTED_NODES[@]}"; do
    [[ "$n" == "$NODE" ]] && match=1
  done
  [[ "$match" -eq 1 ]] || die "Unknown node '$NODE'. Expected one of: ${SUPPORTED_NODES[*]}"

  [[ -n "${NODE_IP[$NODE]:-}" ]] || die "No static IP configured for '$NODE' — edit NODE_IP in this script."

  load_ssh_keys

  log "Target node: $NODE  →  ${NODE_IP[$NODE]}/${SUBNET_CIDR} via $GATEWAY"
}

step_hostname_hosts() {
  log "Setting hostname and /etc/hosts"

  hostnamectl set-hostname "$NODE"

  # Make sure 127.0.1.1 maps to the node name (standard Debian convention)
  if grep -qE '^\s*127\.0\.1\.1\s' /etc/hosts; then
    sed -i "s/^\s*127\.0\.1\.1\s.*/127.0.1.1\t$NODE/" /etc/hosts
  else
    printf '127.0.1.1\t%s\n' "$NODE" >> /etc/hosts
  fi

  # Seed /etc/hosts with every fleet node we currently have an IP for, so
  # sieve/silo/cellar can resolve each other by name before Pi-hole exists.
  local marker="# --- purrbrews fleet (managed block, safe to re-run) ---"
  if grep -qF "$marker" /etc/hosts; then
    # Strip the old managed block, then re-append a fresh one below.
    sed -i "/^${marker//\//\\/}$/,/^# --- end purrbrews fleet ---$/d" /etc/hosts
  fi
  {
    echo "$marker"
    for n in "${!NODE_IP[@]}"; do
      printf '%s\t%s\n' "${NODE_IP[$n]}" "$n"
    done
    echo "# --- end purrbrews fleet ---"
  } >> /etc/hosts
}

step_apt_base() {
  log "apt update/upgrade + base packages"

  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get -y upgrade

  apt-get -y install \
    ca-certificates curl gnupg lsb-release \
    git age sudo vim htop tmux net-tools \
    unattended-upgrades apt-listchanges \
    ufw

  # Unattended security updates — covers the "updates" half of base hardening.
  if [[ ! -f /etc/apt/apt.conf.d/20auto-upgrades ]]; then
    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
  fi
}

step_admin_user() {
  log "Ops user: $OPS_USER (sudo-capable — see the note above OPS_USER)"

  if ! id "$OPS_USER" &>/dev/null; then
    adduser --disabled-password --gecos "" "$OPS_USER"
    local genpass
    genpass="$(openssl rand -base64 18)"
    echo "${OPS_USER}:${genpass}" | chpasswd
    warn "Generated a local password for $OPS_USER (needed for 'sudo su -'/'sudo -i' to reach root — SSH login itself is still key-only, see below):"
    warn "    $genpass"
    warn "Store this somewhere safe (the emergency-access USB, or Vaultwarden once cellar is live) and/or change it with 'passwd $OPS_USER'."
  else
    log "$OPS_USER already exists — leaving password as-is."
  fi

  usermod -aG sudo "$OPS_USER"

  # No docker group — see the note above OPS_USER's definition. Docker
  # commands go through `sudo docker ...` instead.

  install -d -m 700 -o "$OPS_USER" -g "$OPS_USER" "/home/${OPS_USER}/.ssh"
  local akfile="/home/${OPS_USER}/.ssh/authorized_keys"
  touch "$akfile"
  chmod 600 "$akfile"
  chown "$OPS_USER:$OPS_USER" "$akfile"

  local added=0
  for key in "${SSH_PUBKEYS[@]}"; do
    if ! grep -qF "$key" "$akfile" 2>/dev/null; then
      echo "$key" >> "$akfile"
      added=$((added + 1))
    fi
  done
  log "Authorized keys: ${#SSH_PUBKEYS[@]} configured, $added newly added, $(wc -l < "$akfile") total on this node."
}

step_ssh_hardening() {
  log "SSH hardening (key-only login, no root login)"

  local sshd_config="/etc/ssh/sshd_config"
  local backup="/etc/ssh/sshd_config.pre-purrbrews.bak"
  [[ -f "$backup" ]] || cp "$sshd_config" "$backup"

  set_sshd_option() {
    local key="$1" value="$2"
    if grep -qE "^\s*#?\s*${key}\s+" "$sshd_config"; then
      sed -i -E "s|^\s*#?\s*(${key})\s+.*|\1 ${value}|" "$sshd_config"
    else
      echo "${key} ${value}" >> "$sshd_config"
    fi
  }

  set_sshd_option "PasswordAuthentication" "no"
  set_sshd_option "PermitRootLogin" "no"
  set_sshd_option "KbdInteractiveAuthentication" "no"
  set_sshd_option "PubkeyAuthentication" "yes"

  sshd -t || die "sshd_config failed validation — reverting."
  systemctl reload ssh || systemctl reload sshd

  log "Password auth disabled. Confirm you can log in as $OPS_USER with your key in a NEW terminal before closing this session."
}

step_static_ip() {
  log "Static IP configuration"

  local iface
  iface="$(detect_iface)"
  [[ -n "$iface" ]] || die "Couldn't detect the active network interface (no default route). Set it manually."

  local target_ip="${NODE_IP[$NODE]}"
  local current_ip
  current_ip="$(ip -o -4 addr show dev "$iface" | awk '{print $4}' | cut -d/ -f1 | head -n1)"

  log "Interface: $iface   Current IP: ${current_ip:-none}   Target IP: $target_ip/$SUBNET_CIDR"

  if [[ "$current_ip" == "$target_ip" ]]; then
    log "Already on the target IP — skipping network reconfiguration."
    return
  fi

  warn "This rewrites $iface's config to a static IP. If you're connected over SSH and the"
  warn "network doesn't come back up cleanly, you'll need physical/console access to fix it."
  if ! confirm "Apply static IP $target_ip/$SUBNET_CIDR on $iface now?"; then
    warn "Skipped static IP configuration — re-run this script (or edit $iface's config by hand) when ready."
    return
  fi

  if [[ -d /etc/network ]] && systemctl is-enabled networking &>/dev/null; then
    # Traditional ifupdown (Debian's default outside minimal cloud images)
    local ifcfg="/etc/network/interfaces.d/${iface}.cfg"
    mkdir -p /etc/network/interfaces.d
    if ! grep -q '^source /etc/network/interfaces\.d/\*' /etc/network/interfaces 2>/dev/null; then
      echo 'source /etc/network/interfaces.d/*' >> /etc/network/interfaces
    fi
    cat > "$ifcfg" <<EOF
auto ${iface}
iface ${iface} inet static
    address ${target_ip}/${SUBNET_CIDR}
    gateway ${GATEWAY}
    dns-nameservers ${BOOTSTRAP_DNS}
EOF
    log "Wrote $ifcfg — applying (this may briefly drop your SSH session)."
    ifdown "$iface" 2>/dev/null || true
    ifup "$iface" || systemctl restart networking

  elif command -v nmcli &>/dev/null && systemctl is-active NetworkManager &>/dev/null; then
    # NetworkManager fallback, in case this image ended up using it instead
    local con
    con="$(nmcli -t -f NAME,DEVICE con show | awk -F: -v d="$iface" '$2==d{print $1; exit}')"
    [[ -n "$con" ]] || con="$iface"
    nmcli con mod "$con" ipv4.addresses "${target_ip}/${SUBNET_CIDR}" \
                          ipv4.gateway "$GATEWAY" \
                          ipv4.dns "$BOOTSTRAP_DNS" \
                          ipv4.method manual
    nmcli con up "$con"

  else
    die "Neither ifupdown nor NetworkManager detected as the active network manager — configure $iface manually with IP $target_ip/$SUBNET_CIDR, gateway $GATEWAY, DNS $BOOTSTRAP_DNS."
  fi

  log "Static IP applied. Reconnect to $target_ip if this session drops."
}

step_docker() {
  log "Docker + Compose"

  if command -v docker &>/dev/null; then
    log "Docker already installed ($(docker --version)) — skipping install."
  else
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    local codename="${VERSION_CODENAME:-trixie}"
    # Docker's apt repo may not have caught up to a very new Debian codename
    # yet; fall back to bookworm's repo (packages are compatible) if trixie
    # isn't listed.
    if ! curl -fsSL "https://download.docker.com/linux/debian/dists/${codename}/Release" -o /dev/null 2>/dev/null; then
      warn "Docker's apt repo has no '${codename}' suite yet — falling back to 'bookworm'."
      codename="bookworm"
    fi

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${codename} stable" \
      > /etc/apt/sources.list.d/docker.list

    apt-get update
    apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi

  systemctl enable --now docker
  # $OPS_USER is deliberately NOT added to the docker group — see the note
  # above OPS_USER's definition. Use `sudo docker ...` / `sudo docker
  # compose ...` for anything that needs it.
  log "Docker enabled. Run docker/compose commands as \$OPS_USER via 'sudo docker ...' — no docker group membership by design."
}

step_git_repo() {
  log "purrbrews repo (clone from the configured remote)"

  if [[ -d "${PROJECT_DIR}/.git" ]]; then
    log "Git repo already present at $PROJECT_DIR — pulling latest instead of re-cloning."
    git -C "$PROJECT_DIR" pull --ff-only \
      || warn "git pull --ff-only failed on $PROJECT_DIR — resolve manually (local changes? diverged history?). Leaving the repo as-is."
    chown -R "$OPS_USER:$OPS_USER" "$PROJECT_DIR"
    return
  fi

  load_remote_url

  if [[ -z "$REMOTE_URL" ]]; then
    warn "No repo remote configured — checked \$PURRBREWS_REMOTE_URL, $REMOTE_URL_FILE, and"
    warn "${PROJECT_DIR}/.env.local, found none. Set one of those (the repo's own .env.local,"
    warn "gitignored, uses PURRBREWS_REMOTE_URL=... — see the repo skeleton) and re-run this"
    warn "script to clone. Leaving $PROJECT_DIR as a plain, non-git directory for now — NOT"
    warn "running 'git init' here, since a disconnected local history is worse than none."
    install -d -m 2775 -o "$OPS_USER" -g "$OPS_USER" "$PROJECT_DIR"
    return
  fi

  if [[ -e "$PROJECT_DIR" && -n "$(ls -A "$PROJECT_DIR" 2>/dev/null)" ]]; then
    die "$PROJECT_DIR exists and is non-empty but isn't a git repo — can't clone into it." \
        "Move its contents aside (or remove it, if it's just the .env this script writes" \
        "further down — that gets regenerated) and re-run."
  fi

  log "Cloning $REMOTE_URL (from $REMOTE_URL_SOURCE) into $PROJECT_DIR"
  rmdir "$PROJECT_DIR" 2>/dev/null || true   # git clone wants to create the target dir itself
  git clone -q "$REMOTE_URL" "$PROJECT_DIR" \
    || die "Clone failed — check $REMOTE_URL is reachable and that $OPS_USER (or this node) has credentials/deploy-key access to it."
  chown -R "$OPS_USER:$OPS_USER" "$PROJECT_DIR"
}

step_directories() {
  log "DATA_DIR / MEDIA_DIR + shared .env"

  install -d -m 2775 -o "$OPS_USER" -g "$OPS_USER" "$DATA_DIR"
  install -d -m 2775 -o "$OPS_USER" -g "$OPS_USER" "$MEDIA_DIR"

  # PROJECT_DIR itself was already created by step_git_repo (either via
  # clone, or as an empty placeholder if no remote was configured yet).
  local envfile="${PROJECT_DIR}/.env"
  cat > "$envfile" <<EOF
# Identical on every node (Section 19.1) — do not put secrets in this file.
PROJECT_DIR=${PROJECT_DIR}
DATA_DIR=${DATA_DIR}
MEDIA_DIR=${MEDIA_DIR}
EOF
  chown "$OPS_USER:$OPS_USER" "$envfile"
  chmod 644 "$envfile"
}

step_age_key() {
  log "age keypair (SOPS secrets encryption)"

  if [[ -f "$AGE_KEY_FILE" ]]; then
    log "age key already present at $AGE_KEY_FILE — leaving it alone."
    return
  fi

  if [[ "$NODE" != "$AGE_KEY_HOME_NODE" ]]; then
    warn "No age private key found on $NODE, and this isn't $AGE_KEY_HOME_NODE (where it's generated)."
    warn "Copy it over securely once it exists, e.g.:"
    warn "    scp ${AGE_KEY_HOME_NODE}:${AGE_KEY_FILE} root@${NODE}:${AGE_KEY_FILE}"
    warn "SOPS-encrypted secrets in the repo can't be decrypted on this node until you do."
    return
  fi

  if ! confirm "Generate the fleet's ONE age keypair on $NODE now? (do this exactly once)"; then
    warn "Skipped. Nothing decrypts/encrypts secrets until this key exists somewhere."
    return
  fi

  install -d -m 700 -o "$OPS_USER" -g "$OPS_USER" "$AGE_KEY_DIR"
  age-keygen -o "$AGE_KEY_FILE"
  chown "$OPS_USER:$OPS_USER" "$AGE_KEY_FILE"
  chmod 600 "$AGE_KEY_FILE"

  local pubkey
  pubkey="$(grep 'public key:' "$AGE_KEY_FILE" | awk '{print $NF}')"

  warn "=============================================================================="
  warn " AGE KEYPAIR GENERATED — THIS IS THE ONLY COPY RIGHT NOW."
  warn " Private key: $AGE_KEY_FILE"
  warn " Public key:  $pubkey"
  warn ""
  warn " Do these two things before deploying anything else (Section 19.3):"
  warn "   1. Back up $AGE_KEY_FILE OFFLINE (printed copy or a USB kept safely)."
  warn "      This offline copy is the real disaster-recovery copy, not this disk."
  warn "   2. Copy $AGE_KEY_FILE to silo and cellar (scp over SSH is fine) so they"
  warn "      can decrypt secrets too. Use the public key above in .sops.yaml."
  warn " Once Vaultwarden is live on cellar, stash a convenience copy there too —"
  warn " the offline copy remains authoritative."
  warn "=============================================================================="
}

step_firewall() {
  [[ "$ENABLE_UFW" == "true" ]] || { log "UFW step disabled — skipping."; return; }

  log "Baseline firewall (UFW: SSH only, default deny incoming)"

  ufw --force reset >/dev/null
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow OpenSSH
  ufw --force enable
  ufw status verbose
}

step_summary() {
  log "Done: $NODE"
  cat <<EOF

  Node:        $NODE
  IP:          ${NODE_IP[$NODE]}/${SUBNET_CIDR} (gateway $GATEWAY)
  Ops user:    $OPS_USER (sudo only, no docker group; SSH key-only login, sudo needs its own password — use 'sudo docker ...')
  PROJECT_DIR: $PROJECT_DIR
  DATA_DIR:    $DATA_DIR
  MEDIA_DIR:   $MEDIA_DIR

  Next manual steps (per Section 18):
    - Once sieve/silo/cellar are all initialized, continue with 18.2 (sieve:
      Pi-hole → lldap → Redis → Authelia → Traefik → Headscale → cloudflared).
    - If \$PROJECT_DIR isn't a git repo yet (no remote was configured when
      this ran), set PURRBREWS_REMOTE_URL and re-run to clone it.

EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

NODE="${1:-}"
shift || true
for arg in "$@"; do
  [[ "$arg" == "--yes" ]] && AUTO_YES="true"
done

[[ -n "$NODE" ]] || { echo "Usage: sudo $SCRIPT_NAME <sieve|silo|cellar> [--yes]"; exit 1; }

step_preflight
step_hostname_hosts
step_apt_base
step_admin_user
step_ssh_hardening
step_static_ip
step_docker
step_git_repo
step_directories
step_age_key
step_firewall
step_summary
