#requires -Version 7.0
# =====================================================================
# Payor Demo - end-to-end Fabric deployment pack
#
# Creates: Workspace -> Folders -> Lakehouse -> Tables -> Semantic Model
#          -> Ontology -> Fabric Data Agent -> Notebook -> Data Pipeline
#
# Seller edits ONLY the two lines below, then runs:
#   pwsh -ExecutionPolicy Bypass -File .\deploy.ps1
#
# No GUID is hardcoded. All runtime IDs are resolved after creation.
#
# FOLDERS
#   Items cannot be moved between folders after creation ('fab mv' returns
#   UnsupportedCommand), so every item is created directly into its folder.
#   CLI items use a folder path segment; REST-created items (ontology,
#   data agent) carry a folderId in the create envelope.
# =====================================================================

# --- the only lines anyone edits ---
$workspace = "Payor"
$capacity  = "f2westuscapacityq2"
# -----------------------------------

$ErrorActionPreference = "Continue"
$guidRx = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

# --- folder layout ---------------------------------------------------
$folderSources     = "01 Sources"
$folderIngestion   = "02 Ingestion"
$folderInsights    = "03 Insights"
$folderOperational = "04 Operational"

$allFolders = @($folderSources, $folderIngestion, $folderInsights, $folderOperational)

# --- item names ------------------------------------------------------
$lakehouseName = "payor_lh"
$modelName     = "caldova_payor_model"
$ontologyName  = "caldova_payor_ontology"
$agentName     = "caldova_payor_agent"
$notebookName  = "NB_Payor_Demo"
$pipelineName  = "PL_Ingest_Enrollment"

function Stop-Deployment {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host $Message -ForegroundColor Red
    exit 1
}

function Get-FabId {
    param([Parameter(Mandatory)][string]$Path)
    $raw = (fab get $Path -q id 2>&1 | Out-String).Trim().Trim('"')
    if ($raw -match $guidRx) { return $raw }
    return $null
}

function Get-OperationId {
    param([Parameter(Mandatory)][string]$Response)
    if ($Response -match '(?i)"x-ms-operation-id"\s*:\s*"([^"]+)"') { return $Matches[1] }
    if ($Response -match 'operations/([0-9a-fA-F\-]{36})') { return $Matches[1] }
    return $null
}

function Wait-FabricOperation {
    param(
        [Parameter(Mandatory)][string]$OperationId,
        [int]$TimeoutSeconds = 300
    )

    $status = "Running"
    $waited = 0
    while ($status -notin @("Succeeded", "Failed", "Cancelled", "Canceled") -and $waited -lt $TimeoutSeconds) {
        Start-Sleep -Seconds 10
        $waited += 10
        $op = fab api -X get "operations/$OperationId" 2>&1 | Out-String
        if ($op -match '"status"\s*:\s*"([^"]+)"') { $status = $Matches[1] }
        Write-Host "  [$waited s] $status" -ForegroundColor DarkGray
    }
    return $status
}

function Write-JsonNoBom {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Path
    )
    $json = $Object | ConvertTo-Json -Depth 50
    [System.IO.File]::WriteAllText(
        $Path,
        $json,
        [System.Text.UTF8Encoding]::new($false)
    )
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -eq 0) { Stop-Deployment "Runtime JSON is empty: $Path" }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Stop-Deployment "Runtime JSON has a UTF-8 BOM: $Path"
    }
}

function Assert-FileExists {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Stop-Deployment "Required file not found: $Path"
    }
}

# ---------------------------------------------------------------------
# 0. PREREQUISITES + AUTHENTICATION
# ---------------------------------------------------------------------
if (-not (Get-Command fab -ErrorAction SilentlyContinue)) {
    Stop-Deployment "Fabric CLI not found. Install Python 3.12, then run: pip install ms-fabric-cli"
}

