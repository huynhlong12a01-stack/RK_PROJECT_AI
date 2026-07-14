param(
  [switch]$FullPipeline
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $projectRoot

$rscript = Get-Command Rscript -ErrorAction SilentlyContinue
if (-not $rscript) {
  throw "Rscript was not found on PATH."
}

Write-Host "[INFO] Running transform tests..."
& $rscript.Source "scripts/transform_smoke_test.R"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "[INFO] Running nested spatial validation tests..."
& $rscript.Source "scripts/scientific_validation_smoke_test.R"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($FullPipeline) {
  Write-Host "[INFO] Running synthetic full pipeline test..."
  & $rscript.Source "scripts/full_pipeline_smoke_test.R"
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host "[OK] Scientific smoke tests completed."
