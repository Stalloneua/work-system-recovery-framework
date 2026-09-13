[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Repository,
    [string]$Target = "$([Environment]::GetFolderPath('MyDocuments'))\WorkSystem-Restore-Staging",
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command restic -ErrorAction SilentlyContinue)) { throw 'restic is not installed.' }
$secure = Read-Host 'Enter the restic repository password' -AsSecureString
$plain = [System.Net.NetworkCredential]::new('', $secure).Password
$env:RESTIC_REPOSITORY = $Repository
$env:RESTIC_PASSWORD = $plain

try {
    New-Item -ItemType Directory -Force -Path $Target | Out-Null
    & restic restore latest --target $Target
    if ($LASTEXITCODE -ne 0) { throw 'restic restore failed.' }

    $vault = Get-ChildItem -LiteralPath $Target -Filter 'Work Management System.md' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $architecture = Get-ChildItem -LiteralPath $Target -Filter 'Cross-machine Continuity and One-command Recovery Architecture.md' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $vault -or -not $architecture) { throw 'Recovery validation failed: required operating notes are missing.' }

    if ($Apply) {
        $documents = [Environment]::GetFolderPath('MyDocuments')
        $restoredDocuments = Join-Path $Target ((Split-Path -Leaf $documents))
        if (-not (Test-Path -LiteralPath $restoredDocuments)) {
            $restoredDocuments = Get-ChildItem -LiteralPath $Target -Directory -Recurse | Where-Object { $_.Name -eq 'Obsidian Vault' } | Select-Object -First 1 | ForEach-Object Parent
        }
        if (-not $restoredDocuments) { throw 'Could not locate restored Documents root.' }
        & robocopy $restoredDocuments $documents /E /COPY:DAT /DCOPY:DAT /R:2 /W:2 /XJ
        if ($LASTEXITCODE -ge 8) { throw "robocopy apply failed with exit code $LASTEXITCODE" }
    }

    Write-Output "Restore verified at $Target"
} finally {
    Remove-Item Env:RESTIC_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:RESTIC_REPOSITORY -ErrorAction SilentlyContinue
    $plain = $null
}
