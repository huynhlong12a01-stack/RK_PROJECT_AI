param([switch]$PreflightOnly)

$ErrorActionPreference = 'Stop'
$internal = $PSScriptRoot
$project = Split-Path -Parent $internal
$pipeline = Join-Path $internal 'pipeline\interpret_sugarcane_area_final.py'
$input = Join-Path $project '00_XAC_LAP_VUNG_MIA\01_DAU_VAO'
$result = Join-Path $project '00_XAC_LAP_VUNG_MIA\02_KET_QUA'
New-Item -ItemType Directory -Path $input, $result -Force | Out-Null

function PythonPath {
  $preferred = 'D:\apps\POINT_PLANNING_APP\.venv\Scripts\python.exe'
  if (Test-Path -LiteralPath $preferred) { return $preferred }
  $cmd = Get-Command python -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  throw 'Khong tim thay Python. Hay chay install_dependencies.ps1.'
}

$settings = Join-Path $input 'interpretation.yml'
if (-not (Test-Path -LiteralPath $settings -PathType Leaf)) {
  throw "Thieu interpretation.yml: $settings"
}
Write-Host 'XAC LAP VUNG MIA TRUOC THIET KE LAY MAU' -ForegroundColor Cyan
Write-Host '  Neu co ROI field: kiem tra va chuyen sang buoc thiet ke.'
Write-Host '  Neu chi co ROI search: phan loai ve tinh tao UNG VIEN, khong tu phe duyet.'
$arguments = @($pipeline, '--project-dir', $project)
if ($PreflightOnly) { $arguments += '--preflight-only' }
& (PythonPath) @arguments
if ($LASTEXITCODE -ne 0) {
  Write-Host 'Quy trinh dung tai cong khoa hoc. Xem field_area_QA.json va HUONG_DAN.md.' -ForegroundColor Yellow
  exit $LASTEXITCODE
}
$qaPath = Join-Path $result 'field_area_QA.json'
if (Test-Path -LiteralPath $qaPath) {
  $qa = Get-Content -LiteralPath $qaPath -Raw | ConvertFrom-Json
  Write-Host ("Trang thai: {0}" -f $qa.status) -ForegroundColor Green
}
exit 0
