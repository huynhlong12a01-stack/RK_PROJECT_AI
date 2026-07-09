param(
  [string]$Library = "knowledge\library",
  [string]$Inventory = "knowledge\metadata\local_library_inventory.csv",
  [string]$Draft = "knowledge\metadata\local_source_metadata_draft.csv"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$rscriptCmd = Get-Command Rscript -ErrorAction SilentlyContinue
if (-not $rscriptCmd) {
  Write-Error "Rscript was not found on PATH. Please install R or add Rscript to PATH."
  exit 1
}

& $rscriptCmd.Source "scripts\rag_inventory_library.R" --library $Library --inventory $Inventory --draft $Draft
if ($LASTEXITCODE -ne 0) {
  Write-Error "RAG local library inventory failed."
  exit $LASTEXITCODE
}

Write-Host "[INFO] RAG local library inventory finished."