$ErrorActionPreference = "Stop"
$internal = $PSScriptRoot
$project = Split-Path -Parent $internal
$fieldInput = Join-Path $project "00_XAC_LAP_VUNG_MIA\01_DAU_VAO"
$fieldResult = Join-Path $project "00_XAC_LAP_VUNG_MIA\02_KET_QUA"
$designInput = Join-Path $project "01_THIET_KE_LAY_MAU\01_DAU_VAO"
$designResult = Join-Path $project "01_THIET_KE_LAY_MAU\02_KET_QUA"
$mapInputDir = Join-Path $project "02_NOI_SUY_BAN_DO\01_DAU_VAO"
$mapInput = Join-Path $mapInputDir "sample_actual.csv"
$indicatorMetadata = Join-Path $mapInputDir "indicator_metadata.yml"
$outsideReview = Join-Path $mapInputDir "outside_sample_review.csv"
$mapResult = Join-Path $project "02_NOI_SUY_BAN_DO\02_KET_QUA"
$designWork = Join-Path $internal "work\design"
$interpolationWork = Join-Path $internal "work\interpolation"

function Exists([string]$Path) { Test-Path -LiteralPath $Path -PathType Leaf }
function Rows([string]$Path) { if (Exists $Path) { try { @(Import-Csv -LiteralPath $Path).Count } catch { 0 } } else { 0 } }
function State([bool]$Ready) { if ($Ready) { 'READY' } else { 'WAITING' } }
function ReadJson([string]$Path) {
  if (-not (Exists $Path)) { return $null }
  try { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { $null }
}

$roi = Join-Path $designInput 'roi.geojson'
$soil = Join-Path $designInput 'soil_type.geojson'
$settings = Join-Path $designInput 'sampling.yml'
$rawCount = @('CHIRPS.tif','DEM.tif','NDVI.tif','Slope.tif','TWI.tif' | Where-Object { Exists (Join-Path $designWork $_) }).Count
$pcCount = @(1..5 | Where-Object { Exists (Join-Path $designWork ("PC{0}.tif" -f $_)) }).Count
$full = Join-Path $designResult 'sample_cLHS_FULL.csv'
$reduced = Join-Path $designResult 'sample_cLHS_REDUCED.csv'
$designQa = ReadJson (Join-Path $designResult 'sampling_QA.json')
$methodStatus = if ($designQa -and $designQa.method_metadata.is_original_clhs_optimizer_core -eq $true) {
  'CRAN clhs core + explicit spatial hybrid'
} elseif ($designQa -and $designQa.method_metadata.is_clhs_like -eq $true) {
  'DECLARED FALLBACK: cLHS-like'
} else { 'NOT CHECKED' }
$coverageStatus = if ($designQa -and $designQa.raw_covariate_coverage.raw_covariates.coverage_fraction -ne $null) {
  ('{0:P1}' -f [double]$designQa.raw_covariate_coverage.raw_covariates.coverage_fraction)
} else { 'NOT CHECKED' }

$fieldProvided = @(Get-ChildItem -LiteralPath $fieldInput -File -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -eq 'roi_field_area' }).Count -gt 0
$searchProvided = @(Get-ChildItem -LiteralPath $fieldInput -File -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -eq 'roi_search' }).Count -gt 0
$labelProvided = @(Get-ChildItem -LiteralPath $fieldInput -File -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -eq 'sugarcane_labels' }).Count -gt 0
$fieldQa = ReadJson (Join-Path $fieldResult 'field_area_QA.json')
$fieldStatus = if ($fieldQa -and $fieldQa.status) { [string]$fieldQa.status } elseif ($fieldProvided) { 'READY_TO_CHECK' } elseif ($searchProvided -and $labelProvided) { 'READY_TO_CLASSIFY' } else { 'WAITING_INPUT' }
Write-Host 'BUOC 0 - XAC LAP VUNG MIA' -ForegroundColor Cyan
Write-Host ("  ROI field area:   {0}" -f $(if ($fieldProvided -or (Exists $roi)) { 'PROVIDED' } else { 'NOT PROVIDED' }))
Write-Host ("  ROI search:       {0}" -f $(if ($searchProvided) { 'PROVIDED' } else { 'OPTIONAL - NOT PROVIDED' }))
Write-Host ("  Verified labels:  {0}" -f $(if ($labelProvided) { 'PROVIDED' } else { 'OPTIONAL - NOT PROVIDED' }))
Write-Host ("  Stage status:     {0}" -f $fieldStatus)
Write-Host ''

