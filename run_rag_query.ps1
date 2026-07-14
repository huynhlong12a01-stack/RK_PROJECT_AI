param(
  [Parameter(Mandatory=$true)]
  [string]$Query,
  [string]$Chunks = "knowledge/index/curated/chunks.jsonl",
  [string]$Taxonomy = "knowledge/metadata/topic_taxonomy.json",
  [string]$Output = "agent/responses/rag_query_result.json",
  [int]$TopK = 8
)

$ErrorActionPreference = "Stop"
Write-Host "[INFO] Querying local RAG index..."
Write-Host "[INFO] Query: $Query"
if (-not (Get-Command Rscript -ErrorAction SilentlyContinue)) {
  throw "Rscript was not found on PATH."
}
Rscript scripts/rag_query_local_index.R --query $Query --chunks $Chunks --taxonomy $Taxonomy --output $Output --top_k $TopK
if ($LASTEXITCODE -ne 0) {
  throw "RAG query failed with exit code $LASTEXITCODE."
}
Write-Host "[INFO] RAG query completed."
