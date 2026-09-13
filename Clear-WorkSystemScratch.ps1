[CmdletBinding(SupportsShouldProcess)]
param(
    [int]$RetentionDays = 7,
    [string]$ScratchRoot = "$env:LOCALAPPDATA\WorkSystemScratch"
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $ScratchRoot)) { return }
$resolvedRoot = (Resolve-Path -LiteralPath $ScratchRoot).Path
$expectedRoot = [System.IO.Path]::GetFullPath("$env:LOCALAPPDATA\WorkSystemScratch")
if (-not $resolvedRoot.Equals($expectedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'ScratchRoot must be the canonical WorkSystemScratch directory.'
}

$cutoff = (Get-Date).AddDays(-$RetentionDays)
$markers = Get-ChildItem -LiteralPath $resolvedRoot -Filter '*.published.json' -File -Recurse
foreach ($markerFile in $markers) {
    $marker = Get-Content -Raw -LiteralPath $markerFile.FullName | ConvertFrom-Json
    if (-not $marker.verified -or -not $marker.remote_path -or ([datetime]$marker.published_at) -gt $cutoff) { continue }
    $localPath = [System.IO.Path]::GetFullPath([string]$marker.local_path)
    if (-not $localPath.StartsWith($resolvedRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
    if (Test-Path -LiteralPath $localPath) {
        $currentMd5 = (Get-FileHash -Algorithm MD5 -LiteralPath $localPath).Hash.ToLowerInvariant()
        if ($currentMd5 -ne [string]$marker.md5) { continue }
        $remoteLine = (& rclone md5sum ([string]$marker.remote_path) | Select-Object -First 1)
        if ($LASTEXITCODE -ne 0 -or -not $remoteLine) { continue }
        $remoteMd5 = ($remoteLine -split '\s+')[0].ToLowerInvariant()
        if ($remoteMd5 -ne $currentMd5) { continue }
        if ($PSCmdlet.ShouldProcess($localPath, 'Delete verified published scratch artifact')) {
            Remove-Item -LiteralPath $localPath -Force
        }
    }
    if ($PSCmdlet.ShouldProcess($markerFile.FullName, 'Delete publication marker')) {
        Remove-Item -LiteralPath $markerFile.FullName -Force
    }
}
