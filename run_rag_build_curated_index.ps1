param(
  [string]$Sources = "knowledge\metadata\sources.csv",
  [string]$EvidenceDir = "knowledge\notes\evidence_cards",
  [string]$Output = "knowledge\index\curated"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$rscriptCmd = Get-Command Rscript -ErrorAction SilentlyContinue
if (-not $rscriptCmd) {
  Write-Error "Rscript was not found on PATH. Please install R or add Rscript to PATH."
  exit 1
}

& $rscriptCmd.Source "scripts\rag_build_curated_index.R" --sources $Sources --evidence_dir $EvidenceDir --output $Output
if ($LASTEXITCODE -ne 0) {
  Write-Error "Curated RAG index build failed."
  exit $LASTEXITCODE
}

Write-Host "[INFO] Curated RAG index build finished."
