[CmdletBinding()]
param(
    [string]$SourceManifest = "$([Environment]::GetFolderPath('MyDocuments'))\Codex\2026-09-09\https-docs-google-com-document-d\unified_active_chat_capture_manifest_20260911.json",
    [string]$OutputPath = "$PSScriptRoot\chat-organization-manifest.json"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $SourceManifest)) {
    throw "Source chat manifest not found: $SourceManifest"
}

$source = Get-Content -Raw -LiteralPath $SourceManifest | ConvertFrom-Json
$projects = Get-Content -Raw -LiteralPath "$PSScriptRoot\chatgpt-projects.json" | ConvertFrom-Json
$sidebar = Get-Content -Raw -LiteralPath "$PSScriptRoot\sidebar-state.json" | ConvertFrom-Json

$records = foreach ($item in $source.records) {
    [ordered]@{
        thread_id = $item.id
        title = $item.title
        kind = $item.kind
        hosts = @($item.hosts)
        direction_id = $item.primarydir
        project_id = $item.primaryPRJ
        task_ids = @($item.TSK)
        capture_path = $item.canonicalvaultpath
        source_paths = @($item.sourcepaths)
        latest_timestamp = $item.latesttimestamp
        chatgpt_project_id = $null
        codex_workspace = $null
        desired_section = if ($item.primaryPRJ) { $item.primaryPRJ } elseif ($item.primarydir) { $item.primarydir } else { 'Inbox' }
        pinned = @($sidebar.pinned_thread_ids) -contains $item.id
        confidence = $item.confidence
    }
}

$output = [ordered]@{
    schema_version = 1
    generated_at = (Get-Date).ToString('o')
    classification_source = 'Central tracker + Obsidian reconstructable capture manifest'
    ui_state_source = 'Codex app snapshot; UI grouping is a restorable view, not source of truth'
    record_count = @($records).Count
    chatgpt_projects = @($projects.projects)
    sidebar_state = $sidebar
    records = @($records)
}

$output | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding utf8
Write-Output $OutputPath
