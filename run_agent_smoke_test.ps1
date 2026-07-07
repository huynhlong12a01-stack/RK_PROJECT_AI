$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

Write-Host "[INFO] Running agent smoke test..."
$rscriptCmd = Get-Command Rscript -ErrorAction SilentlyContinue
if (-not $rscriptCmd) {
  Write-Error "Rscript was not found on PATH. Please install R or add Rscript to PATH."
  exit 1
}

& $rscriptCmd.Source "scripts\agent_smoke_test.R"
if ($LASTEXITCODE -ne 0) {
  Write-Error "Agent smoke test failed."
  exit $LASTEXITCODE
}
Write-Host "[INFO] Agent smoke test passed."