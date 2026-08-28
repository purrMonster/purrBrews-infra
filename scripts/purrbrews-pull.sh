#!/usr/bin/env bash
#
# purrbrews-pull.sh — cron-driven `git pull --ff-only` for PROJECT_DIR on a
# fleet node. Installed by purrbrews-init.sh's step_cron_pull(), intended to
# run unattended every morning. Pull-only, by design:
#   - never pushes, never commits, never touches secrets/ encryption
#   - never prompts (GIT_TERMINAL_PROMPT=0) — a cron job that can hang on a
#     credential prompt forever is worse than one that fails fast and logs it
#   - --ff-only: if the node's local history has diverged (should never
#     happen with "no live coding on fleet nodes", but this is a safety net,
#     not a guarantee), this refuses to merge/rebase automatically and just
#     logs a failure for a human to look at
#
# KNOWN GAP: the configured remote (see remote_url.txt / $PURRBREWS_REMOTE_URL
# in purrbrews-init.sh) is an HTTPS GitHub URL for a private repo. Without a
# stored credential (a `git config credential.helper store` after one manual
# authenticated pull with a PAT, or switching the remote to SSH with a
# read-only deploy key) this WILL fail every run — that's deliberate
# (fail loud, not hang), but it means this script alone doesn't make cron
# pulls actually work. Set up non-interactive auth for $OPS_USER once,
# per node, before relying on this.
#
# Usage: purrbrews-pull.sh
#   Env overrides (both optional):
#     PURRBREWS_PROJECT_DIR   default: /opt/purrbrews
#     PURRBREWS_PULL_LOG      default: /var/log/purrbrews/pull.log
#
set -euo pipefail

PROJECT_DIR="${PURRBREWS_PROJECT_DIR:-/opt/purrbrews}"
LOG_FILE="${PURRBREWS_PULL_LOG:-/var/log/purrbrews/pull.log}"

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S%z')" "$*" >> "$LOG_FILE"; }

if [[ ! -d "${PROJECT_DIR}/.git" ]]; then
  log "ERROR: ${PROJECT_DIR} is not a git repo yet — nothing to pull. Run purrbrews-init.sh's step_git_repo first."
  exit 1
fi

# Never hang cron on a username/password prompt — fail fast and log instead.
export GIT_TERMINAL_PROMPT=0

before="$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"

if output="$(git -C "$PROJECT_DIR" pull --ff-only 2>&1)"; then
  after="$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
  if [[ "$before" == "$after" ]]; then
    log "OK: already up to date (${after:0:12})."
  else
    log "OK: updated ${before:0:12} -> ${after:0:12}."
    log "$output"
  fi
else
  log "FAILED: git pull --ff-only exited non-zero (diverged history, dirty tree, or auth failure — see KNOWN GAP above). This node will NOT self-heal; investigate manually."
  log "$output"
  exit 1
fi
