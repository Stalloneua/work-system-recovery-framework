[CmdletBinding()]
param(
    [ValidateSet('Critical','Foundation','Full')]
    [string]$Profile = 'Foundation',
    [string]$OutputRoot = (Join-Path $env:LOCALAPPDATA 'WorkSystemScratch\ConnectorSnapshots'),
    [string]$BackupId = (Get-Date -Format 'yyyyMMdd-HHmmss'),
    [long]$MaxArchiveBytes = 83886080
)

$ErrorActionPreference = 'Stop'
$node = Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1
if (-not $node) { throw 'Node.js is not installed.' }

$exporter = Join-Path $PSScriptRoot 'Export-WorkSystemPlainSnapshot.mjs'
if (-not (Test-Path -LiteralPath $exporter)) { throw "Missing exporter: $exporter" }

& $node $exporter `
    --profile $Profile `
    --output-root $OutputRoot `
    --backup-id $BackupId `
    --max-archive-bytes $MaxArchiveBytes
if ($LASTEXITCODE -ne 0) { throw "Connector snapshot export failed with exit code $LASTEXITCODE." }