$requiredFiles = @(
    ".\data\applications.csv",
    ".\data\contacts.csv",
    ".\data\eligibility.csv",
    ".\data\plans.csv",
    ".\fabric\caldova_payor_model\definition\model.tmdl",
    ".\fabric\caldova_payor_ontology\create-ontology-envelope.json",
    ".\fabric\caldova_payor_agent\create-agent-envelope.json",
    ".\fabric\pl_ingest_enrollment\pipeline-content.json"
)
foreach ($file in $requiredFiles) { Assert-FileExists $file }

fab auth login
fab auth status
Read-Host "Correct tenant shown above? Press Enter to continue (Ctrl+C to abort)"

# folders are hidden from 'fab ls' unless this is enabled
fab config set folder_listing_enabled true | Out-Null

# ---------------------------------------------------------------------
# 1. WORKSPACE
# ---------------------------------------------------------------------
Write-Host "`nCreating workspace..." -ForegroundColor Yellow
fab create "$workspace.Workspace" -P capacityname=$capacity

$wsId = Get-FabId "$workspace.Workspace"
if ($wsId -notmatch $guidRx) {
    Stop-Deployment "Workspace was not created or its ID could not be resolved. The workspace name may already exist."
}
Write-Host "workspaceId = $wsId" -ForegroundColor Cyan

# ---------------------------------------------------------------------
# 2. FOLDERS
# Created before any item, because items cannot be moved afterwards.
# ---------------------------------------------------------------------
Write-Host "`nCreating folders..." -ForegroundColor Yellow
$folderIds = @{}

foreach ($f in $allFolders) {
    fab create "$workspace.Workspace/$f.Folder"
    $fid = Get-FabId "$workspace.Workspace/$f.Folder"
    if ($fid -notmatch $guidRx) {
        Stop-Deployment "Folder '$f' was not created or its ID could not be resolved."
    }
    $folderIds[$f] = $fid
    Write-Host "  $f = $fid" -ForegroundColor Cyan
}

# --- canonical item paths (folder segment included) ------------------
$lhPath    = "$workspace.Workspace/$folderSources.Folder/$lakehouseName.Lakehouse"
$modelPath = "$workspace.Workspace/$folderInsights.Folder/$modelName.SemanticModel"
$nbPath    = "$workspace.Workspace/$folderIngestion.Folder/$notebookName.Notebook"
$pipePath  = "$workspace.Workspace/$folderIngestion.Folder/$pipelineName.DataPipeline"

# ---------------------------------------------------------------------
# 3. LAKEHOUSE
# Do not enable schemas because schema-enabled lakehouses break this
# deployment pack's 'fab table load' paths.
# ---------------------------------------------------------------------
Write-Host "`nCreating lakehouse in '$folderSources'..." -ForegroundColor Yellow
fab create $lhPath

$lhId = Get-FabId $lhPath
if ($lhId -notmatch $guidRx) {
    Stop-Deployment "Lakehouse was not created or its ID could not be resolved."
}
Write-Host "lakehouseId = $lhId" -ForegroundColor Cyan

# ---------------------------------------------------------------------
# 4. UPLOAD CSV FILES
# ---------------------------------------------------------------------
$tables = @("applications", "contacts", "eligibility", "plans")
foreach ($t in $tables) {
    Write-Host "Uploading $t.csv..." -ForegroundColor DarkGray
    fab cp ".\data\$t.csv" "$lhPath/Files/$t.csv"
}

# ---------------------------------------------------------------------
# 5. LOAD TABLES (SERIAL + RETRY FOR F2 CAPACITY THROTTLING)
# ---------------------------------------------------------------------
foreach ($t in $tables) {
    $ok = $false
    for ($i = 1; $i -le 5 -and -not $ok; $i++) {
        Write-Host "Loading table '$t' (attempt $i)..." -ForegroundColor Yellow
        $out = fab table load "$lhPath/Tables/$t" --file "$lhPath/Files/$t.csv" 2>&1 | Out-String
        Write-Host $out

        if ($out -match "TooManyRequestsForCapacity|status.?code.?430|\b430\b") {
            Write-Host "  Capacity busy. Waiting 90 seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds 90
        }
        elseif ($out -match "(?i)error|failed|invalid") {
            Write-Host "  Load command reported an error." -ForegroundColor Yellow
            if ($i -lt 5) { Start-Sleep -Seconds 30 }
        }
        else {
            $ok = $true
            Write-Host "  '$t' loaded." -ForegroundColor Green
            Start-Sleep -Seconds 45
        }
    }
    if (-not $ok) {
        Stop-Deployment "FAILED to load '$t'. Aborting because downstream items would be invalid or empty."
    }
}

