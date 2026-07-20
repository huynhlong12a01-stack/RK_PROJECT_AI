param(
  [string]$Library = "knowledge\library",
  [string]$Inventory = "knowledge\metadata\local_library_inventory.csv",
  [string]$Draft = "knowledge\metadata\local_source_metadata_draft.csv"
)

$ErrorActionPreference = "Stop"
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
Set-Location $root
$rLibrary = Join-Path $root '_UNG_DUNG\runtime\R_library'
New-Item -ItemType Directory -Path $rLibrary -Force | Out-Null
$env:R_LIBS_USER = $rLibrary
$rscriptCmd = Get-Command Rscript -ErrorAction SilentlyContinue
if (-not $rscriptCmd) {
  Write-Error "Rscript was not found on PATH. Please install R or add Rscript to PATH."
  exit 1
}

& $rscriptCmd.Source "_UNG_DUNG\engine\scripts\rag_inventory_library.R" --library $Library --inventory $Inventory --draft $Draft
if ($LASTEXITCODE -ne 0) {
  Write-Error "RAG local library inventory failed."
  exit $LASTEXITCODE
}

Write-Host "[INFO] RAG local library inventory finished."