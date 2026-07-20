param(
  [string]$EnglishQuery = "regression kriging residual variogram",
  [string]$VietnameseQuery = "danh gia cheo khong gian"
)

$ErrorActionPreference = "Stop"
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
Set-Location $root
$rLibrary = Join-Path $root '_UNG_DUNG\runtime\R_library'
New-Item -ItemType Directory -Path $rLibrary -Force | Out-Null
$env:R_LIBS_USER = $rLibrary
$rscriptCmd = Get-Command Rscript -ErrorAction SilentlyContinue
if (-not $rscriptCmd) {
  throw "Rscript was not found on PATH."
}

$indexDir = "knowledge\index\curated"
$validationOutput = Join-Path $indexDir ".smoke_validation.json"
$englishOutput = Join-Path $indexDir ".smoke_query_en.json"
$vietnameseOutput = Join-Path $indexDir ".smoke_query_vi.json"
$privacyOutput = Join-Path $indexDir ".smoke_query_privacy.json"
$fallbackOutput = Join-Path $indexDir ".smoke_query_gee_fallback.json"
$temporaryOutputs = @($validationOutput, $englishOutput, $vietnameseOutput, $privacyOutput, $fallbackOutput)

try {
  & $rscriptCmd.Source "_UNG_DUNG\engine\scripts\rag_validate_metadata.R" $validationOutput
  if ($LASTEXITCODE -ne 0) { throw "Curated metadata validation failed." }

  & $rscriptCmd.Source "_UNG_DUNG\engine\scripts\rag_build_curated_index.R" --output $indexDir
  if ($LASTEXITCODE -ne 0) { throw "Curated index build failed." }

  & $rscriptCmd.Source "_UNG_DUNG\engine\scripts\rag_query_local_index.R" --query $EnglishQuery --output $englishOutput --top_k 5
  if ($LASTEXITCODE -ne 0) { throw "English curated query failed." }

  & $rscriptCmd.Source "_UNG_DUNG\engine\scripts\rag_query_local_index.R" --query $VietnameseQuery --output $vietnameseOutput --top_k 5
  if ($LASTEXITCODE -ne 0) { throw "Vietnamese curated query failed." }

  & $rscriptCmd.Source "_UNG_DUNG\engine\scripts\rag_query_local_index.R" --query "PCA cuc bo tu Workflow1 raw; no external data transfer; privacy provenance" --output $privacyOutput --top_k 5
  if ($LASTEXITCODE -ne 0) { throw "Local PCA privacy query failed." }

  & $rscriptCmd.Source "_UNG_DUNG\engine\scripts\rag_query_local_index.R" --query "GEE fallback fixed ROI bounding envelope buffer; download envelope is not prediction domain" --output $fallbackOutput --top_k 5
  if ($LASTEXITCODE -ne 0) { throw "GEE fallback query failed." }

  $english = Get-Content -Raw -LiteralPath $englishOutput | ConvertFrom-Json
  $vietnamese = Get-Content -Raw -LiteralPath $vietnameseOutput | ConvertFrom-Json
  $privacy = Get-Content -Raw -LiteralPath $privacyOutput | ConvertFrom-Json
  $fallback = Get-Content -Raw -LiteralPath $fallbackOutput | ConvertFrom-Json

  if ($english.n_matches -lt 1) { throw "English smoke query returned no matches." }
  if ($vietnamese.n_matches -lt 1) { throw "Vietnamese smoke query returned no matches." }
  if (@($vietnamese.alias_groups_matched).Count -lt 1) {
    throw "Vietnamese smoke query did not activate a taxonomy alias group."
  }
  $privacyAliases = ($privacy.alias_groups_matched | ConvertTo-Json -Depth 10 -Compress)
  if ($privacy.n_matches -lt 1 -or $privacyAliases -notmatch 'data_provenance' -or $privacyAliases -notmatch 'pca') {
    throw "Local PCA privacy query did not activate pca and data_provenance aliases."
  }
  $fallbackAliases = ($fallback.alias_groups_matched | ConvertTo-Json -Depth 10 -Compress)
  if ($fallback.n_matches -lt 1 -or $fallbackAliases -notmatch 'gee' -or $fallbackAliases -notmatch 'scale_and_support') {
    throw "GEE fallback query did not activate gee and scale_and_support aliases."
  }

  foreach ($result in @($english, $vietnamese, $privacy, $fallback)) {
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
