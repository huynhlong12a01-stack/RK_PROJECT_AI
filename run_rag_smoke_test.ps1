param(
  [string]$Output = "agent\responses\rag_smoke_test.json"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$rscriptCmd = Get-Command Rscript -ErrorAction SilentlyContinue
if (-not $rscriptCmd) {
  Write-Error "Rscript was not found on PATH. Please install R or add Rscript to PATH."
  exit 1
}

& $rscriptCmd.Source "scripts\rag_validate_metadata.R" $Output
if ($LASTEXITCODE -ne 0) {
  Write-Error "RAG smoke test failed."
  exit $LASTEXITCODE
}

Write-Host "[INFO] RAG smoke test finished."