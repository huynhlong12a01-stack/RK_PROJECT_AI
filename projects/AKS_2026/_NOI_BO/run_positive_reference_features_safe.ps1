$ErrorActionPreference = 'Stop'
$internal = $PSScriptRoot
$project = Split-Path -Parent $internal
$python = 'D:\apps\POINT_PLANNING_APP\.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python)) {
  $found = Get-Command python -ErrorAction SilentlyContinue
  if (-not $found) { throw 'Khong tim thay Python.' }
  $python = $found.Source
}
& $python (Join-Path $internal 'pipeline\build_positive_feature_library_safe.py') --project-dir $project
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
exit 0