Write-Host "`nVerifying tables..." -ForegroundColor Cyan
$tableList = fab ls "$lhPath/Tables" 2>&1 | Out-String
Write-Host $tableList
foreach ($t in $tables) {
    if ($tableList -notmatch "(?im)\b$([regex]::Escape($t))\b") {
        Stop-Deployment "Table verification failed. '$t' was not found in the lakehouse Tables area."
    }
}

Write-Host "Waiting 60 seconds for the SQL analytics endpoint to sync..." -ForegroundColor Cyan
Start-Sleep -Seconds 60

# ---------------------------------------------------------------------
# 6. SEMANTIC MODEL
# Replace placeholders in a temporary copy so source TMDL remains portable.
# ---------------------------------------------------------------------
Write-Host "`nDeploying semantic model into '$folderInsights'..." -ForegroundColor Yellow
$modelSrc = ".\fabric\caldova_payor_model"
$modelTmp = Join-Path $env:TEMP "caldova_payor_model_$([guid]::NewGuid().ToString('N'))"

try {
    Copy-Item $modelSrc $modelTmp -Recurse -Force

    Get-ChildItem $modelTmp -Recurse -Filter *.tmdl | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        $content = $content.Replace('<WORKSPACE_ITEM_ID>', $wsId)
        $content = $content.Replace('<LAKEHOUSE_ITEM_ID>', $lhId)
        Set-Content $_.FullName -Value $content -NoNewline -Encoding utf8NoBOM
    }

    $leftovers = Get-ChildItem $modelTmp -Recurse -Filter *.tmdl |
        Select-String -Pattern '<WORKSPACE_ITEM_ID>|<LAKEHOUSE_ITEM_ID>'
    if ($leftovers) {
        Stop-Deployment "Placeholders remain in the temporary TMDL copy. Semantic model deployment aborted."
    }

    $modelImport = fab import $modelPath -i $modelTmp --format TMDL -f 2>&1 | Out-String
    Write-Host $modelImport
}
finally {
    if (Test-Path $modelTmp) { Remove-Item $modelTmp -Recurse -Force }
}

$modelId = Get-FabId $modelPath
if ($modelId -notmatch $guidRx) {
    Stop-Deployment "Semantic model was not created or its ID could not be resolved."
}
Write-Host "modelId = $modelId" -ForegroundColor Cyan

# API-created models have no bound owner, so Direct Lake cannot
# authenticate to OneLake until ownership is taken.
$takeover = fab api -A powerbi -X post "groups/$wsId/datasets/$modelId/Default.TakeOver" 2>&1 | Out-String
Write-Host $takeover
if ($takeover -notmatch '"status_code"\s*:\s*200') {
    Write-Host "TakeOver did not return 200. The model may lack credentials for OneLake." -ForegroundColor Yellow
}

