[CmdletBinding()]
param(
    [string]$RemoteName = 'work-drive',
    [string]$RemotePath = 'Work System/00 Recovery/plain-foundation',
    [ValidateSet('Critical','Foundation','Full')]
    [string]$Profile = 'Foundation',
    [switch]$RegisterSchedule,
    [string]$ScheduleTime = '02:00'
)

$ErrorActionPreference = 'Stop'
$stateRoot = Join-Path $env:LOCALAPPDATA 'WorkSystemRecovery'
$configPath = Join-Path $stateRoot 'config.json'
New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null

if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) {
    throw 'rclone is not installed.'
}

$remotes = @(& rclone listremotes --log-level ERROR | ForEach-Object { $_.TrimEnd(':') })
if ($RemoteName -notin $remotes) {
    Write-Host "Create the Google Drive remote '$RemoteName'. Browser OAuth approval is required once."
    & rclone config create $RemoteName drive config_is_local true --log-level ERROR
    if ($LASTEXITCODE -ne 0) { throw 'rclone Google Drive configuration failed.' }
}

& rclone lsd "${RemoteName}:" --log-level ERROR | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Cannot read Google Drive remote '$RemoteName'." }

[ordered]@{
    schema_version = 2
    backup_mode = 'plain-rclone'
    remote_name = $RemoteName
    remote_path = $RemotePath.Trim('/')
    profile = $Profile
    package_root = $PSScriptRoot
    created_at = (Get-Date).ToString('o')
} | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding utf8

& "$PSScriptRoot\Invoke-WorkSystemBackup.ps1" -Profile $Profile -Check
if ($LASTEXITCODE -ne 0) { throw 'Initial plain Google Drive backup failed.' }

if ($RegisterSchedule) {
    & "$PSScriptRoot\Register-WorkSystemScheduledTasks.ps1" -BackupTime $ScheduleTime
}

Write-Output "Plain Google Drive foundation backup is initialized at ${RemoteName}:$RemotePath"
