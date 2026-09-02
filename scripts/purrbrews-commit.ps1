<#
.SYNOPSIS
  Stage changes, get an AI-written commit message from a LOCAL Ollama
  model, commit, and push.

.DESCRIPTION
  Deliberately commit-message-only. Runbook entries are NOT generated here
  -- that's handled by a separate nightly job using a stronger model with
  more context, so it can look at the day's commits as a whole instead of
  one diff at a time. This script's only job is to be fast per-commit.

  Run from anywhere inside the purrBrews-infra working tree (it resolves
  the repo root itself via `git rev-parse --show-toplevel`).

  Requires:
    - git
    - Ollama running locally (`ollama serve`) with a model already pulled
      (default: llama3.2:3b -- `ollama pull llama3.2:3b`, or pass -Model
      to point at whatever you actually have). Deliberately a small model:
      writing a commit message doesn't need 26B-parameter reasoning, and a
      small model turns this from a ~30-45s wait into single-digit
      seconds. If the output quality isn't good enough, try something a
      bit bigger (e.g. qwen2.5:7b) before reaching for a large one again --
      see the runbook's 2026-08-27 latency entries for the numbers that
      drove this.

  Nothing here ever leaves your machine -- the diff is sent to localhost
  only, never to a third-party API. Matches the project's own
  unexposed-by-default convention (see runbook, 2026-08-27 entries).

  `git add -A` stages new/modified/deleted files respecting .gitignore, so
  claude/, *.env.local, *.key etc. are never picked up -- same guardrail
  that protects a manual `git add .`. This adds no scanning beyond what
  .gitignore already excludes; it trusts the same rules the rest of the
  project does.

.PARAMETER Yes
  Skip the "does this look right?" confirmation prompt (needed for
  unattended/scheduled use).

.PARAMETER DryRun
  Do everything except `git commit`/`git push` -- prints the generated
  commit message so you can sanity-check the model's output before
  trusting it.

.PARAMETER Model
  Override the Ollama model for this run.

.PARAMETER OllamaUrl
  Override the Ollama base URL for this run.

.PARAMETER NumCtx
  Context window (tokens) explicitly requested from Ollama via the
  `options.num_ctx` request field, on top of the diff-size cap below.
  Without this, Ollama falls back to a small default (often 4096)
  regardless of what the model actually supports -- a ~12,000-char diff
  alone is already ~3,700 tokens, which leaves almost nothing for the
  model to answer with and produces a "done_reason: length, empty
  .response" failure (confirmed against this repo's own diffs: 3737 prompt
  tokens + 357 generated hit a ~4096 ceiling with zero of it landing in
  the final text -- the model was still mid-answer, likely still
  reasoning internally for a thinking-capable model, when it ran out of
  room). Raise this further if you still see that failure with a bigger
  model/diff; lower it only if your model's max context is actually
  smaller than this.

.PARAMETER KeepAlive
  How long Ollama keeps the model loaded in memory after this call before
  unloading it (e.g. "10m", "-1" for indefinitely). Reloading a large model
  from disk is the single most expensive part of a run (tens of seconds) --
  this just avoids paying that cost again if you're sitting at the y/N
  confirmation prompt for a while, or run this script again shortly after.
  Doesn't affect a cold first run.

.PARAMETER MaxSubjectChars
  Hard cap on the final commit message length, enforced in THIS SCRIPT, not
  just requested in the prompt. Added 2026-09-02: telling a small local
  model "under 50 characters total" in the prompt text is not enough on its
  own -- confirmed after this project's own Conventional-Commits prompt
  rewrite still produced long, multi-sentence output despite saying exactly
  that. Small models are unreliable at obeying a hard numeric constraint
  like a character count; the prompt below states this limit (so the model
  at least aims for something short) but Enforce-SubjectLength below is
  what actually guarantees it, by collapsing the response to one line and
  truncating at a word boundary if the model still went over. If you see a
  "Model's response was N chars" warning often, either the model isn't a
  good fit for this or the limit is set unrealistically low for it --
  raising -MaxSubjectChars is a legitimate fix too, not just a fallback.

.EXAMPLE
  .\scripts\purrbrews-commit.ps1

.EXAMPLE
  .\scripts\purrbrews-commit.ps1 -DryRun

.EXAMPLE
  .\scripts\purrbrews-commit.ps1 -Yes -Model qwen2.5:7b
#>
[CmdletBinding()]
param(
  [switch]$Yes,
  [switch]$DryRun,
  [string]$Model = "llama3.2:3b",
  [string]$OllamaUrl = "http://localhost:11434",
  [int]$NumCtx = 8192,
  [string]$KeepAlive = "10m",
  [int]$MaxSubjectChars = 50
)

$ErrorActionPreference = "Stop"