Start-Sleep -Seconds 20
$refresh = fab api -A powerbi -X post "groups/$wsId/datasets/$modelId/refreshes" --show_headers 2>&1 | Out-String
Write-Host $refresh
if ($refresh -notmatch '"status_code"\s*:\s*202') {
    Write-Host "Refresh could not be triggered. Refresh manually in the portal." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------
# 7. ONTOLOGY
# Created via REST, so the folder is specified with folderId rather than
# a path segment. Decode InlineBase64 parts, inject runtime IDs, re-encode.
# ---------------------------------------------------------------------
Write-Host "`nDeploying ontology into '$folderInsights'..." -ForegroundColor Yellow
$ontoRoot = ".\fabric\caldova_payor_ontology"
$ontoEnvelopePath = Join-Path $ontoRoot "create-ontology-envelope.json"
$ontoRuntimePath = Join-Path ([System.IO.Path]::GetTempPath()) "ontology-runtime-$([guid]::NewGuid().ToString('N')).json"
$ontoEnvelope = Get-Content $ontoEnvelopePath -Raw | ConvertFrom-Json
$injected = 0

foreach ($part in $ontoEnvelope.definition.parts) {
    if ($part.payloadType -ne "InlineBase64") { continue }
    try {
        $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($part.payload))
    }
    catch {
        Stop-Deployment "Invalid base64 payload in ontology part '$($part.path)'."
    }

    if ($decoded -match '<WORKSPACE_ITEM_ID>|<LAKEHOUSE_ITEM_ID>') {
        $decoded = $decoded.Replace('<WORKSPACE_ITEM_ID>', $wsId)
        $decoded = $decoded.Replace('<LAKEHOUSE_ITEM_ID>', $lhId)
        $part.payload = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($decoded))
        $injected++
        Write-Host "  injected: $($part.path)" -ForegroundColor DarkGray
    }
}

if ($injected -eq 0) {
    Stop-Deployment "No workspace or lakehouse placeholders were found in the ontology envelope."
}

foreach ($part in $ontoEnvelope.definition.parts) {
    if ($part.payloadType -ne "InlineBase64") { continue }
    $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($part.payload))
    if ($decoded -match '<WORKSPACE_ITEM_ID>|<LAKEHOUSE_ITEM_ID>') {
        Stop-Deployment "An ontology placeholder remains in '$($part.path)'."
    }
}

# place the ontology in the Insights folder
$ontoEnvelope | Add-Member -NotePropertyName folderId -NotePropertyValue $folderIds[$folderInsights] -Force

Write-JsonNoBom -Object $ontoEnvelope -Path $ontoRuntimePath
Write-Host "  ontology runtime envelope written without BOM" -ForegroundColor Green

try {
    $ontoResp = fab api -X post "workspaces/$wsId/items" -i $ontoRuntimePath --show_headers 2>&1 | Out-String
    Write-Host $ontoResp
}
finally {
    if (Test-Path $ontoRuntimePath) { Remove-Item $ontoRuntimePath -Force }
}

$ontoOpId = Get-OperationId $ontoResp
if ($ontoOpId) {
    Write-Host "  ontology operationId = $ontoOpId" -ForegroundColor Cyan
    $ontoStatus = Wait-FabricOperation -OperationId $ontoOpId
    if ($ontoStatus -ne "Succeeded") {
        Write-Host "Ontology operation detail:" -ForegroundColor Red
        fab api -X get "operations/$ontoOpId"
        fab api -X get "operations/$ontoOpId/result"
        Stop-Deployment "Ontology creation ended with status '$ontoStatus'."
    }
}
elseif ($ontoResp -notmatch '"status_code"\s*:\s*201|\b201\b') {
    Stop-Deployment "Ontology creation returned neither HTTP 201 nor a long-running operation ID."
}

# Resolve the newly created ontology dynamically. This is a fresh workspace,
# so exactly one ontology is expected.
$ontoJson = fab api -X get "workspaces/$wsId/items?type=Ontology" 2>&1 | Out-String
$ontoId = $null
try {
    $ontoResult = $ontoJson | ConvertFrom-Json
    $ontoItems = @($ontoResult.value)
    if ($ontoItems.Count -eq 1 -and $ontoItems[0].id -match $guidRx) {
        $ontoId = $ontoItems[0].id
    }
}
catch {
    # Fallback below handles CLI output wrappers that are not plain JSON.
}
if (-not $ontoId -and $ontoJson -match '"id"\s*:\s*"([0-9a-fA-F\-]{36})"') {
    $ontoId = $Matches[1]
}
if ($ontoId -notmatch $guidRx) {
    Write-Host $ontoJson
    Stop-Deployment "Ontology was created but its ID could not be resolved."
}
Write-Host "ontologyId = $ontoId" -ForegroundColor Cyan

