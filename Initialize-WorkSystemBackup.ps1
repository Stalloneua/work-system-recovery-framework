[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Repository,
    [ValidateSet('Critical','Foundation','Full')]
    [string]$Profile = 'Foundation',
    [switch]$RegisterSchedule,
    [string]$ScheduleTime = '02:00'
)

$ErrorActionPreference = 'Stop'
$stateRoot = Join-Path $env:LOCALAPPDATA 'WorkSystemRecovery'
$configPath = Join-Path $stateRoot 'config.json'
$passwordPath = Join-Path $stateRoot 'restic-password.xml'
New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null

if (-not (Get-Command restic -ErrorAction SilentlyContinue)) {
    throw 'restic is not installed.'
}

$secure = Read-Host 'Enter the restic repository password; store a recovery copy in a password manager' -AsSecureString
if ($secure.Length -lt 16) {
    throw 'Use a passphrase of at least 16 characters.'
}

$secure | ConvertFrom-SecureString | Set-Content -LiteralPath $passwordPath -Encoding ascii
$plain = [System.Net.NetworkCredential]::new('', $secure).Password
$env:RESTIC_REPOSITORY = $Repository
$env:RESTIC_PASSWORD = $plain

try {
    & restic snapshots --json *> $null
    if ($LASTEXITCODE -ne 0) {
        & restic init
        if ($LASTEXITCODE -ne 0) { throw 'restic init failed.' }
    }

    [ordered]@{
        schema_version = 1
        repository = $Repository
        profile = $Profile
        package_root = $PSScriptRoot
        created_at = (Get-Date).ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding utf8

    & "$PSScriptRoot\Invoke-WorkSystemBackup.ps1"
    if ($RegisterSchedule) {
        & "$PSScriptRoot\Register-WorkSystemScheduledTasks.ps1" -BackupTime $ScheduleTime
    }
} finally {
    Remove-Item Env:RESTIC_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:RESTIC_REPOSITORY -ErrorAction SilentlyContinue
    $plain = $null
}
