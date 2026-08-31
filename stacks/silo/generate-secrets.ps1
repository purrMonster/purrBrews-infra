# generate-secrets.ps1 — the roastery-side half of the SOPS+age bridge
# (decided 2026-08-31: silo onward uses SOPS+age, unlike sieve's stack —
# see ../../.sops.yaml and ../../secrets/README.md for why the split).
#
# Runs on roastery (Windows), per Section 19.6 ("no live coding on fleet
# nodes" — all development happens on roastery/americano, fleet nodes only
# pull already-committed code). Fills in real values for silo's app
# secrets, encrypts each with the age PUBLIC key (via .sops.yaml — no
# private key needed for this half), and leaves committable ciphertext at
# secrets/silo/<app>.sops.yaml. You git add/commit/push those from here;
# each node then decrypts its own copy at deploy time
# (stacks/silo/decrypt-secrets.sh, needs the PRIVATE key, which stays off
# roastery unless you deliberately copy it here to edit an existing secret
# — see the -Prompt/idempotency notes below).
#
# Idempotent, same rule as stacks/sieve/generate-secrets.sh: a key that
# already holds a real value is never touched, so re-running this later
# (e.g. once a new app needs a new secret) is always safe. The difference
# from sieve's version is HOW that's checked — sieve just greps a plaintext
# file; this has to `sops -d` the existing ciphertext first. If that
# decrypt fails (no private key present on this machine), the script
# refuses to touch that file rather than guessing — silently regenerating
# e.g. a database password that's already in use elsewhere would break a
# running service, not just create a redundant value.
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
$SecretsDir = Join-Path $RepoRoot "secrets\silo"

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

Write-Host "==> silo secrets (secrets/silo/*.sops.yaml)"

# --- Per-app secrets go here ------------------------------------------
# Nothing yet — silo's apps (Unbound, CrowdSec, NetAlertX, Speedtest
# Tracker, Komodo, Scrutiny, Diun) haven't been built. Add one
# Set-SopsSecretIfAbsent call per secret value as each app gets built,
# same pattern as stacks/sieve/generate-secrets.sh uses per app. Example,
# for when Komodo needs a webhook secret:
#
#   Set-SopsSecretIfAbsent -SopsFile (Join-Path $SecretsDir "komodo.sops.yaml") `
#     -Key "KOMODO_WEBHOOK_SECRET" -Value (New-RandomSecret 32)
#
# For a value that can't be randomly generated (an API token, etc.), use
# -Prompt instead of -Value, same as sieve's CF_DNS_API_TOKEN/TUNNEL_TOKEN:
#
#   Set-SopsSecretIfAbsent -SopsFile (Join-Path $SecretsDir "somesvc.sops.yaml") `
#     -Key "SOME_API_TOKEN" -Prompt -PromptText "Some service API token"
# ------------------------------------------------------------------------

Write-Host "`nDone. Encrypted files under secrets/silo/ are ciphertext — safe to 'git add', commit, and push."
Write-Host "Next, on silo: git pull, then ./decrypt-secrets.sh, then ./render-configs.sh."