Start-Sleep -Seconds 45

# ---------------------------------------------------------------------
# 8. FABRIC DATA AGENT
# POST endpoint is /dataAgents. The agent envelope binds to the ontology.
# ---------------------------------------------------------------------
Write-Host "`nDeploying Fabric data agent into '$folderOperational'..." -ForegroundColor Yellow
$agentRoot = ".\fabric\caldova_payor_agent"
$agentEnvelopePath = Join-Path $agentRoot "create-agent-envelope.json"
$agentRuntimePath = Join-Path ([System.IO.Path]::GetTempPath()) "agent-runtime-$([guid]::NewGuid().ToString('N')).json"
$agentEnvelope = Get-Content $agentEnvelopePath -Raw | ConvertFrom-Json
$agentInjected = 0

foreach ($part in $agentEnvelope.definition.parts) {
    if ($part.payloadType -ne "InlineBase64") { continue }
    try {
        $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($part.payload))
    }
    catch {
        Stop-Deployment "Invalid base64 payload in data-agent part '$($part.path)'."
    }

    if ($decoded -match '<WORKSPACE_ITEM_ID>|<ONTOLOGY_ITEM_ID>') {
        $decoded = $decoded.Replace('<WORKSPACE_ITEM_ID>', $wsId)
        $decoded = $decoded.Replace('<ONTOLOGY_ITEM_ID>', $ontoId)
        $part.payload = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($decoded))
        $agentInjected++
        Write-Host "  injected: $($part.path)" -ForegroundColor DarkGray
    }
}

if ($agentInjected -eq 0) {
    Stop-Deployment "No workspace or ontology placeholders were found in the data-agent envelope."
}

foreach ($part in $agentEnvelope.definition.parts) {
    if ($part.payloadType -ne "InlineBase64") { continue }
    $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($part.payload))
    if ($decoded -match '<WORKSPACE_ITEM_ID>|<ONTOLOGY_ITEM_ID>') {
        Stop-Deployment "A data-agent placeholder remains in '$($part.path)'."
    }
}

# place the data agent in the Operational folder
$agentEnvelope | Add-Member -NotePropertyName folderId -NotePropertyValue $folderIds[$folderOperational] -Force

Write-JsonNoBom -Object $agentEnvelope -Path $agentRuntimePath
Write-Host "  data-agent runtime envelope written without BOM" -ForegroundColor Green

try {
    $agentResp = fab api -X post "workspaces/$wsId/dataAgents" -i $agentRuntimePath --show_headers 2>&1 | Out-String
    Write-Host $agentResp
}
finally {
    if (Test-Path $agentRuntimePath) { Remove-Item $agentRuntimePath -Force }
}

if ($agentResp -match '"status_code"\s*:\s*201|\b201\b') {
    Write-Host "Data agent created." -ForegroundColor Green
}
else {
    $agentOpId = Get-OperationId $agentResp
    if (-not $agentOpId) {
        Stop-Deployment "Data-agent request returned neither HTTP 201 nor a long-running operation ID."
    }

    Write-Host "  data-agent operationId = $agentOpId" -ForegroundColor Cyan
    $agentStatus = Wait-FabricOperation -OperationId $agentOpId
    if ($agentStatus -ne "Succeeded") {
        Write-Host "Data-agent operation detail:" -ForegroundColor Red
        fab api -X get "operations/$agentOpId"
        fab api -X get "operations/$agentOpId/result"
        Stop-Deployment "Data-agent creation ended with status '$agentStatus'."
    }
    Write-Host "Data agent created." -ForegroundColor Green
}

# ---------------------------------------------------------------------
# 9. NOTEBOOK + DATA PIPELINE
# One shared notebook backs all three notebook activities.
# ---------------------------------------------------------------------
Write-Host "`nCreating notebook in '$folderIngestion'..." -ForegroundColor Yellow
fab create $nbPath