function Log  ($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Warn ($msg) { Write-Host "!! $msg" -ForegroundColor Yellow }
function Die  ($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Die "git not found." }

$repoRoot = $null
try {
  $repoRoot = (git rev-parse --show-toplevel 2>$null)
} catch {}
if (-not $repoRoot) { Die "Not inside a git repo." }
Set-Location $repoRoot

try {
  $tags = Invoke-RestMethod -Uri "$OllamaUrl/api/tags" -Method Get -TimeoutSec 5
} catch {
  Die "Can't reach Ollama at $OllamaUrl -- is it running? (ollama serve)"
}

$availableModels = @($tags.models | ForEach-Object { $_.name })
if ($availableModels -and ($availableModels -notcontains $Model)) {
  Warn "'$Model' isn't in Ollama's pulled-models list -- this is the most likely reason the next step fails."
  Warn "Available: $($availableModels -join ', ')"
  Warn "Pull it first (ollama pull $Model) or pass -Model with one of the names above."
}

# Diffs larger than this (chars) get truncated before being sent to the
# model -- a huge diff blows a local model's context window and produces a
# useless summary anyway. The FULL diff is still what gets committed; only
# what the model sees is capped. Tune to your model's context size.
$MaxDiffChars = 36000

# ---------------------------------------------------------------------------
# Stage everything, bail if there's nothing to do
# ---------------------------------------------------------------------------
Log "Staging changes (git add -A)"
git add -A

$stagedNames = git diff --cached --name-only
if (-not $stagedNames) {
  Log "Nothing staged -- working tree matches HEAD. Nothing to commit."
  exit 0
}

$diffStat = (git diff --cached --stat) -join "`n"
$diffFull = (git diff --cached) -join "`n"
$diffForModel = $diffFull
if ($diffForModel.Length -gt $MaxDiffChars) {
  Warn "Staged diff is $($diffForModel.Length) chars -- truncating to $MaxDiffChars for the model (the full diff is still what gets committed)."
  $diffForModel = $diffForModel.Substring(0, $MaxDiffChars) + "`n...[truncated for the model]"
}

Write-Host ""
Write-Host $diffStat

# ---------------------------------------------------------------------------
# Ollama call helper -- /api/generate, non-streaming, plain text in/out
# ---------------------------------------------------------------------------
function Invoke-Ollama([string]$Prompt) {
  $body = @{
    model = $Model
    prompt = $Prompt
    stream = $false
    keep_alive = $KeepAlive
    options = @{ num_ctx = $NumCtx }
  } | ConvertTo-Json -Depth 5

  # No try/catch swallowing here without inspecting the body first: Ollama's
  # error responses (e.g. "model not found") come back as a JSON body on a
  # non-2xx status. Invoke-RestMethod throws on those by default, but the
  # body is still recoverable via $_.ErrorDetails.Message -- surface it
  # instead of letting a raw stack trace (or worse, a silent empty string)
  # stand in for the real reason.
  try {
    $resp = Invoke-RestMethod -Uri "$OllamaUrl/api/generate" -Method Post -Body $body -ContentType "application/json"
  } catch {
    $msg = $_.Exception.Message
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
      try {
        $errBody = $_.ErrorDetails.Message | ConvertFrom-Json
        if ($errBody.error) { $msg = $errBody.error }
      } catch {}
    }
    Die "Request to Ollama failed: $msg"
  }

  if ($resp.error) { Die "Ollama returned an error: $($resp.error)" }

  if (-not $resp.response) {
    if ($resp.done_reason -eq "length") {
      Warn "Hit the context limit before producing any output (done_reason: length; ~$($resp.prompt_eval_count) prompt tokens + $($resp.eval_count) generated tokens, none of it landing in the final response -- likely spent entirely on internal reasoning before running out of room)."
      Warn "Fix: raise -NumCtx (currently $NumCtx) so there's headroom left after the prompt, or lower `$MaxDiffChars (currently $MaxDiffChars) so the prompt itself is smaller."
    } else {
      Warn "Ollama returned no .response and no .error -- raw reply below, for debugging:"
      Warn ($resp | ConvertTo-Json -Depth 5)
    }
  }
  return $resp.response
}

function Strip-Fences([string]$Text) {
  # Trim a leading ```lang and/or trailing ``` fence, if the model added one
  # despite being told not to -- small local models don't always follow
  # "no code fences" instructions.
  $t = $Text.Trim()
  $t = $t -replace '^```[a-zA-Z]*\r?\n', ''
  $t = $t -replace '\r?\n```\s*$', ''
  return $t.Trim()
}

Log "Asking $Model for a commit message"
$commitPrompt = @"
You are an expert developer assistant specialized in Git version control. Your task is to analyze the provided git diff and generate a super concise, professional commit message following the Conventional Commits specification. ### Rules:
1. Format: Use the structure ``<type>(<scope>): <short description in lowercase>``
2. Allowed Types: feat, fix, docs, style, refactor, test, chore, perf, ci, build.
3. Length: The entire message MUST be under $MaxSubjectChars characters total. This is a hard limit -- there is no room for a body, footer, or explanation of any kind, ever.
4. Tone: Use the imperative mood, present tense.
5. Content: Focus strictly on the single most important what of the change. Do not list every file changed or every detail -- pick the one thing that matters most and say only that.
6. Output: Return ONLY the final raw commit message string, as one line. Do not include markdown code blocks, quotes, introductions, reasoning, or explanations of any kind.

