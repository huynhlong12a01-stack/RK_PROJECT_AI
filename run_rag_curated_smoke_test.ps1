param(
  [string]$EnglishQuery = "regression kriging residual variogram",
  [string]$VietnameseQuery = "danh gia cheo khong gian"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$rscriptCmd = Get-Command Rscript -ErrorAction SilentlyContinue
if (-not $rscriptCmd) {
  throw "Rscript was not found on PATH."
}

$indexDir = "knowledge\index\curated"
$validationOutput = Join-Path $indexDir ".smoke_validation.json"
$englishOutput = Join-Path $indexDir ".smoke_query_en.json"
$vietnameseOutput = Join-Path $indexDir ".smoke_query_vi.json"
$temporaryOutputs = @($validationOutput, $englishOutput, $vietnameseOutput)

try {
  & $rscriptCmd.Source "scripts\rag_validate_metadata.R" $validationOutput
  if ($LASTEXITCODE -ne 0) { throw "Curated metadata validation failed." }

  & $rscriptCmd.Source "scripts\rag_build_curated_index.R" --output $indexDir
  if ($LASTEXITCODE -ne 0) { throw "Curated index build failed." }

  & $rscriptCmd.Source "scripts\rag_query_local_index.R" --query $EnglishQuery --output $englishOutput --top_k 5
  if ($LASTEXITCODE -ne 0) { throw "English curated query failed." }

  & $rscriptCmd.Source "scripts\rag_query_local_index.R" --query $VietnameseQuery --output $vietnameseOutput --top_k 5
  if ($LASTEXITCODE -ne 0) { throw "Vietnamese curated query failed." }

  $english = Get-Content -Raw -LiteralPath $englishOutput | ConvertFrom-Json
  $vietnamese = Get-Content -Raw -LiteralPath $vietnameseOutput | ConvertFrom-Json

  if ($english.n_matches -lt 1) { throw "English smoke query returned no matches." }
  if ($vietnamese.n_matches -lt 1) { throw "Vietnamese smoke query returned no matches." }
  if (@($vietnamese.alias_groups_matched).Count -lt 1) {
    throw "Vietnamese smoke query did not activate a taxonomy alias group."
  }

  foreach ($result in @($english, $vietnamese)) {
    $linked = @($result.matches | Where-Object { @($_.citation_links).Count -gt 0 })
    if ($linked.Count -lt 1) { throw "A smoke query returned matches but no DOI/URL citation links." }
  }

  Write-Host "[INFO] Curated RAG smoke test passed."
  Write-Host "[INFO] English matches: $($english.n_matches)"
  Write-Host "[INFO] Vietnamese matches: $($vietnamese.n_matches)"
}
finally {
  foreach ($path in $temporaryOutputs) {
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
  }
}
