$ErrorActionPreference = "Stop"
$internal = $PSScriptRoot
$project = Split-Path -Parent $internal
$root = Resolve-Path (Join-Path $project "..\..")
Set-Location $root
$designInput = Join-Path $project "01_THIET_KE_LAY_MAU\01_DAU_VAO"
$sampleFile = Join-Path $project "02_NOI_SUY_BAN_DO\01_DAU_VAO\sample_actual.csv"
$result = Join-Path $project "02_NOI_SUY_BAN_DO\02_KET_QUA"
$designWork = Join-Path $internal "work\design"
$work = Join-Path $internal "work\interpolation"
$modelWork = Join-Path $internal "work\models"
$pipeline = Join-Path $internal "pipeline"
$configDir = Join-Path $internal "config"

function PythonPath {
  $preferred = "D:\apps\POINT_PLANNING_APP\.venv\Scripts\python.exe"
  if (Test-Path -LiteralPath $preferred) { return $preferred }
  $cmd = Get-Command python -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  throw "Khong tim thay Python."
}
function RscriptPath {
  $cmd = Get-Command Rscript -ErrorAction SilentlyContinue
  if (-not $cmd) { throw "Khong tim thay Rscript." }
  return $cmd.Source
}
function RunChecked([string]$Command, [string[]]$Arguments) {
  & $Command @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Buoc xu ly that bai: $Command $($Arguments -join ' ')" }
}
function MissingFiles([string[]]$Paths) { @($Paths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }).Count -gt 0 }

if (-not (Test-Path -LiteralPath $sampleFile -PathType Leaf)) { throw "Thieu sample_actual.csv. Dat file tai: $sampleFile" }
$designPcs = 1..5 | ForEach-Object { Join-Path $designWork ("PC{0}.tif" -f $_) }
if (MissingFiles $designPcs) { throw "Chua co PCA tu quy trinh 1. Hay chay CHAY_THIET_KE_LAY_MAU.bat truoc." }
if (-not (Test-Path -LiteralPath (Join-Path $configDir "pca_model_reference.json"))) { throw "Thieu PCA reference cua quy trinh 1." }
& "$internal\sync_settings.ps1"
$python = PythonPath
$rscript = RscriptPath

Write-Host "[1/6] Kiem tra sample_actual va cac diem ngoai ROI..." -ForegroundColor Cyan
RunChecked $rscript @("projects\AKS_2026\_NOI_BO\pipeline\preflight_actual.R")

$buffers = Join-Path $work "covariate_support_buffers.gpkg"
if (Test-Path -LiteralPath $buffers) {
  $preflightSummary = Get-Content -LiteralPath (Join-Path $work "qa\preflight_summary.json") -Raw | ConvertFrom-Json
  if ([int]$preflightSummary.n_requiring_gee_download -gt 0) {
    Write-Host "[2/6] Tai covariates bo sung tu Earth Engine cho diem thieu coverage..." -ForegroundColor Cyan
    RunChecked $python @("projects\AKS_2026\_NOI_BO\pipeline\run_download_actual.py")
  } else {
    Write-Host "[2/6] Covariates support da du; bo qua tai Earth Engine." -ForegroundColor Green
  }
  Write-Host "[3/6] Rebuild PCA support voi frozen reference va ghi provenance hash..." -ForegroundColor Cyan
  RunChecked $rscript @("projects\AKS_2026\_NOI_BO\pipeline\02_build_pca_support.R")
  RunChecked $rscript @("projects\AKS_2026\_NOI_BO\pipeline\preflight_actual.R")
} else {
  $preflightSummaryFile = Join-Path $work "qa\preflight_summary.json"
  $reuseAvailableCurrent = $false
  $reuseVerifiedCurrent = $false
  if (Test-Path -LiteralPath $preflightSummaryFile) {
    $preflightSummary = Get-Content -LiteralPath $preflightSummaryFile -Raw | ConvertFrom-Json
    $reuseAvailableCurrent = [int]$preflightSummary.n_with_complete_current_actual_pc -eq [int]$preflightSummary.n_samples
    $reuseVerifiedCurrent = [bool]$preflightSummary.current_pca_provenance_valid -and
      ([int]$preflightSummary.n_with_trusted_current_actual_pc -eq [int]$preflightSummary.n_samples)
  }
  if ($reuseAvailableCurrent) {
    if ($reuseVerifiedCurrent) {
      Write-Host "[2/6] Tai su dung PCA hien tai da khop hash voi frozen reference." -ForegroundColor Green
    } else {
      Write-Host "[2/6] PCA hien tai day du nhung provenance dang cho refresh; giu nguyen raster va danh dau DRAFT." -ForegroundColor Yellow
    }
  } else {
    Write-Host "[2/6] Sao chep PCA workflow 1 va tao provenance hash..." -ForegroundColor Cyan
    foreach ($i in 1..5) {
      Copy-Item -LiteralPath (Join-Path $designWork ("PC{0}.tif" -f $i)) -Destination (Join-Path $work ("PC{0}.tif" -f $i)) -Force
    }
    Remove-Item -LiteralPath (Join-Path $work "qa\pca_current_provenance.json") -Force -ErrorAction SilentlyContinue
    RunChecked $rscript @("projects\AKS_2026\_NOI_BO\pipeline\verify_current_pca_provenance.R")
    RunChecked $rscript @("projects\AKS_2026\_NOI_BO\pipeline\preflight_actual.R")
  }
}
Write-Host "[4/8] Danh gia do tuong dong covariate cua cac diem ngoai ROI..." -ForegroundColor Cyan
RunChecked $rscript @("projects\AKS_2026\_NOI_BO\pipeline\diagnose_outside_covariate_support.R")

