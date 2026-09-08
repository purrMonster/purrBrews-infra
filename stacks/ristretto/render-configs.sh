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
set -uo pipefail   # deliberately no -e -- see the note above the render loop below

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v envsubst >/dev/null 2>&1 || {
  echo "envsubst not found — install it (apt-get install gettext-base) and re-run." >&2
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
