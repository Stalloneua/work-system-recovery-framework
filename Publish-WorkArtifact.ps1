[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,
    [Parameter(Mandatory)]
    [ValidatePattern('^DIR-\d{3}$')]
    [string]$DirectionId,
    [Parameter(Mandatory)]
    [ValidatePattern('^PRJ-\d{3}$')]
    [string]$ProjectId,
    [ValidateSet('Deliverables','Sources','Exports')]
    [string]$Category = 'Deliverables',
    [string]$RemoteName = 'work-drive'
)

$ErrorActionPreference = 'Stop'
$file = Get-Item -LiteralPath $Path
if ($file.PSIsContainer) { throw 'Publish one final file at a time.' }
if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) { throw 'rclone is not installed.' }

$remotePath = "${RemoteName}:Work System/10 Directions/$DirectionId/$ProjectId/$Category/$($file.Name)"
& rclone copyto $file.FullName $remotePath --create-empty-src-dirs --log-level ERROR
if ($LASTEXITCODE -ne 0) { throw 'Artifact upload failed.' }

$localMd5 = (Get-FileHash -Algorithm MD5 -LiteralPath $file.FullName).Hash.ToLowerInvariant()
$remoteLine = (& rclone md5sum $remotePath --log-level ERROR | Select-Object -First 1)
if ($LASTEXITCODE -ne 0 -or -not $remoteLine) { throw 'Could not verify remote artifact hash.' }
$remoteMd5 = ($remoteLine -split '\s+')[0].ToLowerInvariant()
if ($localMd5 -ne $remoteMd5) { throw 'Remote artifact hash does not match the local file.' }

$marker = [ordered]@{
    schema_version = 1
    local_path = $file.FullName
    remote_path = $remotePath
    md5 = $localMd5
    direction_id = $DirectionId
    project_id = $ProjectId
    published_at = (Get-Date).ToString('o')
    verified = $true
    drive_file_id = $null
    drive_url = $null
}
$markerPath = "$($file.FullName).published.json"
$marker | ConvertTo-Json | Set-Content -LiteralPath $markerPath -Encoding utf8
Write-Output $markerPath
Write-Warning 'Resolve the Drive file ID/URL with the Google Drive connector and register it in Files before marking a deliverable complete.'
