param(
  [string]$Inventory = "knowledge\metadata\local_library_inventory.csv",
  [string]$Output = "knowledge\index\local_chunks",
  [int]$ChunkChars = 2500,
  [int]$OverlapChars = 250
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

& $rscriptCmd.Source "_UNG_DUNG\engine\scripts\rag_build_local_index.R" --inventory $Inventory --output $Output --chunk_chars $ChunkChars --overlap_chars $OverlapChars
if ($LASTEXITCODE -ne 0) {
  Write-Error "RAG local index build failed."
  exit $LASTEXITCODE
}

Write-Host "[INFO] RAG local index build finished."