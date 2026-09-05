#!/usr/bin/env bash
#
# render-configs.sh — renders every *.template file under this directory
# into its real counterpart, substituting ${DOMAIN}/${TZ}/etc from
# .env.local and each app's own secrets.env.local. Identical to every
# other node's copy of this script — copied verbatim, nothing
# roastery-specific in the logic itself. No app here has a .template file
# yet (immich-ml's compose file needs no rendering, only .env.local
# interpolation via docker compose's own native ${VAR} substitution) --
# kept anyway for consistency and for whenever Ollama or another
# templated app gets added here.
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v envsubst >/dev/null 2>&1 || {
  echo "envsubst not found — install it (in WSL2: apt-get install gettext-base) and re-run." >&2
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