Write-Host 'QUY TRINH 1 - THIET KE LAY MAU' -ForegroundColor Cyan
Write-Host ("  ROI:              {0}" -f (State (Exists $roi)))
Write-Host ("  Soil Type:        {0}" -f $(if (Exists $soil) { 'OPTIONAL - PROVIDED' } else { 'OPTIONAL - NOT PROVIDED' }))
Write-Host ("  sampling.yml:     {0}" -f (State (Exists $settings)))
Write-Host ("  Covariates:       {0}/5; ROI coverage {1}" -f $rawCount, $coverageStatus)
Write-Host ("  PCA:              {0}/5" -f $pcCount)
Write-Host ("  Method:           {0}" -f $methodStatus)
Write-Host ("  FULL plan:        {0} rows" -f (Rows $full))
Write-Host ("  REDUCED plan:     {0} rows (not guaranteed equal to FULL)" -f (Rows $reduced))

$sampleRows = Rows $mapInput
$filledIndicators = @()
if ($sampleRows -gt 0) {
  $data = @(Import-Csv -LiteralPath $mapInput)
  $names = @($data[0].PSObject.Properties.Name | Where-Object { $_ -notin @('code','lat','lon') })
  $filledIndicators = @($names | Where-Object { $nm = $_; @($data | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.$nm) }).Count -gt 0 })
}
$confirmedMetadata = if (Exists $indicatorMetadata) {
  @(Select-String -LiteralPath $indicatorMetadata -Pattern '^\s+confirmed:\s*true\s*$').Count
} else { 0 }
$actualPcCount = @(1..5 | Where-Object { Exists (Join-Path $interpolationWork ("PC{0}.tif" -f $_)) }).Count
$mapCount = @(Get-ChildItem -LiteralPath (Join-Path $mapResult 'maps') -Filter '*.tif' -File -Recurse -ErrorAction SilentlyContinue).Count
$preflight = ReadJson (Join-Path $interpolationWork 'qa\preflight_summary.json')
$insideCount = if ($preflight) { [int]$preflight.n_inside_roi } else { 0 }
$outsideCount = if ($preflight) { [int]$preflight.n_outside_roi } else { 0 }
$pendingOutside = if ($preflight -and $preflight.n_pending_outside_review -ne $null) { [int]$preflight.n_pending_outside_review } else { 0 }
$pcaTrust = if ($preflight -and $preflight.current_pca_provenance_valid -eq $true) { 'VERIFIED' } elseif ($actualPcCount -eq 5) { 'UNVERIFIED' } else { 'WAITING' }

Write-Host ''
Write-Host 'QUY TRINH 2 - NOI SUY BAN DO' -ForegroundColor Cyan
Write-Host ("  sample_actual:    {0} rows ({1} inside, {2} outside ROI)" -f $sampleRows, $insideCount, $outsideCount)
Write-Host ("  Outside review:   {0} pending" -f $pendingOutside)
Write-Host ("  Indicators ready: {0}; metadata confirmed: {1}" -f $filledIndicators.Count, $confirmedMetadata)
Write-Host ("  Actual PCA:       {0}/5; provenance {1}" -f $actualPcCount, $pcaTrust)
Write-Host ("  Output maps:      {0}" -f $mapCount)
if ($pendingOutside -gt 0) { Write-Host '  Next: review outside_sample_review.csv (22 outside points only).' -ForegroundColor Yellow }
if ($filledIndicators.Count -eq 0) { Write-Host '  Next: paste numeric lab values into sample_actual.csv when results arrive.' -ForegroundColor Yellow }
elseif ($confirmedMetadata -lt $filledIndicators.Count) { Write-Host '  Next: confirm method/unit in indicator_metadata.yml for every filled indicator.' -ForegroundColor Yellow }