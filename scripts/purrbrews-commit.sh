#!/usr/bin/env bash
#
# purrbrews-commit.sh — stage changes, get an AI-written commit message from
# a LOCAL Ollama model, commit, and push.
#
# Deliberately commit-message-only. Runbook entries are NOT generated here —
# that's handled by a separate nightly job using a stronger model with more
# context, so it can look at the day's commits as a whole instead of one
# diff at a time. This script's only job is to be fast per-commit.
#
# Run from anywhere inside the purrBrews-infra working tree (it resolves the
# repo root itself via `git rev-parse --show-toplevel`).
#
# Requires:
#   - git, curl, jq
#   - Ollama running locally (`ollama serve`) with a model already pulled
#     (default: llama3.2:3b — `ollama pull llama3.2:3b`, or point
#     --model at whatever you actually have). Deliberately a small model:
#     writing a commit message doesn't need 26B-parameter reasoning, and a
#     small model turns this from a ~30-45s wait into single-digit seconds.
#     If the output quality isn't good enough, try something a bit bigger
#     (e.g. qwen2.5:7b) before reaching for a large one again — see the
#     runbook's 2026-08-27 latency entries for the numbers that drove this.
#
# Nothing here ever leaves your machine — the diff is sent to localhost
# only, never to a third-party API. Matches the project's own
# unexposed-by-default convention (see runbook, 2026-08-27 entries).
#
# Usage:
#   ./scripts/purrbrews-commit.sh [--yes] [--dry-run] [--model NAME] [--ollama-url URL] [--num-ctx N]
#
#   --yes             skip the "does this look right?" confirmation prompt
#                      (needed for unattended/scheduled use)
#   --dry-run         do everything except `git commit`/`git push` — prints
#                      the generated commit message so you can sanity-check
#                      the model's output before trusting it
#   --model NAME       override the Ollama model for this run
#   --ollama-url URL   override the Ollama base URL for this run
#   --num-ctx N        override the context window (tokens) requested from
#                       Ollama for this run — see OLLAMA_NUM_CTX below
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Config — edit defaults here, or override per-run with flags above
# ---------------------------------------------------------------------------
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
OLLAMA_MODEL="${OLLAMA_MODEL:-llama3.2:3b}"
# Diffs larger than this (chars) get truncated before being sent to the
# model — a huge diff blows a local model's context window and produces a
# useless summary anyway. The FULL diff is still what gets committed;
# only what the model sees is capped.
MAX_DIFF_CHARS=12000
# Context window (tokens) explicitly requested from Ollama via the
# `options.num_ctx` request field, on TOP of MAX_DIFF_CHARS above. Without
# this, Ollama falls back to a small default (often 4096) regardless of
# what the model actually supports — a ~12,000-char diff alone is already
# ~3,700 tokens, which leaves almost nothing for the model to answer with
# and produces exactly the "done_reason: length, empty .response" failure
# this comment is here to prevent (confirmed against this repo's own diffs:
# 3737 prompt tokens + 357 generated hit a ~4096 ceiling with zero of it
# landing in the final text — the model was still mid-answer, likely still
# reasoning internally for a thinking-capable model, when it ran out of
# room). Raise this further if you still see that failure with a bigger
# model/diff; lower it only if your model's max context is actually smaller
# than this.
OLLAMA_NUM_CTX=8192
# How long Ollama keeps the model loaded in memory after this call before
# unloading it. Reloading a large model from disk is the single most
# expensive part of a run (tens of seconds) — this just avoids paying that
# cost again if you're sitting at the y/N confirmation prompt for a while,
# or run this script again shortly after. Doesn't affect a cold first run.
OLLAMA_KEEP_ALIVE="10m"

AUTO_YES="false"
DRY_RUN="false"

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) AUTO_YES="true"; shift ;;
    --dry-run) DRY_RUN="true"; shift ;;
    --model) OLLAMA_MODEL="$2"; shift 2 ;;
    --ollama-url) OLLAMA_URL="$2"; shift 2 ;;
    --num-ctx) OLLAMA_NUM_CTX="$2"; shift 2 ;;
    -h|--help)
      grep '^#' "$0" | sed '1d;s/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown argument: $1 (see --help)" >&2; exit 1 ;;
  esac
done

log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
command -v git  &>/dev/null || die "git not found."
command -v curl &>/dev/null || die "curl not found."
command -v jq   &>/dev/null || die "jq not found (needed to talk to Ollama's JSON API)."

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "Not inside a git repo."
cd "$REPO_ROOT"

TAGS_RESPONSE="$(curl -fsS "${OLLAMA_URL}/api/tags" 2>/dev/null)" \
  || die "Can't reach Ollama at $OLLAMA_URL — is it running? (ollama serve)"

AVAILABLE_MODELS="$(printf '%s' "$TAGS_RESPONSE" | jq -r '.models[]?.name' 2>/dev/null || true)"
if [[ -n "$AVAILABLE_MODELS" ]] && ! grep -qxF "$OLLAMA_MODEL" <<< "$AVAILABLE_MODELS"; then
  warn "'$OLLAMA_MODEL' isn't in Ollama's pulled-models list — this is the most likely reason the next step fails."
  warn "Available: $(printf '%s' "$AVAILABLE_MODELS" | tr '\n' ' ')"
  warn "Pull it first (ollama pull $OLLAMA_MODEL) or pass --model with one of the names above."
fi

