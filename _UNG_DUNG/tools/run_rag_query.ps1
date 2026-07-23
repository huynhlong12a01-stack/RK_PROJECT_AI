param(
  [Parameter(Mandatory=$true)]
  [string]$Query,
  [string]$Chunks = "knowledge/index/curated/chunks.jsonl",
  [string]$Taxonomy = "knowledge/metadata/topic_taxonomy.json",
  [string]$Output = "_UNG_DUNG/runtime/rag_query_result.json",
  [int]$TopK = 8
)

$ErrorActionPreference = "Stop"
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
Set-Location $root
$rLibrary = Join-Path $root '_UNG_DUNG\runtime\R_library'
New-Item -ItemType Directory -Path $rLibrary -Force | Out-Null
$env:R_LIBS_USER = $rLibrary
Write-Host "[INFO] Querying local RAG index..."
Write-Host "[INFO] Query: $Query"
if (-not (Get-Command Rscript -ErrorAction SilentlyContinue)) {
  throw "Rscript was not found on PATH."
}
Rscript _UNG_DUNG/engine/scripts/rag_query_local_index.R --query $Query --chunks $Chunks --taxonomy $Taxonomy --output $Output --top_k $TopK
if ($LASTEXITCODE -ne 0) {
  throw "RAG query failed with exit code $LASTEXITCODE."
}
Write-Host "[INFO] RAG query completed."