Write-Host "[5/8] Kiem tra predictor va Soil Type tuy chon..." -ForegroundColor Cyan
$hasSoil = Test-Path -LiteralPath (Join-Path $designInput "soil_type.geojson")
if ($hasSoil) {
  RunChecked $python @("projects\AKS_2026\_NOI_BO\pipeline\run_prepare_soil_actual.py")
  RunChecked $rscript @("scripts\validate_raster_schema.R", "--config", "projects\AKS_2026\_NOI_BO\config\full_pc_soil.R", "--point", "projects\AKS_2026\_NOI_BO\work\interpolation\sample_actual_clean.csv", "--output", "projects\AKS_2026\_NOI_BO\work\interpolation\qa\raster_schema_current.json")
} else {
  Write-Host "[INFO] Khong co Soil Type; chi chay mo hinh PC." -ForegroundColor Yellow
  RunChecked $rscript @("scripts\validate_raster_schema.R", "--config", "projects\AKS_2026\_NOI_BO\config\full_pc.R", "--point", "projects\AKS_2026\_NOI_BO\work\interpolation\sample_actual_clean.csv", "--output", "projects\AKS_2026\_NOI_BO\work\interpolation\qa\raster_schema_current.json")
}

Write-Host "[6/8] Kiem tra ket qua phan tich..." -ForegroundColor Cyan
RunChecked $rscript @("projects\AKS_2026\_NOI_BO\pipeline\prepare_model_input.R")

$modelInput = Join-Path $modelWork "input\soil_points.csv"
$rows = @(Import-Csv -LiteralPath $modelInput)
$core = @('code','lat','lon')
$indicators = @($rows[0].PSObject.Properties.Name | Where-Object { $_ -notin $core })
$filled = @($indicators | Where-Object { $name = $_; @($rows | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.$name) }).Count -gt 0 })
if ($filled.Count -eq 0) { throw "Khong co chi tieu nao co ket qua so trong sample_actual.csv." }

function RunModel([string]$Indicator, [string]$ModelName, [string]$ConfigFile, [string]$OutputRoot) {
  Write-Host "    $Indicator - $ModelName" -ForegroundColor Cyan
  $safeIndicator = ($Indicator -replace '[^A-Za-z0-9_-]', '_') -replace '_+', '_'
  $runName = "AKS_2026_${safeIndicator}_${ModelName}"
  $expectedRun = Join-Path $OutputRoot $runName
  $env:RK_TARGET_FIELD = $Indicator
  $env:RK_RUN_NAME = $runName
  $env:RK_CONFIG_OVERRIDE = $ConfigFile
  try { RunChecked (RscriptPath) @("scripts\main.R") }
  finally {
    Remove-Item Env:RK_TARGET_FIELD -ErrorAction SilentlyContinue
    Remove-Item Env:RK_RUN_NAME -ErrorAction SilentlyContinue
    Remove-Item Env:RK_CONFIG_OVERRIDE -ErrorAction SilentlyContinue
  }
  if (-not (Test-Path -LiteralPath $expectedRun -PathType Container)) { throw "Khong tim thay output model cho $Indicator - $ModelName" }
  $mapOut = Join-Path $result "maps\$safeIndicator\$ModelName"
  RunChecked (RscriptPath) @("projects\AKS_2026\_NOI_BO\pipeline\04_mask_final_to_roi.R", "--run_dir", $expectedRun, "--output_dir", $mapOut)
  $reportSource = Join-Path $expectedRun "06_report"
  $reportOut = Join-Path $result "reports\$safeIndicator\$ModelName"
  if (Test-Path -LiteralPath $reportSource) {
    New-Item -ItemType Directory -Path $reportOut -Force | Out-Null
    Copy-Item -Path (Join-Path $reportSource '*') -Destination $reportOut -Recurse -Force
  }
}

Write-Host "[7/8] Chay noi suy cho $($filled.Count) chi tieu..." -ForegroundColor Cyan
foreach ($indicator in $filled) {
  RunModel $indicator "PC_ONLY" "projects/AKS_2026/_NOI_BO/config/rk_pc.R" (Join-Path $modelWork "PC_ONLY")
  if ($hasSoil) { RunModel $indicator "PC_PLUS_SOIL" "projects/AKS_2026/_NOI_BO/config/rk_pc_soil.R" (Join-Path $modelWork "PC_PLUS_SOIL") }
}
Write-Host "[8/8] Phan tich do nhay voi tap chi gom diem trong ROI..." -ForegroundColor Cyan
$preflightSummaryFile = Join-Path $work "qa\preflight_summary.json"
$preflightForSensitivity = Get-Content -LiteralPath $preflightSummaryFile -Raw | ConvertFrom-Json
if ([int]$preflightForSensitivity.n_outside_roi -gt 0) {
  & "$internal\run_sensitivity_workflow.ps1"
  if ($LASTEXITCODE -ne 0) { throw "Phan tich do nhay outside-ROI that bai." }
} else {
  Write-Host "[SKIP] Khong co diem ngoai ROI." -ForegroundColor Green
}
Write-Host "HOAN TAT BAN DO DINH DUONG" -ForegroundColor Green
Write-Host "Ket qua: $result"
