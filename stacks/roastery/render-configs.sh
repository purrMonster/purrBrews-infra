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
set -uo pipefail   # deliberately no -e -- see the note above the render loop below

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v envsubst >/dev/null 2>&1 || {
  echo "envsubst not found — install it (in WSL2: apt-get install gettext-base) and re-run." >&2
  exit 1
}

set -a
[[ -f "${DIR}/.env.local" ]] && source "${DIR}/.env.local"
set +a

FAILED=()

while IFS= read -r tpl; do
  out="${tpl%.template}"
  app_dir="$(dirname "$(dirname "$tpl")")"
  rel="${out#"$DIR"/}"

  if [[ -f "${app_dir}/secrets.env.local" ]]; then
    set -a
    if ! source "${app_dir}/secrets.env.local" 2>/dev/null; then
      set +a
      echo "FAILED: ${rel} -- couldn't source ${app_dir#"$DIR"/}/secrets.env.local (permission denied or syntax error -- check \`ls -la\` and \`bash -n\` on that file)" >&2
      FAILED+=("$rel")
      continue
    fi
    set +a
  fi

  if envsubst < "$tpl" > "$out" 2>/dev/null; then
    echo "Rendered: ${rel}"
  else
    echo "FAILED: ${rel} -- envsubst failed" >&2
    FAILED+=("$rel")
  fi
done < <(find "$DIR" -name '*.template')

if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo >&2
  echo "render-configs.sh: ${#FAILED[@]} of the templates above FAILED to render:" >&2
  for f in "${FAILED[@]}"; do echo "  - $f" >&2; done
  echo "Everything else rendered fine (see 'Rendered:' lines above) -- fix the failure(s) above and re-run; already-rendered files are untouched by a re-run that fixes only the broken one(s)." >&2
  exit 1
fi