Example:
DIFF:
diff --git a/api/users.py b/api/users.py
+def get_user(id):
+    return db.query(User).get(id)
Output:
feat(api): add get_user endpoint

DIFF:
$diffForModel
"@
$commitMsgRaw = Strip-Fences (Invoke-Ollama $commitPrompt)
if (-not $commitMsgRaw) { Die "Model returned an empty commit message -- aborting rather than committing with nothing. Staged changes are left staged." }

function Enforce-SubjectLength([string]$Text, [int]$MaxChars) {
  # The actual fix for "the model wrote a huge commit message despite the
  # prompt saying under $MaxChars characters" (2026-09-02) -- a prompt
  # instruction alone doesn't reliably bound a small local model's output
  # length, no matter how the wording is tightened. This collapses
  # whatever came back to one line (a rambling multi-sentence answer from
  # a small model is padding, not a deliberate Conventional-Commits body --
  # see rule 3 above, which now says there's never room for one) and, if
  # it's still over the limit, truncates at the last word boundary so a
  # word never gets cut in half.
  $oneLine = ($Text -split '\r?\n' | Where-Object { $_.Trim() -ne '' }) -join ' '
  $oneLine = $oneLine.Trim()
  if ($oneLine.Length -le $MaxChars) { return $oneLine }
  $cut = $oneLine.Substring(0, $MaxChars)
  $lastSpace = $cut.LastIndexOf(' ')
  if ($lastSpace -gt 0) { $cut = $cut.Substring(0, $lastSpace) }
  return $cut.TrimEnd('.', ',', ';', ':', ' ')
}

$commitMsg = Enforce-SubjectLength $commitMsgRaw $MaxSubjectChars
if ($commitMsg.Length -lt $commitMsgRaw.Trim().Length) {
  Warn "$Model ignored the '$MaxSubjectChars characters' rule -- its raw response was $($commitMsgRaw.Trim().Length) chars. Truncated to fit; raw output below so you can judge whether the truncated version still makes sense, or whether to just write this one by hand."
  Warn "Raw model output: $commitMsgRaw"
}
if (-not $commitMsg) { Die "Model returned an empty commit message -- aborting rather than committing with nothing. Staged changes are left staged." }

Write-Host "`n----------------------------------------------------------------------"
Write-Host "Commit message:"
Write-Host $commitMsg
Write-Host "----------------------------------------------------------------------"

if ($DryRun) {
  Log "Dry run -- stopping before commit/push. Nothing committed. (Changes are still staged from git add -A -- unstage with 'git reset' if that's not what you want.)"
  exit 0
}

if (-not $Yes) {
  $reply = Read-Host "Commit and push with the message above? [y/N]"
  if ($reply -notmatch '^[Yy]$') {
    Warn "Aborted -- staged changes are left staged, nothing committed or pushed."
    exit 1
  }
}

# ---------------------------------------------------------------------------
# Commit, push. No runbook.md touched here -- see synopsis/description.
#
# Fixed 2026-09-01: this used to be `git commit -m "$commitMsg"`, which
# broke the moment the model's output contained a literal double-quote
# character (it happily did -- e.g. wrapping a phrase in quotes for
# emphasis, or a filename in backticks). PowerShell doesn't re-escape an
# embedded `"` when building the command line it hands to a native exe, so
# git.exe actually received something like `-m "feat: Add "` as the whole
# -m value, then every subsequent word in the message became its own bare
# argument -- which git interpreted as pathspecs, producing exactly the
# "pathspec 'in' did not match any file(s)" pileup this script hit on a
# real commit message ("Add "Ports in use on this host" table to both
# `stacks/sieve/README.md` and `stacks/silo/README.md`").
#
# Fix: never hand an arbitrary string through PowerShell's native-argument
# quoting at all. Write it to a temp file and use `git commit -F <file>`,
# which git reads byte-for-byte -- immune to quotes, backticks, or
# anything else the model puts in there. Tightened the prompt above too
# (no backticks/quotes) so the output looks like a normal commit subject,
# but the -F fix is what actually makes this safe regardless of what the
# model does.
# ---------------------------------------------------------------------------
$commitMsgFile = Join-Path ([System.IO.Path]::GetTempPath()) "purrbrews-commit-msg-$([guid]::NewGuid()).txt"
try {
  [System.IO.File]::WriteAllText($commitMsgFile, $commitMsg, [System.Text.UTF8Encoding]::new($false))
  git commit -F $commitMsgFile
} finally {
  Remove-Item -Path $commitMsgFile -ErrorAction SilentlyContinue
}
Log "Committed. Pushing..."
git push
Log "Done."
