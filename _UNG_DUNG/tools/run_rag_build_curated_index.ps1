param(
  [string]$Sources = "knowledge\metadata\sources.csv",
  [string]$EvidenceDir = "knowledge\notes\evidence_cards",
  [string]$Output = "knowledge\index\curated"
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

& $rscriptCmd.Source "_UNG_DUNG\engine\scripts\rag_build_curated_index.R" --sources $Sources --evidence_dir $EvidenceDir --output $Output
if ($LASTEXITCODE -ne 0) {
  Write-Error "Curated RAG index build failed."
  exit $LASTEXITCODE
}

Write-Host "[INFO] Curated RAG index build finished."
