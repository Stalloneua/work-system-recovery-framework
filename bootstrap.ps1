[CmdletBinding()]
param(
    [string]$Repository = 'rclone:work-drive:Work System/00 Recovery/restic-foundation',
    [string]$RemoteName = 'work-drive',
    [ValidateSet('Plain','Encrypted')]
    [string]$BackupMode = 'Plain',
    [string]$PlainRemotePath = 'Work System/00 Recovery/plain-foundation',
    [string]$Target = "$([Environment]::GetFolderPath('MyDocuments'))\WorkSystem-Restore-Staging",
    [switch]$Apply,
    [switch]$SkipPackages
)

$ErrorActionPreference = 'Stop'

if (-not $SkipPackages) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'winget is required.' }
    $packages = @(
        @{ Id = 'Git.Git'; Command = 'git' },
        @{ Id = 'OpenAI.Codex'; Command = 'codex' },
        @{ Id = 'Obsidian.Obsidian'; Command = 'obsidian' },
        @{ Id = 'Syncthing.Syncthing'; Command = 'syncthing' },
        @{ Id = 'Rclone.Rclone'; Command = 'rclone' }
    )
    if ($BackupMode -eq 'Encrypted') { $packages += @{ Id = 'restic.restic'; Command = 'restic' } }
    foreach ($package in $packages) {
        if (-not (Get-Command $package.Command -ErrorAction SilentlyContinue)) {
            & winget install --id $package.Id --exact --accept-package-agreements --accept-source-agreements --silent
            if ($LASTEXITCODE -ne 0) { throw "Failed to install $($package.Id)." }
        }
    }
}

if ($BackupMode -eq 'Plain' -or $Repository.StartsWith('rclone:')) {
    $remotes = @(& rclone listremotes | ForEach-Object { $_.TrimEnd(':') })
    if ($RemoteName -notin $remotes) {
        Write-Host "Configure Google Drive remote '$RemoteName'. Browser OAuth approval is required once."
        & rclone config create $RemoteName drive config_is_local true
        if ($LASTEXITCODE -ne 0) { throw 'rclone configuration failed.' }
    }
    & rclone lsd "${RemoteName}:" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Cannot read rclone remote '$RemoteName'." }
}

& "$PSScriptRoot\Restore-WorkSystem.ps1" -Repository $Repository -BackupMode $BackupMode -RemoteName $RemoteName -PlainRemotePath $PlainRemotePath -Target $Target -Apply:$Apply
if ($LASTEXITCODE -ne 0) { throw 'Restore step failed.' }

& "$PSScriptRoot\Test-DisasterRecovery.ps1" -Repository $Repository -ExistingRestoreTarget $Target -SkipBackupHealth
if ($LASTEXITCODE -ne 0) { throw 'Validation step failed.' }

Write-Output 'Technical restore is complete. Sign in to Codex/ChatGPT, open the restored Vault, and then open the Portfolio Dashboard and active recovery task. Approve Syncthing only when live replication is enabled.'