$nbId = Get-FabId $nbPath
if ($nbId -notmatch $guidRx) {
    Stop-Deployment "Notebook was not created or its ID could not be resolved."
}
Write-Host "notebookId = $nbId" -ForegroundColor Cyan

Write-Host "Deploying data pipeline into '$folderIngestion'..." -ForegroundColor Yellow
$pipeSrc = ".\fabric\pl_ingest_enrollment"
$pipeTmp = Join-Path $env:TEMP "pl_ingest_enrollment_$([guid]::NewGuid().ToString('N'))"

try {
    Copy-Item $pipeSrc $pipeTmp -Recurse -Force

    Get-ChildItem $pipeTmp -Recurse -File | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        $content = $content.Replace('<WORKSPACE_ITEM_ID>', $wsId)
        $content = $content.Replace('<LAKEHOUSE_ITEM_ID>', $lhId)
        $content = $content.Replace('<NOTEBOOK_ITEM_ID>', $nbId)
        [System.IO.File]::WriteAllText($_.FullName, $content, [System.Text.UTF8Encoding]::new($false))
    }

    $pipeLeft = Get-ChildItem $pipeTmp -Recurse -File |
        Select-String -Pattern '<WORKSPACE_ITEM_ID>|<LAKEHOUSE_ITEM_ID>|<NOTEBOOK_ITEM_ID>'
    if ($pipeLeft) {
        Stop-Deployment "Placeholders remain in the temporary pipeline copy. Pipeline deployment aborted."
    }

    $pipeImport = fab import $pipePath -i $pipeTmp -f 2>&1 | Out-String
    Write-Host $pipeImport
}
finally {
    if (Test-Path $pipeTmp) { Remove-Item $pipeTmp -Recurse -Force }
}

Start-Sleep -Seconds 15
$pipeId = Get-FabId $pipePath
if ($pipeId -notmatch $guidRx) {
    Write-Host "Pipeline ID could not be resolved. Verify the pipeline in the portal." -ForegroundColor Yellow
}
else {
    Write-Host "pipelineId = $pipeId" -ForegroundColor Cyan
    Write-Host "Data pipeline created." -ForegroundColor Green
}

# ---------------------------------------------------------------------
# 10. VERIFY
# ---------------------------------------------------------------------
Write-Host "`nVerifying folder contents..." -ForegroundColor Cyan
foreach ($f in $allFolders) {
    Write-Host "`n$f :" -ForegroundColor Cyan
    fab ls "$workspace.Workspace/$f.Folder"
}

Write-Host "`nDeployment complete." -ForegroundColor Green
Write-Host "Workspace:      $workspace"                           -ForegroundColor Green
Write-Host "  $folderSources     -> $lakehouseName"               -ForegroundColor Green
Write-Host "  $folderIngestion   -> $notebookName, $pipelineName" -ForegroundColor Green
Write-Host "  $folderInsights    -> $modelName, $ontologyName"    -ForegroundColor Green
Write-Host "  $folderOperational -> $agentName"                   -ForegroundColor Green

Write-Host "`nMANUAL STEPS REQUIRED" -ForegroundColor Yellow
Write-Host "  1. Open the ontology's graph model in the Fabric portal and click Save." -ForegroundColor Yellow
Write-Host "     A graph model created entirely via REST API is not queryable until the" -ForegroundColor Yellow
Write-Host "     portal provisions its loading infrastructure on first open. Until then" -ForegroundColor Yellow
Write-Host "     the data agent reports 'graph model not ready'." -ForegroundColor Yellow
Write-Host "  2. Add entity and relationship descriptions and synonyms in the portal." -ForegroundColor Yellow
Write-Host "     This metadata is not part of the ontology definition schema and cannot" -ForegroundColor Yellow
Write-Host "     be deployed via API. It grounds the data agent's answers." -ForegroundColor Yellow
Write-Host "  3. Select a predesigned task flow and assign items to tasks." -ForegroundColor Yellow
Write-Host "     Task flow has no API surface." -ForegroundColor Yellow
