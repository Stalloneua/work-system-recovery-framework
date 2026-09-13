[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^ssh-ed25519\s+[A-Za-z0-9+/=]+(?:\s+.*)?$')]
    [string]$PublicKey,

    [ValidateRange(1, 65535)]
    [int]$Port = 22
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ActiveIpv4 {
    Get-NetIPAddress -AddressFamily IPv4 -AddressState Preferred |
        Where-Object {
            $_.IPAddress -ne '127.0.0.1' -and
            $_.IPAddress -notlike '169.254.*'
        } |
        Sort-Object InterfaceMetric, SkipAsSource, IPAddress |
        Select-Object -ExpandProperty IPAddress -Unique
}

if (-not (Test-IsAdministrator)) {
    $escapedPath = $PSCommandPath.Replace("'", "''")
    $escapedKey = $PublicKey.Replace("'", "''")
    $elevatedCommand = "& '$escapedPath' -PublicKey '$escapedKey' -Port $Port"
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($elevatedCommand))
    $process = Start-Process `
        -FilePath 'powershell.exe' `
        -Verb RunAs `
        -Wait `
        -PassThru `
        -ArgumentList '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encodedCommand
    exit $process.ExitCode
}

$capabilityName = 'OpenSSH.Server~~~~0.0.1.0'
$capability = Get-WindowsCapability -Online -Name $capabilityName
if ($capability.State -ne 'Installed') {
    Add-WindowsCapability -Online -Name $capabilityName | Out-Null
}

$sshdPath = Join-Path $env:WINDIR 'System32\OpenSSH\sshd.exe'
if (-not (Test-Path -LiteralPath $sshdPath)) {
    throw "OpenSSH Server installation completed without creating $sshdPath."
}

$service = Get-Service -Name sshd -ErrorAction Stop
Set-Service -Name sshd -StartupType Automatic

$firewallRuleName = 'OpenSSH-Server-In-TCP'
$firewallRule = Get-NetFirewallRule -Name $firewallRuleName -ErrorAction SilentlyContinue
if ($null -eq $firewallRule) {
    New-NetFirewallRule `
        -Name $firewallRuleName `
        -DisplayName 'OpenSSH SSH Server (sshd)' `
        -Enabled True `
        -Direction Inbound `
        -Protocol TCP `
        -Action Allow `
        -LocalPort $Port | Out-Null
} else {
    Set-NetFirewallRule -Name $firewallRuleName -Enabled True -Direction Inbound -Action Allow | Out-Null
    Set-NetFirewallPortFilter -AssociatedNetFirewallRule $firewallRule -Protocol TCP -LocalPort $Port | Out-Null
}

$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentUser = $currentIdentity.Name
$isAdministrator = Test-IsAdministrator

if ($isAdministrator) {
    $authorizedKeysPath = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
} else {
    $authorizedKeysPath = Join-Path $env:USERPROFILE '.ssh\authorized_keys'
}

$authorizedKeysDirectory = Split-Path -Parent $authorizedKeysPath
New-Item -ItemType Directory -Path $authorizedKeysDirectory -Force | Out-Null

$normalizedKey = ($PublicKey -replace '\s+', ' ').Trim()
$existingKeys = @()
if (Test-Path -LiteralPath $authorizedKeysPath) {
    $existingKeys = @(Get-Content -LiteralPath $authorizedKeysPath -ErrorAction Stop | ForEach-Object { $_.Trim() })
}
if ($existingKeys -notcontains $normalizedKey) {
    Add-Content -LiteralPath $authorizedKeysPath -Value $normalizedKey -Encoding ascii
}

if ($isAdministrator) {
    & icacls.exe $authorizedKeysPath /inheritance:r | Out-Null
    & icacls.exe $authorizedKeysPath /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null
} else {
    $userSid = $currentIdentity.User.Value
    & icacls.exe $authorizedKeysPath /inheritance:r | Out-Null
    & icacls.exe $authorizedKeysPath /grant:r "*${userSid}:F" '*S-1-5-18:F' | Out-Null
}

$configPath = Join-Path $env:ProgramData 'ssh\sshd_config'
if (-not (Test-Path -LiteralPath $configPath)) {
    throw "OpenSSH Server did not create $configPath."
}

$configText = Get-Content -LiteralPath $configPath -Raw
if ($Port -ne 22 -and $configText -notmatch '(?m)^\s*Port\s+') {
    Add-Content -LiteralPath $configPath -Value "`r`nPort $Port" -Encoding ascii
}
if ($configText -notmatch '(?im)^\s*PubkeyAuthentication\s+yes\s*$') {
    Add-Content -LiteralPath $configPath -Value "`r`nPubkeyAuthentication yes" -Encoding ascii
}
if ($isAdministrator -and $configText -notmatch '(?im)^\s*AuthorizedKeysFile\s+__PROGRAMDATA__/ssh/administrators_authorized_keys\s*$') {
    Add-Content -LiteralPath $configPath -Value @"

Match Group administrators
       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
"@ -Encoding ascii
}

& $sshdPath -t
if ($LASTEXITCODE -ne 0) {
    throw "sshd configuration validation failed with exit code $LASTEXITCODE."
}

if ($service.Status -eq 'Running') {
    Restart-Service -Name sshd -Force
} else {
    Start-Service -Name sshd
}

$tcpClient = [Net.Sockets.TcpClient]::new()
try {
    $connectTask = $tcpClient.ConnectAsync('127.0.0.1', $Port)
    $localPortOpen = $connectTask.Wait([TimeSpan]::FromSeconds(5)) -and $tcpClient.Connected
} finally {
    $tcpClient.Dispose()
}

$tailscaleIpv4 = $null
$tailscale = Get-Command tailscale.exe -ErrorAction SilentlyContinue
if ($null -ne $tailscale) {
    try {
        $tailscaleIpv4 = (& $tailscale.Source ip -4 2>$null | Select-Object -First 1).Trim()
    } catch {
        $tailscaleIpv4 = $null
    }
}

$result = [ordered]@{
    status = if ($localPortOpen) { 'ready' } else { 'failed' }
    hostname = $env:COMPUTERNAME
    username = $currentUser
    isAdministrator = $isAdministrator
    lanIpv4 = @(Get-ActiveIpv4)
    tailscaleIpv4 = $tailscaleIpv4
    sshPort = $Port
    sshdState = (Get-Service -Name sshd).Status.ToString()
    firewallRule = $firewallRuleName
    authorizedKeysPath = $authorizedKeysPath
    sshdConfigTest = 'passed'
    localPortTest = $localPortOpen
}

$result | ConvertTo-Json -Depth 4
if (-not $localPortOpen) {
    exit 1
}
