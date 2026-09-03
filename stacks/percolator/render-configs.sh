#!/usr/bin/env bash
#
# render-configs.sh — renders every *.template file under this directory
# into its real counterpart (e.g. config/komodo.yml.template ->
# config/komodo.yml), substituting ${DOMAIN}/${SILO_LAN_IP}/${TZ} from
# .env.local and each app's own secrets.env.local. Identical to
# stacks/sieve/render-configs.sh — copied verbatim, nothing silo-specific
# in the logic itself.
#
# The .template files are the source of truth and are tracked in git; the
# rendered output is gitignored since it contains the real domain and/or
# real secrets. Re-run any time .env.local or a secrets.env.local changes
# (including right after ./generate-secrets.sh) — always safe, always
# overwrites the rendered file. Never hand-edit a rendered file directly;
# edit the .template.
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v envsubst >/dev/null 2>&1 || {
  echo "envsubst not found — install it (apt-get install gettext-base) and re-run." >&2
  exit 1
}

set -a
[[ -f "${DIR}/.env.local" ]] && source "${DIR}/.env.local"
set +a

find "$DIR" -name '*.template' | while read -r tpl; do
  out="${tpl%.template}"
  app_dir="$(dirname "$(dirname "$tpl")")"
  if [[ -f "${app_dir}/secrets.env.local" ]]; then
    set -a; source "${app_dir}/secrets.env.local"; set +a
  fi
  envsubst < "$tpl" > "$out"
  echo "Rendered: ${out#"$DIR"/}"
done
