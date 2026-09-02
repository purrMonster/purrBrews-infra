# generate-secrets.ps1 — the roastery-side half of the SOPS+age bridge for
# ristretto. Copied from stacks/silo/generate-secrets.ps1 2026-09-01 when
# ristretto's stack directory was first scaffolded (see the runbook's
# 2026-09-01 entry) — the mechanics below are identical to silo's own
# script and to every future node's copy of it; only $SecretsDir and the
# per-app secrets section differ per node. See stacks/silo/generate-secrets.ps1
# for the fuller rationale comments (idempotency, why SOPS+age instead of
# sieve's plain local generation, etc.) — not re-explained here to avoid
# drifting out of sync across five copies of the same header.
#
# Runs on roastery (Windows), per Section 19.6 ("no live coding on fleet
# nodes"). Fills in real values for ristretto's app secrets, encrypts each
# with the age PUBLIC key (via .sops.yaml), and leaves committable
# ciphertext at secrets/ristretto/<app>.sops.yaml. git add/commit/push those
# from here; ristretto then decrypts its own copy at deploy time
# (stacks/ristretto/decrypt-secrets.sh, needs the PRIVATE key).
#
# THIS FILE HAS NO APPS YET. ristretto's own app list isn't built out —
# see stacks/ristretto/README.md and the initiation doc for what's actually
# planned. Add one Set-SopsSecretIfAbsent block per secret as each app gets
# built, same pattern as stacks/silo/generate-secrets.ps1's own per-app
# section — copy the helper functions below as-is, they're generic.
#
# Requires `sops` and `age` on PATH:
#   winget install SecretsOPerationS.SOPS
#   winget install FiloSottile.age
#
# Usage: run from anywhere — resolves its own paths from this script's
# location.
#   .\generate-secrets.ps1

$ErrorActionPreference = "Stop"

$RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$SecretsDir = Join-Path $RepoRoot "secrets\ristretto"

foreach ($cmd in @("sops", "age")) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Error "'$cmd' not found on PATH — install it first (see this script's header) and re-run."
        exit 1
    }
}

function New-RandomSecret {
    # Same shape as sieve's rand() helper (openssl rand -base64 N) — a
    # cryptographically random value, base64-encoded so it's always a safe
    # single-line YAML/dotenv value with no quoting surprises.
    param([int]$Bytes = 32)
    $buf = New-Object byte[] $Bytes
    [Security.Cryptography.RandomNumberGenerator]::Fill($buf)
    return [Convert]::ToBase64String($buf)
}

function Set-SopsSecretIfAbsent {
    # Set-SopsSecretIfAbsent -SopsFile <path> -Key <NAME> [-Value <v> | -Prompt -PromptText <text>]
    #
    # Mirrors sieve's set_if_absent / prompt_if_placeholder: only ever adds
    # a MISSING key. Never overwrites a key that already has a value,
    # generated or hand-edited — re-running this script is always safe.
    param(
        [Parameter(Mandatory)] [string]$SopsFile,
        [Parameter(Mandatory)] [string]$Key,
        [string]$Value,
        [switch]$Prompt,
        [string]$PromptText,
        [string]$Placeholder = "REPLACE_ME"
    )

    $dir = Split-Path -Parent $SopsFile
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $existingLines = @()
    if (Test-Path $SopsFile) {
        $raw = & sops -d $SopsFile 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "  SKIP $Key — can't decrypt $SopsFile on this machine (no age private key here). Copy /etc/purrbrews/age/keys.txt here temporarily to edit an existing value, or run this from a node that already has it."
            return
        }
        $existingLines = $raw -split "`r?`n" | Where-Object { $_ -match '^\s*[A-Za-z_][A-Za-z0-9_]*\s*:' }
    }

    if ($existingLines | Where-Object { $_ -match "^\s*$Key\s*:" }) {
        return
    }

    if (-not $Value) {
        if ($Prompt -and [Environment]::UserInteractive) {
            $secure = Read-Host -Prompt $PromptText -AsSecureString
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            try {
                $Value = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
            } finally {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
            if ([string]::IsNullOrEmpty($Value)) {
                $Value = $Placeholder
                Write-Host "  (left blank — keeping placeholder; re-run once you have it)"
            }
        } else {
            $Value = $Placeholder
        }
    }

    $newLines = $existingLines + "${Key}: ${Value}"
    $tmp = New-TemporaryFile
    try {
        ($newLines -join "`n") | Set-Content -NoNewline -Path $tmp.FullName
        Copy-Item $tmp.FullName $SopsFile -Force
        & sops -e -i $SopsFile
        if ($LASTEXITCODE -ne 0) {
            throw "sops -e -i failed on $SopsFile — see its own error above."
        }
        Write-Host "  set $Key in $(Resolve-Path -Relative $SopsFile)"
    } finally {
        Remove-Item $tmp.FullName -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "==> ristretto secrets (secrets/ristretto/*.sops.yaml)"

# --- Per-app secrets go here ------------------------------------------
# One Set-SopsSecretIfAbsent call per secret value, added as each app gets
# built — see stacks/silo/generate-secrets.ps1's own per-app section for
# real worked examples (netalertx/speedtest-tracker/komodo). Nothing here
# yet: ristretto has no apps built out as of 2026-09-01.
#
#   Set-SopsSecretIfAbsent -SopsFile (Join-Path $SecretsDir "somesvc.sops.yaml") `
#     -Key "SOME_PASSWORD" -Value (New-RandomSecret 16)
#
# For a value that can't be randomly generated (an API token, etc.), use
# -Prompt instead of -Value:
#
#   Set-SopsSecretIfAbsent -SopsFile (Join-Path $SecretsDir "somesvc.sops.yaml") `
#     -Key "SOME_API_TOKEN" -Prompt -PromptText "Some service API token"
# ------------------------------------------------------------------------

Write-Host "`nDone. Encrypted files under secrets/ristretto/ are ciphertext — safe to 'git add', commit, and push."
Write-Host "Next, on ristretto: git pull, then ./decrypt-secrets.sh, then ./render-configs.sh."
