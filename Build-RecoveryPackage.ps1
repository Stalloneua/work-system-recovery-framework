[CmdletBinding()]
param([string]$OutputDirectory = "$PSScriptRoot\dist")

$ErrorActionPreference = 'Stop'
& "$PSScriptRoot\New-ChatOrganizationManifest.ps1" | Out-Null
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$files = Get-ChildItem -LiteralPath $PSScriptRoot -File | Where-Object { $_.Name -notin @('package-manifest.json') }
$manifest = [ordered]@{
    schema_version = 1
    created_at = (Get-Date).ToString('o')
    files = @($files | Sort-Object Name | ForEach-Object {
        [ordered]@{ name = $_.Name; bytes = $_.Length; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash }
    })
}
$manifestPath = Join-Path $PSScriptRoot 'package-manifest.json'
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8

$zip = Join-Path $OutputDirectory 'work-system-recovery.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
$packageFiles = Get-ChildItem -LiteralPath $PSScriptRoot -File
Compress-Archive -LiteralPath $packageFiles.FullName -DestinationPath $zip -CompressionLevel Optimal

[ordered]@{
    path = $zip
    bytes = (Get-Item -LiteralPath $zip).Length
    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash
} | ConvertTo-Json
