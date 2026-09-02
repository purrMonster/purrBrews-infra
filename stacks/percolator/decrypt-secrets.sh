#!/usr/bin/env bash
#
# decrypt-secrets.sh — the node-side half of the SOPS+age bridge (decided
# 2026-08-31: silo onward uses SOPS+age, unlike sieve's stack which
# deliberately kept its own local-only plaintext generate-secrets.sh — see
# .sops.yaml and secrets/README.md for why the split).
#
# Decrypts every secrets/percolator/<app>.sops.yaml (committed ciphertext,
# generated+encrypted on roastery via generate-secrets.ps1) into
# <app>/secrets.env.local here — same filename, same dotenv format, same
# consumption path as sieve's stack (compose.sh --env-file,
# render-configs.sh's envsubst). Neither of those two scripts needed to
# change at all; this just swaps out what fills secrets.env.local in the
# first place — a real value typed/generated locally on sieve, vs. decrypted
# from git here.
#
# Needs the age PRIVATE key present on this node at
# /etc/purrbrews/age/keys.txt (per purrbrews-init.sh / secrets/README.md —
# generated once on sieve, copied node-to-node over SSH, never committed).
# sops is pointed at it explicitly via SOPS_AGE_KEY_FILE below rather than
# relying on its default search path.
#
# Run this after every `git pull` that touches secrets/percolator/, and always
# before render-configs.sh (which reads each app's secrets.env.local same
# as it always has).
#
# Idempotent in the sense that matters: always re-decrypts and overwrites —
# secrets.env.local is gitignored and disposable, regenerated from the real
# source of truth (secrets/percolator/*.sops.yaml) every time. Safe to re-run
# anytime, including on a fresh clone.
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${DIR}/../.." && pwd)"
SECRETS_SRC="${REPO_ROOT}/secrets/percolator"

log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

command -v sops >/dev/null 2>&1 || fail "sops not found — install it (see secrets/README.md) and re-run."

AGE_KEY_FILE="/etc/purrbrews/age/keys.txt"
[[ -f "$AGE_KEY_FILE" ]] || fail "No age private key at ${AGE_KEY_FILE} — can't decrypt anything. See secrets/README.md: generated on sieve, copy it here over SSH (scp sieve:${AGE_KEY_FILE} root@\$(hostname):${AGE_KEY_FILE})."
export SOPS_AGE_KEY_FILE="$AGE_KEY_FILE"

if [[ ! -d "$SECRETS_SRC" ]]; then
  log "No ${SECRETS_SRC} yet — nothing to decrypt (fine if no percolator app needs secrets yet)."
  exit 0
fi

shopt -s nullglob
FILES=("${SECRETS_SRC}"/*.sops.yaml)
shopt -u nullglob

if [[ ${#FILES[@]} -eq 0 ]]; then
  log "No *.sops.yaml files in ${SECRETS_SRC} — nothing to decrypt."
  exit 0
fi

log "Decrypting ${#FILES[@]} secret file(s) from secrets/percolator/"
for f in "${FILES[@]}"; do
  app="$(basename "$f" .sops.yaml)"
  out_dir="${DIR}/${app}"
  if [[ ! -d "$out_dir" ]]; then
    echo "  SKIP ${app}: ${out_dir} doesn't exist — no such app folder under stacks/percolator. Check the filename matches the app directory name." >&2
    continue
  fi
  out="${out_dir}/secrets.env.local"
  sops -d --output-type dotenv "$f" > "${out}.tmp" \
    || { rm -f "${out}.tmp"; fail "sops couldn't decrypt ${f} — see its own error above."; }
  mv "${out}.tmp" "$out"
  chmod 600 "$out"
  echo "  decrypted: secrets/percolator/${app}.sops.yaml -> stacks/percolator/${app}/secrets.env.local"
done

log "Done. Run ./render-configs.sh next if any template values changed."
