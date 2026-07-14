param([string]$Name = "")

$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$reference = Join-Path $root "projects\AKS_2026"
$templateDir = Join-Path $root "docs\templates"
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
if (-not $Name) { $Name = Read-Host "Nhap ten du an moi" }
$projectId = ($Name.Trim() -replace '[^A-Za-z0-9_-]', '_') -replace '_+', '_'
$projectId = $projectId.Trim('_')
if (-not $projectId) { throw "Ten du an khong hop le." }

$target = [IO.Path]::GetFullPath((Join-Path $root "projects\$projectId"))
$projectsRoot = [IO.Path]::GetFullPath((Join-Path $root "projects")).TrimEnd('\') + '\'
if (-not $target.StartsWith($projectsRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Duong dan du an khong an toan." }
if (Test-Path -LiteralPath $target) { throw "Du an da ton tai: $target" }

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
foreach ($dir in $dirs) { New-Item -ItemType Directory -Path (Join-Path $target $dir) -Force | Out-Null }
Copy-Item -LiteralPath (Join-Path $reference "_NOI_BO\config") -Destination (Join-Path $target "_NOI_BO") -Recurse
Copy-Item -LiteralPath (Join-Path $reference "_NOI_BO\pipeline") -Destination (Join-Path $target "_NOI_BO") -Recurse
foreach ($name in @('run_field_area_workflow.ps1','run_positive_reference_features_safe.ps1','run_design_workflow.ps1','run_interpolation_workflow.ps1','run_sensitivity_workflow.ps1','sync_settings.ps1','status.ps1')) {
  Copy-Item -LiteralPath (Join-Path $reference "_NOI_BO\$name") -Destination (Join-Path $target "_NOI_BO\$name")
}
Copy-Item -LiteralPath (Join-Path $reference "RUN.ps1") -Destination (Join-Path $target "RUN.ps1")
Remove-Item -LiteralPath (Join-Path $target "_NOI_BO\config\pca_model_reference.json") -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $target "_NOI_BO\config\sampling_legacy.yml") -Force -ErrorAction SilentlyContinue
$pipelineRoot = [IO.Path]::GetFullPath((Join-Path $target "_NOI_BO\pipeline"))
if (-not $pipelineRoot.StartsWith($target, [StringComparison]::OrdinalIgnoreCase)) { throw "Duong dan pipeline khong an toan." }
Get-ChildItem -LiteralPath $pipelineRoot -Directory -Filter "__pycache__" -Recurse -ErrorAction SilentlyContinue |
  ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
Remove-Item -LiteralPath (Join-Path $target "_NOI_BO\pipeline\status_legacy.ps1") -Force -ErrorAction SilentlyContinue

$textFiles = Get-ChildItem -LiteralPath $target -Recurse -File | Where-Object { $_.Extension -in @('.R', '.py', '.ps1', '.yml', '.md', '.json') }
$utf8 = New-Object System.Text.UTF8Encoding($false)
foreach ($file in $textFiles) {
  $text = [IO.File]::ReadAllText($file.FullName)
  $text = $text.Replace("AKS_2026", $projectId)
  [IO.File]::WriteAllText($file.FullName, $text, $utf8)
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

$header = "code,lat,lon,pH,Humus,CEC,N_total,P_Olsen,P_Bray,K_available_mgkg,K_exchangeable_cmol,Ca_exchangeable,Mg_exchangeable,S_available,B_available,Zn_available,Cu_available,Mn_available,Fe_available,EC"
[IO.File]::WriteAllText((Join-Path $target "02_NOI_SUY_BAN_DO\01_DAU_VAO\sample_actual.csv"), $header + [Environment]::NewLine, $utf8)
Copy-Item -LiteralPath (Join-Path $templateDir "INDICATOR_METADATA.yml") `
  -Destination (Join-Path $target "02_NOI_SUY_BAN_DO\01_DAU_VAO\indicator_metadata.yml")
Copy-Item -LiteralPath (Join-Path $templateDir "INTERPRETATION.yml") `
  -Destination (Join-Path $target "00_XAC_LAP_VUNG_MIA\01_DAU_VAO\interpretation.yml")
Copy-Item -LiteralPath (Join-Path $templateDir "SUGARCANE_LABELS_TEMPLATE.csv") `
  -Destination (Join-Path $target "00_XAC_LAP_VUNG_MIA\01_DAU_VAO\sugarcane_labels_template.csv")

$sampling = @"
project_id: $projectId
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
[IO.File]::WriteAllText((Join-Path $target "01_THIET_KE_LAY_MAU\01_DAU_VAO\sampling.yml"), $sampling, $utf8)

Write-ProjectTemplate "WORKFLOW0_GUIDE.md" (Join-Path $target "00_XAC_LAP_VUNG_MIA\HUONG_DAN.md")
Write-ProjectTemplate "WORKFLOW1_GUIDE.md" (Join-Path $target "01_THIET_KE_LAY_MAU\HUONG_DAN.md")
Write-ProjectTemplate "WORKFLOW2_GUIDE.md" (Join-Path $target "02_NOI_SUY_BAN_DO\HUONG_DAN.md")
Write-ProjectTemplate "PROJECT_README.md" (Join-Path $target "README.md")

$statusBat = @"
@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0RUN.ps1" status
pause
"@
[IO.File]::WriteAllText((Join-Path $target "0_KIEM_TRA_DU_AN.bat"), $statusBat, [Text.Encoding]::ASCII)

$fieldBat = @"
@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\RUN.ps1" interpret
pause
"@
[IO.File]::WriteAllText((Join-Path $target "00_XAC_LAP_VUNG_MIA\CHAY_XAC_LAP_VUNG_MIA.bat"), $fieldBat, [Text.Encoding]::ASCII)

$designBat = @"
@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\RUN.ps1" design
pause
"@
[IO.File]::WriteAllText((Join-Path $target "01_THIET_KE_LAY_MAU\CHAY_THIET_KE_LAY_MAU.bat"), $designBat, [Text.Encoding]::ASCII)

$mapBat = @"
@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\RUN.ps1" interpolate
pause
"@
[IO.File]::WriteAllText((Join-Path $target "02_NOI_SUY_BAN_DO\CHAY_NOI_SUY_BAN_DO.bat"), $mapBat, [Text.Encoding]::ASCII)

Write-Host "Da tao du an: $target" -ForegroundColor Green
Write-Host "Buoc tiep theo: mo README.md. Neu co san ROI field, dat roi_field_area.geojson vao buoc 00; neu chua co, dat roi_search + labels da xac minh."
