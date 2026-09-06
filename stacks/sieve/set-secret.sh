#!/usr/bin/env bash
#
# set-secret.sh -- deployed to ~/.purrbrews-set-secret.sh on each remote
# node by oidc-secret-sync.sh (run from sieve). Not secret itself -- just
# the idempotent "set this KEY=VALUE in this file, unless it's already a
# real value" logic, factored out so the actual secret value never has to
# be embedded in a command string (it comes in over stdin instead, see
# oidc-secret-sync.sh's own comment on why).
#
# Usage: set-secret.sh <file> <key>   (value read from stdin)
#
set -euo pipefail

FILE="$1"
KEY="$2"
VALUE="$(cat)"

mkdir -p "$(dirname "$FILE")"
touch "$FILE"
chmod 600 "$FILE"

if grep -qE "^${KEY}=" "$FILE" 2>/dev/null; then
  CURRENT="$(grep -E "^${KEY}=" "$FILE" | tail -n1 | cut -d= -f2-)"
  if [[ -n "$CURRENT" && "$CURRENT" != REPLACE_ME* ]]; then
    echo "SKIP: ${KEY} already set in ${FILE} -- leaving it alone"
    exit 0
  fi
  sed -i "/^${KEY}=/d" "$FILE"
fi

printf '%s=%s\n' "$KEY" "$VALUE" >> "$FILE"
chmod 600 "$FILE"
echo "OK: ${KEY} set in ${FILE}"
