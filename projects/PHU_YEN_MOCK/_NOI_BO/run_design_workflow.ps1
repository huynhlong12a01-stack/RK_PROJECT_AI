param([switch]$ForceDownload)

$ErrorActionPreference = "Stop"
$internal = $PSScriptRoot
$project = Split-Path -Parent $internal
$root = Resolve-Path (Join-Path $project "..\..")
Set-Location $root
$rLibrary = Join-Path $root '_UNG_DUNG\runtime\R_library'
New-Item -ItemType Directory -Path $rLibrary -Force | Out-Null
$env:R_LIBS_USER = $rLibrary
$input = Join-Path $project "01_THIET_KE_LAY_MAU\01_DAU_VAO"
$result = Join-Path $project "01_THIET_KE_LAY_MAU\02_KET_QUA"
$work = Join-Path $internal "work\design"
$pipeline = Join-Path $internal "pipeline"
$configFile = Join-Path $internal "config\project.yml"
$settings = Join-Path $input "sampling.yml"
$logDir = Join-Path $internal "logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

function PythonPath {
  $local = Join-Path $root '.venv\Scripts\python.exe'
  if (Test-Path -LiteralPath $local -PathType Leaf) { return $local }
  $cmd = Get-Command python -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  throw "Khong tim thay Python. Hay chay CAI_DAT_UNG_DUNG.bat o thu muc goc."
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
function NeedFiles([string[]]$Paths) { @($Paths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }).Count -gt 0 }
function Test-PcaQaCurrent([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  try {
    $qa = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    return (
      [string]$qa.schema_version -eq '2.0.0' -and
      [int]$qa.n_input -eq 5 -and
      [int]$qa.n_retained -eq 5 -and
      $qa.dimension_reduction_applied -eq $false -and
      $qa.reference_frozen -eq $true -and
      $qa.pca_input_lineage_verified -eq $true -and
      @($qa.raw_covariate_sha256.PSObject.Properties).Count -eq 5 -and
      @($qa.pca_raster_sha256.PSObject.Properties).Count -eq 5 -and
      [string]$qa.raw_provenance_sha256 -match '^[0-9a-f]{64}$' -and
      [string]$qa.reference_file_sha256 -match '^[0-9a-f]{64}$' -and
      [string]$qa.reference_hash -match '^[0-9a-f]{64}$'
    )
  } catch { return $false }
}

& "$internal\sync_settings.ps1"
RunChecked (PythonPath) @((Join-Path $pipeline 'configure_project_crs.py'), '--project-dir', $project)
$roi = Join-Path $project "00_XAC_LAP_VUNG_MIA\01_DAU_VAO\roi_field_area.geojson"
$fieldQaPath = Join-Path $project "00_XAC_LAP_VUNG_MIA\02_KET_QUA\field_area_QA.json"
$fieldApproved = $false
if (Test-Path -LiteralPath $fieldQaPath -PathType Leaf) {
  try {
    $fieldQa = Get-Content -LiteralPath $fieldQaPath -Raw | ConvertFrom-Json
    $currentRoiHash = if (Test-Path -LiteralPath $roi -PathType Leaf) { (Get-FileHash -LiteralPath $roi -Algorithm SHA256).Hash.ToLowerInvariant() } else { '' }
    $fieldApproved = [string]$fieldQa.status -eq 'APPROVED_FOR_SAMPLE_DESIGN' -and
      [string]$fieldQa.sample_design_roi.sha256 -eq $currentRoiHash
  } catch { $fieldApproved = $false }
}
if (-not (Test-Path -LiteralPath $roi -PathType Leaf) -or -not $fieldApproved) {
  Write-Host "[0/5] Dang xac lap/kiem tra ROI_field_area truoc khi rai diem..." -ForegroundColor Cyan
  & "$internal\run_field_area_workflow.ps1"
  if ($LASTEXITCODE -ne 0) {
    throw "Buoc xac lap vung mia chua dat cong khoa hoc. Xem 00_XAC_LAP_VUNG_MIA\02_KET_QUA\field_area_QA.json."
  }
  if (Test-Path -LiteralPath $fieldQaPath -PathType Leaf) {
    $fieldQa = Get-Content -LiteralPath $fieldQaPath -Raw | ConvertFrom-Json
    $currentRoiHash = if (Test-Path -LiteralPath $roi -PathType Leaf) { (Get-FileHash -LiteralPath $roi -Algorithm SHA256).Hash.ToLowerInvariant() } else { '' }
    $fieldApproved = [string]$fieldQa.status -eq 'APPROVED_FOR_SAMPLE_DESIGN' -and
      [string]$fieldQa.sample_design_roi.sha256 -eq $currentRoiHash
  }
}
if (-not $fieldApproved -or -not (Test-Path -LiteralPath $roi -PathType Leaf)) {
  throw "Chi ROI_field_area da duoc review va APPROVED_FOR_SAMPLE_DESIGN moi duoc dua vao thiet ke; candidate khong duoc tu dong su dung."
}
if (-not (Test-Path -LiteralPath $settings -PathType Leaf)) { throw "Thieu sampling.yml. Dat file tai: $settings" }
if (Test-Path -LiteralPath (Join-Path $input "soil_type.geojson")) {
  Write-Host "[OK] Co Soil Type; se dua nhom dat vao thiet ke." -ForegroundColor Green
} else {
  Write-Host "[INFO] Khong co Soil Type; se thiet ke chi voi PC covariates." -ForegroundColor Yellow
}

$python = PythonPath
$rscript = RscriptPath
$raw = @('CHIRPS.tif','DEM.tif','NDVI.tif','Slope.tif','TWI.tif') | ForEach-Object { Join-Path $work $_ }
$pcs = 1..5 | ForEach-Object { Join-Path $work ("PC{0}.tif" -f $_) }
$reference = Join-Path $internal "config\pca_model_reference.json"
$pcaQa = Join-Path $work "qa\pca_summary.json"
$coverageQa = Join-Path $work "qa\raw_covariate_coverage.json"
$needDownload = [bool]$ForceDownload
if (-not $needDownload) {
  & $python "projects\PHU_YEN_MOCK\_NOI_BO\pipeline\ensure_design_covariates.py"
  if ($LASTEXITCODE -ne 0) { $needDownload = $true }
}
if ($needDownload) {
  Write-Host "[1/5] Dang tai covariates full-area tu Google Earth Engine..." -ForegroundColor Cyan
  RunChecked $python @("projects\PHU_YEN_MOCK\_NOI_BO\pipeline\run_download_clhs.py")
  RunChecked $python @("projects\PHU_YEN_MOCK\_NOI_BO\pipeline\ensure_design_covariates.py")
} else {
  Write-Host "[1/5] Covariates full-area da qua coverage gate; khong goi GEE." -ForegroundColor Green
}
$coverage = Get-Content -LiteralPath $coverageQa -Raw | ConvertFrom-Json
$rawChanged = [bool]$coverage.raw_files_changed -or $needDownload
$pcaAssetsReady = (
  -not (NeedFiles $pcs) -and
  (Test-Path -LiteralPath $reference -PathType Leaf) -and
  [bool]$coverage.pca_grid_ready
)
if (
  $ForceDownload -or
  $rawChanged -or
  -not $pcaAssetsReady -or
  -not (Test-PcaQaCurrent $pcaQa)
) {
  if (-not $ForceDownload -and -not $rawChanged -and $pcaAssetsReady) {
    Write-Host "[2/5] Dang lam moi QA; tai su dung PCA rasters va frozen reference." -ForegroundColor Cyan
    $env:PCA_METADATA_ONLY = "1"
    try {
      RunChecked $rscript @("projects\PHU_YEN_MOCK\_NOI_BO\pipeline\build_clhs_pca.R")
    } finally {
      Remove-Item Env:PCA_METADATA_ONLY -ErrorAction SilentlyContinue
    }
  } else {
    Write-Host "[2/5] Dang tao/kiem tra PCA va khoa reference..." -ForegroundColor Cyan
    $env:PCA_STREAM_PYTHON = $python
    try {
      RunChecked $rscript @("projects\PHU_YEN_MOCK\_NOI_BO\pipeline\build_clhs_pca.R")
    } finally {
      Remove-Item Env:PCA_STREAM_PYTHON -ErrorAction SilentlyContinue
    }
  }
} else {
  Write-Host "[2/5] PCA va frozen reference da hop le; tai su dung." -ForegroundColor Green
}
# PCA may have been created or refreshed after the first coverage check. Re-run
# the gate so downstream sampling QA is based on the current PC rasters and lineage.
RunChecked $python @("projects\PHU_YEN_MOCK\_NOI_BO\pipeline\ensure_design_covariates.py")
$coverage = Get-Content -LiteralPath $coverageQa -Raw | ConvertFrom-Json
if (-not [bool]$coverage.pca_grid_ready) {
  throw "PCA lineage does not match the current raw covariates. Re-run Workflow 1 from the beginning."
}
Write-Host "[3/5] Dang xu ly Soil Type tuy chon va khoa lineage..." -ForegroundColor Cyan
RunChecked $python @("projects\PHU_YEN_MOCK\_NOI_BO\pipeline\prepare_clhs_soil.py")
RunChecked $python @("projects\PHU_YEN_MOCK\_NOI_BO\pipeline\ensure_design_covariates.py")
$coverage = Get-Content -LiteralPath $coverageQa -Raw | ConvertFrom-Json
if (-not [bool]$coverage.soil_lineage_ready) {
  $soilReasons = @($coverage.soil_lineage_assessment.reasons) -join '; '
  throw "Soil Type lineage was not locked by Workflow 1: $soilReasons"
}
Write-Host "[4/5] Dang tao hai phuong an lay mau va QA rieng..." -ForegroundColor Cyan
$env:RK_RSCRIPT = $rscript
RunChecked $python @("projects\PHU_YEN_MOCK\_NOI_BO\pipeline\run_design_clhs_official.py")
Write-Host "[5/5] Dang kiem tra metadata va QA khoa hoc..." -ForegroundColor Cyan
RunChecked $python @("projects\PHU_YEN_MOCK\_NOI_BO\pipeline\design_clhs_scientific_smoke_test.py")

$full = Join-Path $result "sample_cLHS_FULL.csv"
$reduced = Join-Path $result "sample_cLHS_REDUCED.csv"
if (-not (Test-Path -LiteralPath $full) -or -not (Test-Path -LiteralPath $reduced)) { throw "Khong tao duoc day du hai phuong an lay mau." }
Write-Host "HOAN TAT THIET KE LAY MAU" -ForegroundColor Green
Write-Host "FULL:    $full"
Write-Host "REDUCED: $reduced"
