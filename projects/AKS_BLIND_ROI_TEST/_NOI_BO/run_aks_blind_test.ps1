param([switch]$SkipPostHocComparison)

$ErrorActionPreference = 'Stop'
$internal = $PSScriptRoot
$project = Split-Path -Parent $internal
$root = [IO.Path]::GetFullPath((Join-Path $project '..\..'))
$inputDir = Join-Path $project '00_XAC_LAP_VUNG_MIA\01_DAU_VAO'
$knownRoi = Join-Path $root 'projects\AKS_2026\00_XAC_LAP_VUNG_MIA\01_DAU_VAO\roi_field_area.geojson'

function PythonPath {
  $local = Join-Path $root '.venv\Scripts\python.exe'
  if (Test-Path -LiteralPath $local -PathType Leaf) { return $local }
  $cmd = Get-Command python -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  throw 'Khong tim thay Python. Hay chay CAI_DAT_UNG_DUNG.bat.'
}

$forbidden = @(Get-ChildItem -LiteralPath $inputDir -File -ErrorAction SilentlyContinue |
  Where-Object { $_.BaseName -eq 'roi_field_area' })
if ($forbidden.Count -gt 0) {
  throw 'AKS blind test tu choi ROI_field_area trong thu muc inference.'
}

$python = PythonPath
Write-Host 'AKS BLIND ROI TEST - GIAI DOAN INFERENCE' -ForegroundColor Cyan
& $python (Join-Path $internal 'pipeline\prepare_aks_blind_inputs.py') --project-dir $project --buffer-m 5000
if ($LASTEXITCODE -ne 0) { throw 'Khong the tao blind inputs.' }

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $project 'RUN.ps1') interpret
$inferenceExit = $LASTEXITCODE
if ($inferenceExit -ne 0) {
  Write-Host 'Inference dung tai cong QA; withheld ROI chua duoc mo.' -ForegroundColor Yellow
  exit $inferenceExit
}

if (-not $SkipPostHocComparison) {
  if (-not (Test-Path -LiteralPath $knownRoi -PathType Leaf)) {
    throw 'Thieu withheld AKS ROI cho doi chieu hau nghiem.'
  }
  Write-Host 'AKS BLIND ROI TEST - DOI CHIEU HAU NGHIEM' -ForegroundColor Cyan
  & $python (Join-Path $internal 'pipeline\evaluate_aks_blind_reconstruction.py') --project-dir $project --withheld-roi $knownRoi
  if ($LASTEXITCODE -ne 0) { throw 'Doi chieu hau nghiem that bai.' }
}
Write-Host 'Hoan tat AKS blind ROI test.' -ForegroundColor Green
exit 0