# ---------------------------------------------------------------------------
# Stage everything, bail if there's nothing to do
#
# `git add -A` stages new/modified/deleted files respecting .gitignore, so
# claude/, *.env.local, *.key etc. are never picked up — same guardrail
# that protects a manual `git add .` (see runbook, exposed/unexposed
# convention). This does not add any scanning beyond what .gitignore
# already excludes; it trusts the same rules the rest of the project does.
# ---------------------------------------------------------------------------
log "Staging changes (git add -A)"
git add -A

if git diff --cached --quiet; then
  log "Nothing staged — working tree matches HEAD. Nothing to commit."
  exit 0
fi

DIFF_STAT="$(git diff --cached --stat)"
DIFF_FULL="$(git diff --cached)"
DIFF_FOR_MODEL="$DIFF_FULL"
if [[ ${#DIFF_FOR_MODEL} -gt $MAX_DIFF_CHARS ]]; then
  warn "Staged diff is ${#DIFF_FOR_MODEL} chars — truncating to $MAX_DIFF_CHARS for the model (the full diff is still what gets committed)."
  DIFF_FOR_MODEL="${DIFF_FOR_MODEL:0:$MAX_DIFF_CHARS}"$'\n...[truncated for the model]'
fi

echo
echo "$DIFF_STAT"

# ---------------------------------------------------------------------------
# Ollama call helper — /api/generate, non-streaming, plain text in/out
# ---------------------------------------------------------------------------
ollama_ask() {
  local prompt="$1" payload response err text done_reason pe ev
  payload="$(jq -n --arg model "$OLLAMA_MODEL" --arg prompt "$prompt" \
    --argjson num_ctx "$OLLAMA_NUM_CTX" --arg keep_alive "$OLLAMA_KEEP_ALIVE" \
    '{model: $model, prompt: $prompt, stream: false, keep_alive: $keep_alive, options: {num_ctx: $num_ctx}}')"

  # Deliberately no -f here: Ollama's error responses (e.g. "model not
  # found") come back as a JSON body on a non-2xx status, and -f would
  # discard that body, leaving nothing for jq to report — which is exactly
  # what produced the unhelpful "empty commit message" failure this is
  # fixing. We check for `.error` ourselves instead.
  response="$(curl -sS "${OLLAMA_URL}/api/generate" -d "$payload")" \
    || die "Request to Ollama failed (network error) — is $OLLAMA_URL still reachable?"

  err="$(printf '%s' "$response" | jq -r '.error // empty' 2>/dev/null)"
  [[ -z "$err" ]] || die "Ollama returned an error: $err"

  text="$(printf '%s' "$response" | jq -r '.response // empty' 2>/dev/null)"
  if [[ -z "$text" ]]; then
    done_reason="$(printf '%s' "$response" | jq -r '.done_reason // empty' 2>/dev/null)"
    if [[ "$done_reason" == "length" ]]; then
      pe="$(printf '%s' "$response" | jq -r '.prompt_eval_count // "?"' 2>/dev/null)"
      ev="$(printf '%s' "$response" | jq -r '.eval_count // "?"' 2>/dev/null)"
      warn "Hit the context limit before producing any output (done_reason: length; ~$pe prompt tokens + $ev generated tokens, none of it landing in the final response — likely spent entirely on internal reasoning before running out of room)."
      warn "Fix: raise --num-ctx (currently $OLLAMA_NUM_CTX) so there's headroom left after the prompt, or lower MAX_DIFF_CHARS (currently $MAX_DIFF_CHARS) so the prompt itself is smaller."
    else
      warn "Ollama returned no .response and no .error — raw reply below (first 500 chars), for debugging:"
      warn "$(printf '%s' "$response" | head -c 500)"
    fi
  fi
  printf '%s' "$text"
}

strip_fences() {
  # Trim a leading ```lang and/or trailing ``` fence, if the model added one
  # despite being told not to — small local models don't always follow
  # "no code fences" instructions.
  local s
  s="$(printf '%s' "$1" | sed -e '1{/^```/d}' -e '${/^```$/d}')"
  printf '%s' "$s"
}

log "Asking $OLLAMA_MODEL for a commit message"
COMMIT_PROMPT="Write a git commit message for the following staged diff from the purrBrews-infra homelab repo. Follow Conventional Commits style (e.g. 'feat: ...', 'fix: ...', 'docs: ...', 'chore: ...'). Summary line under 72 characters, imperative mood, no trailing period. Add a short body (1-3 bullet points) only if the diff genuinely needs more explanation than the summary line gives. Output ONLY the commit message text, nothing else — no preamble, no code fences.

DIFF:
$DIFF_FOR_MODEL"

COMMIT_MSG="$(strip_fences "$(ollama_ask "$COMMIT_PROMPT")")"
[[ -n "$COMMIT_MSG" ]] || die "Model returned an empty commit message — aborting rather than committing with nothing. Staged changes are left staged."

# ---------------------------------------------------------------------------
# Preview + confirm
# ---------------------------------------------------------------------------
echo
echo "----------------------------------------------------------------------"
echo "Commit message:"
echo "$COMMIT_MSG"
echo "----------------------------------------------------------------------"

if [[ "$DRY_RUN" == "true" ]]; then
  log "Dry run — stopping before commit/push. Nothing committed. (Changes are still staged from git add -A — unstage with 'git reset' if that's not what you want.)"
  exit 0
fi

if [[ "$AUTO_YES" != "true" ]]; then
  read -r -p "Commit and push with the message above? [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || { warn "Aborted — staged changes are left staged, nothing committed or pushed."; exit 1; }
fi

# ---------------------------------------------------------------------------
# Commit, push. No runbook.md touched here — see header comment.
# ---------------------------------------------------------------------------
git commit -m "$COMMIT_MSG"
log "Committed. Pushing..."
git push
log "Done."
