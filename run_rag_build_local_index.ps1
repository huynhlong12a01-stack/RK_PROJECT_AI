param(
  [string]$Inventory = "knowledge\metadata\local_library_inventory.csv",
  [string]$Output = "knowledge\index\local_chunks",
  [int]$ChunkChars = 2500,
  [int]$OverlapChars = 250
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$rscriptCmd = Get-Command Rscript -ErrorAction SilentlyContinue
if (-not $rscriptCmd) {
  Write-Error "Rscript was not found on PATH. Please install R or add Rscript to PATH."
  exit 1
}

& $rscriptCmd.Source "scripts\rag_build_local_index.R" --inventory $Inventory --output $Output --chunk_chars $ChunkChars --overlap_chars $OverlapChars
if ($LASTEXITCODE -ne 0) {
  Write-Error "RAG local index build failed."
  exit $LASTEXITCODE
}

Write-Host "[INFO] RAG local index build finished."