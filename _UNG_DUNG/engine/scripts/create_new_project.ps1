param([string]$Name = "")

$ErrorActionPreference = "Stop"
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\.."))
$projectsDir = [IO.Path]::GetFullPath((Join-Path $root "projects"))
$projectTemplate = Join-Path $root "_UNG_DUNG\project_template"
$templateDir = Join-Path $root "docs\templates"
$utf8 = New-Object System.Text.UTF8Encoding($false)

$requiredTemplates = @(
  "PROJECT_README.md",
  "WORKFLOW0_GUIDE.md",
  "WORKFLOW1_GUIDE.md",
  "WORKFLOW2_GUIDE.md",
  "INTERPRETATION.yml",
  "SUGARCANE_LABELS_TEMPLATE.csv",
  "INDICATOR_METADATA.yml"
)
foreach ($templateName in $requiredTemplates) {
  $templatePath = Join-Path $templateDir $templateName
  if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
    throw "Thieu template tao du an: $templatePath"
  }
}

$requiredBlueprintDirectories = @(
  "_NOI_BO\config",
  "_NOI_BO\pipeline"
)
foreach ($relativePath in $requiredBlueprintDirectories) {
  $blueprintPath = Join-Path $projectTemplate $relativePath
  if (-not (Test-Path -LiteralPath $blueprintPath -PathType Container)) {
    throw "Thieu thu muc project template: $blueprintPath"
  }
}

$requiredBlueprintFiles = @(
  "_NOI_BO\config\project.yml",
  "_NOI_BO\run_field_area_workflow.ps1",
  "_NOI_BO\run_design_workflow.ps1",
  "_NOI_BO\run_interpolation_workflow.ps1",
  "_NOI_BO\run_sensitivity_workflow.ps1",
  "_NOI_BO\sync_settings.ps1",
  "_NOI_BO\status.ps1"
)
foreach ($relativePath in $requiredBlueprintFiles) {
  $blueprintPath = Join-Path $projectTemplate $relativePath
  if (-not (Test-Path -LiteralPath $blueprintPath -PathType Leaf)) {
    throw "Thieu tep project template: $blueprintPath"
  }
}

if (-not $Name) { $Name = Read-Host "Nhap ten du an moi" }
$projectId = ($Name.Trim() -replace '[^A-Za-z0-9_-]', '_') -replace '_+', '_'
$projectId = $projectId.Trim('_')
if (-not $projectId) { throw "Ten du an khong hop le." }

