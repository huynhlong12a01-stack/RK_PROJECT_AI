$ErrorActionPreference = 'Stop'
$internal = $PSScriptRoot
$project = Split-Path -Parent $internal
$root = [IO.Path]::GetFullPath((Join-Path $project '..\..'))
$python = Join-Path $root '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
  throw 'Khong tim thay Python Google Earth Engine. Hay chay CAI_DAT_UNG_DUNG.bat.'
}
& $python (Join-Path $internal 'pipeline\extract_positive_feature_knowledge_atomic.py') --project-dir $project
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $python (Join-Path $internal 'pipeline\ingest_positive_feature_knowledge.py') --project-dir $project
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
exit 0