$projectsPrefix = $projectsDir.TrimEnd('\') + '\'
$target = [IO.Path]::GetFullPath((Join-Path $projectsDir $projectId))
if (-not $target.StartsWith($projectsPrefix, [StringComparison]::OrdinalIgnoreCase)) {
  throw "Duong dan du an khong an toan."
}
if (Test-Path -LiteralPath $target) { throw "Du an da ton tai: $target" }

$stagingName = ".creating_{0}_{1}" -f $projectId, [guid]::NewGuid().ToString("N")
$staging = [IO.Path]::GetFullPath((Join-Path $projectsDir $stagingName))
if (-not $staging.StartsWith($projectsPrefix, [StringComparison]::OrdinalIgnoreCase)) {
  throw "Duong dan staging khong an toan."
}

function Write-ProjectTemplate {
  param(
    [Parameter(Mandatory = $true)][string]$TemplateName,
    [Parameter(Mandatory = $true)][string]$Destination
  )
  $templatePath = Join-Path $templateDir $TemplateName
  $content = [IO.File]::ReadAllText($templatePath)
  $content = $content.Replace("{{PROJECT_ID}}", $projectId)
  [IO.File]::WriteAllText($Destination, $content, $utf8)
}

try {
  New-Item -ItemType Directory -Path $staging -Force | Out-Null

  $dirs = @(
    "00_XAC_LAP_VUNG_MIA\01_DAU_VAO",
    "00_XAC_LAP_VUNG_MIA\02_KET_QUA",
    "01_THIET_KE_LAY_MAU\01_DAU_VAO",
    "01_THIET_KE_LAY_MAU\02_KET_QUA",
    "02_NOI_SUY_BAN_DO\01_DAU_VAO",
    "02_NOI_SUY_BAN_DO\02_KET_QUA\maps",
    "02_NOI_SUY_BAN_DO\02_KET_QUA\reports",
    "02_NOI_SUY_BAN_DO\02_KET_QUA\tables",
    "_NOI_BO\work\field_area\reference_package",
    "_NOI_BO\work\model_package",
    "_NOI_BO\work\design\qa",
    "_NOI_BO\work\interpolation\qa",
    "_NOI_BO\work\models\input\sensitivity",
    "_NOI_BO\work\models\qa",
    "_NOI_BO\work\models\PC_ONLY",
    "_NOI_BO\work\models\PC_PLUS_SOIL"
  )
  foreach ($dir in $dirs) {
    New-Item -ItemType Directory -Path (Join-Path $staging $dir) -Force | Out-Null
  }

  Copy-Item -LiteralPath (Join-Path $projectTemplate "_NOI_BO\config") -Destination (Join-Path $staging "_NOI_BO") -Recurse
  Copy-Item -LiteralPath (Join-Path $projectTemplate "_NOI_BO\pipeline") -Destination (Join-Path $staging "_NOI_BO") -Recurse
  foreach ($name in @(
    "run_field_area_workflow.ps1",
    "run_design_workflow.ps1",
    "run_interpolation_workflow.ps1",
    "run_sensitivity_workflow.ps1",
    "sync_settings.ps1",
    "status.ps1"
  )) {
    Copy-Item -LiteralPath (Join-Path $projectTemplate "_NOI_BO\$name") -Destination (Join-Path $staging "_NOI_BO\$name")
  }

  foreach ($sourceOnly in @(
    "_NOI_BO\config\positive_reference_knowledge_contract.json",
    "_NOI_BO\pipeline\build_positive_feature_library.py",
    "_NOI_BO\pipeline\build_positive_feature_library_safe.py",
    "_NOI_BO\pipeline\extract_positive_feature_knowledge_atomic.py",
    "_NOI_BO\pipeline\ingest_positive_feature_knowledge.py",
    "_NOI_BO\pipeline\positive_reference_contract.py",
    "_NOI_BO\run_positive_reference_features_safe.ps1"
  )) {
    Remove-Item -LiteralPath (Join-Path $staging $sourceOnly) -Force -ErrorAction SilentlyContinue
  }
  Remove-Item -LiteralPath (Join-Path $staging "_NOI_BO\config\pca_model_reference.json") -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath (Join-Path $staging "_NOI_BO\config\sampling_legacy.yml") -Force -ErrorAction SilentlyContinue

  $testsPath = [IO.Path]::GetFullPath((Join-Path $staging "_NOI_BO\pipeline\tests"))
  if (-not $testsPath.StartsWith($staging.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Duong dan tests khong an toan."
  }
  if (Test-Path -LiteralPath $testsPath) {
    Remove-Item -LiteralPath $testsPath -Recurse -Force
  }

  $pipelineRoot = [IO.Path]::GetFullPath((Join-Path $staging "_NOI_BO\pipeline"))
  if (-not $pipelineRoot.StartsWith($staging.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Duong dan pipeline khong an toan."
  }
  Get-ChildItem -LiteralPath $pipelineRoot -Directory -Filter "__pycache__" -Recurse -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }

  $textExtensions = @(".R", ".py", ".ps1", ".yml", ".yaml", ".md", ".json", ".csv", ".txt")
  $textFiles = Get-ChildItem -LiteralPath $staging -Recurse -File |
    Where-Object { $_.Extension -in $textExtensions }
  foreach ($file in $textFiles) {
    $text = [IO.File]::ReadAllText($file.FullName)
    $text = $text.Replace("{{PROJECT_ID}}", $projectId)
    [IO.File]::WriteAllText($file.FullName, $text, $utf8)
  }

  $remainingPlaceholder = Get-ChildItem -LiteralPath $staging -Recurse -File |
    Where-Object { $_.Extension -in $textExtensions } |
    Select-String -SimpleMatch "{{PROJECT_ID}}" -List
  if ($remainingPlaceholder) {
    throw "Project template con placeholder chua duoc thay: $($remainingPlaceholder[0].Path)"
  }
  $sourceSpecificReference = Get-ChildItem -LiteralPath $staging -Recurse -File |
    Where-Object { $_.Extension -in $textExtensions } |
    Select-String -Pattern "AKS_2026|PHU_YEN_MOCK" -List
  if ($sourceSpecificReference) {
    throw "Project template con tham chieu du an nguon: $($sourceSpecificReference[0].Path)"
  }

  $commonSettings = @"
# Nguon duy nhat cho CRS, GEE project, grid, buffer ho tro va khoang ngay covariates.
# Cac tep trong buoc 00/01 se duoc ung dung dong bo tu dong.
project_id: $projectId
crs_mode: auto
crs_epsg: 32649
resolution_m: 10
covariate_support_buffer_m: 300
gee_project_id: rkapp-492504
sampling_start_date: "2026-01-01"
sampling_end_date: "2026-04-01"
"@
  [IO.File]::WriteAllText((Join-Path $staging "THONG_SO_DU_AN.yml"), $commonSettings, $utf8)

  $header = "code,lat,lon,pH,Humus,CEC,N_total,P_Olsen,P_Bray,K_available_mgkg,K_exchangeable_cmol,Ca_exchangeable,Mg_exchangeable,S_available,B_available,Zn_available,Cu_available,Mn_available,Fe_available,EC"
  [IO.File]::WriteAllText(
    (Join-Path $staging "02_NOI_SUY_BAN_DO\01_DAU_VAO\sample_actual.csv"),
    $header + [Environment]::NewLine,
    $utf8
  )
  Write-ProjectTemplate "INDICATOR_METADATA.yml" (Join-Path $staging "02_NOI_SUY_BAN_DO\01_DAU_VAO\indicator_metadata.yml")
  Write-ProjectTemplate "INTERPRETATION.yml" (Join-Path $staging "00_XAC_LAP_VUNG_MIA\01_DAU_VAO\interpretation.yml")
  Write-ProjectTemplate "SUGARCANE_LABELS_TEMPLATE.csv" (Join-Path $staging "00_XAC_LAP_VUNG_MIA\01_DAU_VAO\sugarcane_labels_template.csv")

  $sampling = @"
# CRS, GEE, resolution va ngay covariates duoc dong bo tu THONG_SO_DU_AN.yml.
project_id: $projectId
crs_mode: auto
crs_epsg: 32649
resolution_m: 10
gee_project_id: rkapp-492504
start_date: "2026-01-01"
end_date: "2026-04-01"

continuous_covariates: [CHIRPS, DEM, NDVI, Slope, TWI]
soil_group_field: Ma1

sampling_method: backend_reported_at_runtime
method_family: conditioned_latin_hypercube_core_with_spatial_augmentation
original_clhs_optimizer: false
original_clhs_optimizer_core_requested: true
full_plan_is_pure_clhs: false
clhs_backend: auto
reduced_core_samples: 79
reduced_plan: conditioned_lhs_core_only
clhs_iterations: 20000
clhs_restarts: 4
clhs_use_cpp: true
clhs_auto_install: true
clhs_repository: https://cloud.r-project.org
clhs_weight_numeric: 1.0
clhs_weight_factor: 1.0
clhs_weight_correlation: 1.0
clhs_max_candidates: 200000
inner_buffer_m: 30
minimum_field_area_ha: 0.1
minimum_spacing_m: 100
spatial_infill_max_fraction: 0.20
short_lag_fraction: 0.10
short_lag_min_m: 100
short_lag_max_m: 300
random_seed: 42
"@
  [IO.File]::WriteAllText((Join-Path $staging "01_THIET_KE_LAY_MAU\01_DAU_VAO\sampling.yml"), $sampling, $utf8)

  Write-ProjectTemplate "WORKFLOW0_GUIDE.md" (Join-Path $staging "00_XAC_LAP_VUNG_MIA\HUONG_DAN.md")
  Write-ProjectTemplate "WORKFLOW1_GUIDE.md" (Join-Path $staging "01_THIET_KE_LAY_MAU\HUONG_DAN.md")
  Write-ProjectTemplate "WORKFLOW2_GUIDE.md" (Join-Path $staging "02_NOI_SUY_BAN_DO\HUONG_DAN.md")
  Write-ProjectTemplate "PROJECT_README.md" (Join-Path $staging "README.md")

  $runScript = @"
param(
  [Parameter(Position = 0)]
  [ValidateSet('status','interpret','design','interpolate')]
  [string]{{DOLLAR}}Action = 'status'
)
{{DOLLAR}}project = {{DOLLAR}}PSScriptRoot
switch ({{DOLLAR}}Action) {
  'status' { & "{{DOLLAR}}project\_NOI_BO\status.ps1" }
  'interpret' { & "{{DOLLAR}}project\_NOI_BO\run_field_area_workflow.ps1" }
  'design' { & "{{DOLLAR}}project\_NOI_BO\run_design_workflow.ps1" }
  'interpolate' { & "{{DOLLAR}}project\_NOI_BO\run_interpolation_workflow.ps1" }
}
if (-not {{DOLLAR}}?) { exit 1 }
exit {{DOLLAR}}LASTEXITCODE
"@
  $runScript = $runScript.Replace("{{DOLLAR}}", '$')
  [IO.File]::WriteAllText((Join-Path $staging "RUN.ps1"), $runScript, $utf8)

  $statusBat = @"
@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0RUN.ps1" status
pause
"@
  [IO.File]::WriteAllText((Join-Path $staging "0_KIEM_TRA_DU_AN.bat"), $statusBat, [Text.Encoding]::ASCII)

  $fieldBat = @"
@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\RUN.ps1" interpret
pause
"@
  [IO.File]::WriteAllText((Join-Path $staging "00_XAC_LAP_VUNG_MIA\CHAY_XAC_LAP_VUNG_MIA.bat"), $fieldBat, [Text.Encoding]::ASCII)

  $designBat = @"
@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\RUN.ps1" design
pause
"@
  [IO.File]::WriteAllText((Join-Path $staging "01_THIET_KE_LAY_MAU\CHAY_THIET_KE_LAY_MAU.bat"), $designBat, [Text.Encoding]::ASCII)

  $mapBat = @"
@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\RUN.ps1" interpolate
pause
"@
  [IO.File]::WriteAllText((Join-Path $staging "02_NOI_SUY_BAN_DO\CHAY_NOI_SUY_BAN_DO.bat"), $mapBat, [Text.Encoding]::ASCII)

  Move-Item -LiteralPath $staging -Destination $target
} catch {
  $originalError = $_
  if (Test-Path -LiteralPath $staging -PathType Container) {
    $verifiedStaging = [IO.Path]::GetFullPath($staging)
    if ($verifiedStaging.StartsWith($projectsPrefix, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $verifiedStaging).StartsWith(".creating_", [StringComparison]::OrdinalIgnoreCase)) {
      Remove-Item -LiteralPath $verifiedStaging -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  throw $originalError
}

Write-Host "Da tao du an: $target" -ForegroundColor Green
Write-Host "Buoc tiep theo: mo README.md va THONG_SO_DU_AN.yml."
Write-Host "Neu co san ROI field, dat roi_field_area.geojson vao buoc 00; neu chua co, dat roi_search + labels da xac minh."