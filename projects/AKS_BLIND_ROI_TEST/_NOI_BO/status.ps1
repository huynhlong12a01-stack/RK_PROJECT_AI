$ErrorActionPreference = "Stop"
$internal = $PSScriptRoot
$project = Split-Path -Parent $internal
$projectSettings = Join-Path $project "THONG_SO_DU_AN.yml"
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
function ReadSetting([string]$Path, [string]$Name, [string]$Default = '') {
  if (-not (Exists $Path)) { return $Default }
  $text = [IO.File]::ReadAllText($Path)
  $match = [regex]::Match($text, "(?m)^[ \t]*" + [regex]::Escape($Name) + "[ \t]*:[ \t]*([^#\r\n]+)")
  if ($match.Success) { return $match.Groups[1].Value.Trim().Trim('"').Trim("'") }
  return $Default
}

$roi = Join-Path $fieldInput 'roi_field_area.geojson'
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
$currentCoverageQa = ReadJson (Join-Path $designWork 'qa\raw_covariate_coverage.json')
$rawProvenanceReady = $currentCoverageQa -and
  [string]$currentCoverageQa.status -eq 'ready' -and
  $currentCoverageQa.raw_provenance_assessment.valid -eq $true
$pcaLineageReady = $rawProvenanceReady -and
  $currentCoverageQa.pca_grid_ready -eq $true -and
  $currentCoverageQa.pca_lineage_assessment.valid -eq $true
$soilLineageReady = $rawProvenanceReady -and
  $currentCoverageQa.soil_lineage_ready -eq $true -and
  $currentCoverageQa.soil_lineage_assessment.valid -eq $true
$rawProvenanceStatus = if ($rawProvenanceReady) { 'VERIFIED' } elseif ($rawCount -gt 0) { 'STALE/UNVERIFIED' } else { 'WAITING' }
$pcaLineageStatus = if ($pcaLineageReady) { 'VERIFIED' } elseif ($pcCount -gt 0) { 'STALE/UNVERIFIED' } else { 'WAITING' }
$soilLineageStatus = if ($soilLineageReady) { 'VERIFIED' } elseif ((Exists $soil) -or (Exists (Join-Path $designWork 'Soil_Group_Code.tif'))) { 'STALE/UNVERIFIED' } else { 'WAITING' }
$coverageStatus = if ($rawProvenanceReady -and $currentCoverageQa.raw_covariates.coverage_fraction -ne $null) {
  ('{0:P1}' -f [double]$currentCoverageQa.raw_covariates.coverage_fraction)
} elseif ($currentCoverageQa -and $currentCoverageQa.current_assessment.coverage_fraction -ne $null) {
  ('{0:P1} (STALE/UNVERIFIED)' -f [double]$currentCoverageQa.current_assessment.coverage_fraction)
} elseif ($designQa -and $designQa.raw_covariate_coverage.raw_covariates.coverage_fraction -ne $null) {
  ('{0:P1} (LEGACY QA ONLY)' -f [double]$designQa.raw_covariate_coverage.raw_covariates.coverage_fraction)
} else { 'NOT CHECKED' }

$fieldProvided = @(Get-ChildItem -LiteralPath $fieldInput -File -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -eq 'roi_field_area' }).Count -gt 0
$searchProvided = @(Get-ChildItem -LiteralPath $fieldInput -File -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -eq 'roi_search' }).Count -gt 0
$labelProvided = @(Get-ChildItem -LiteralPath $fieldInput -File -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -eq 'sugarcane_labels' }).Count -gt 0
$fieldQa = ReadJson (Join-Path $fieldResult 'field_area_QA.json')
$fieldStatus = if ($fieldQa -and $fieldQa.status) { [string]$fieldQa.status } elseif ($fieldProvided) { 'READY_TO_CHECK' } elseif ($searchProvided -and $labelProvided) { 'READY_TO_CLASSIFY' } else { 'WAITING_INPUT' }
Write-Host 'CAU HINH CHUNG' -ForegroundColor Cyan
Write-Host ("  THONG_SO_DU_AN:  {0}" -f (State (Exists $projectSettings)))
if (-not (Exists $projectSettings)) { Write-Host '  Next: tao/khoi phuc THONG_SO_DU_AN.yml o thu muc du an.' -ForegroundColor Yellow }
Write-Host ''
Write-Host 'BUOC 0 - XAC LAP VUNG MIA' -ForegroundColor Cyan
Write-Host ("  ROI field area:   {0}" -f $(if ($fieldProvided -or (Exists $roi)) { 'PROVIDED' } else { 'NOT PROVIDED' }))
Write-Host ("  ROI search:       {0}" -f $(if ($searchProvided) { 'PROVIDED' } else { 'OPTIONAL - NOT PROVIDED' }))
Write-Host ("  Verified labels:  {0}" -f $(if ($labelProvided) { 'PROVIDED' } else { 'OPTIONAL - NOT PROVIDED' }))
Write-Host ("  Stage status:     {0}" -f $fieldStatus)
Write-Host ''

Write-Host 'QUY TRINH 1 - THIET KE LAY MAU' -ForegroundColor Cyan
Write-Host ("  ROI:              {0}" -f (State (Exists $roi)))
Write-Host ("  Soil Type:        {0}; lineage {1}" -f $(if (Exists $soil) { 'OPTIONAL - PROVIDED' } else { 'OPTIONAL - NOT PROVIDED' }), $soilLineageStatus)
Write-Host ("  sampling.yml:     {0}" -f (State (Exists $settings)))
Write-Host ("  Covariates:       {0}/5; raw provenance {1}; ROI coverage {2}" -f $rawCount, $rawProvenanceStatus, $coverageStatus)
Write-Host ("  PCA:              {0}/5; lineage {1}" -f $pcCount, $pcaLineageStatus)
Write-Host ("  Method:           {0}" -f $methodStatus)
Write-Host ("  FULL plan:        {0} rows" -f (Rows $full))
Write-Host ("  REDUCED plan:     {0} rows (not guaranteed equal to FULL)" -f (Rows $reduced))
if (($rawCount -gt 0 -or $pcCount -gt 0) -and (-not $rawProvenanceReady -or -not $pcaLineageReady -or -not $soilLineageReady)) {
  Write-Host '  Next: Re-run CHAY_THIET_KE_LAY_MAU.bat de tai lai covariates va khoa raw/PCA/Soil lineage.' -ForegroundColor Yellow
}

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
$supportDownload = ReadJson (Join-Path $interpolationWork 'qa\gee_support_download_summary.json')
$privacy = if ($supportDownload) { $supportDownload.privacy_gate } else { $null }
$privacyVerified = $privacy -and
  [string]$privacy.status -eq 'verified_before_gee_initialization' -and
  [string]$privacy.support_geometry_policy -eq 'fixed_roi_buffer_no_sample_geometry' -and
  [string]$privacy.geometry_source -eq 'reviewed_roi_bounding_envelope_plus_fixed_metric_buffer' -and
  [string]$privacy.geometry_derivation -eq 'sf_projected_bbox_then_st_buffer_nQuadSegs_30' -and
  [string]$privacy.coverage_guarantee -eq 'contains_the_fixed_metric_buffer_of_the_reviewed_roi' -and
  $privacy.geometry_certified_by_preflight_hash_chain -eq $true -and
  $privacy.roi_hash_matches_current_file -eq $true -and
  $privacy.support_hash_matches_current_file -eq $true -and
  $privacy.attribute_schema_exact_and_privacy_minimal -eq $true -and
  $privacy.sample_coordinates_or_identifiers_sent -eq $false
$localNoTransfer = $preflight -and [string]$preflight.current_pca_provenance_mode -eq 'local_rebuild_from_verified_workflow1_raw_covariates' -and $preflight.current_pca_provenance_valid -eq $true
$privacyStatus = if ($localNoTransfer) { 'NOT REQUIRED - NO EXTERNAL TRANSFER' } elseif ($privacyVerified) { 'VERIFIED - NO SAMPLE LOCATION SENT' } elseif ($supportDownload) { 'UNVERIFIED/BLOCKED' } else { 'WAITING' }
$supportPolicy = if ($preflight -and $preflight.support_geometry_policy) { [string]$preflight.support_geometry_policy } else { 'fixed_roi_buffer_no_sample_geometry' }
$supportBuffer = if ($preflight -and $preflight.support_buffer_m -ne $null) { [string]$preflight.support_buffer_m } else { ReadSetting $projectSettings 'covariate_support_buffer_m' '300' }
$supportGeometryStatus = if ($localNoTransfer) { 'NOT REQUIRED - VERIFIED WORKFLOW1 RAW' } else { "FIXED ROI ENVELOPE + $supportBuffer m; policy $supportPolicy" }
$modelInputSummary = ReadJson (Join-Path $internal 'work\models\qa\model_input_summary.json')
$workflow2Status = if ($modelInputSummary -and $modelInputSummary.product_status) { [string]$modelInputSummary.product_status } elseif ($pcaTrust -eq 'VERIFIED') { 'PREDICTORS_READY' } else { 'PREPARATION_REQUIRED' }

Write-Host ''
Write-Host 'QUY TRINH 2 - NOI SUY BAN DO' -ForegroundColor Cyan
Write-Host ("  sample_actual:    {0} rows ({1} inside, {2} outside ROI)" -f $sampleRows, $insideCount, $outsideCount)
Write-Host ("  Outside review:   {0} pending" -f $pendingOutside)
Write-Host ("  Indicators ready: {0}; metadata confirmed: {1}" -f $filledIndicators.Count, $confirmedMetadata)
Write-Host ("  Actual PCA:       {0}/5; provenance {1}" -f $actualPcCount, $pcaTrust)
Write-Host ("  Support geometry: {0}" -f $supportGeometryStatus)
Write-Host ("  Privacy gate:     {0}" -f $privacyStatus)
Write-Host ("  Stage status:     {0}" -f $workflow2Status)
Write-Host ("  Output maps:      {0}" -f $mapCount)
if (-not $pcaLineageReady -or -not $soilLineageReady) { Write-Host '  BLOCKED: Chay lai Quy trinh 1 truoc khi noi suy; raw/PCA/Soil lineage chua duoc xac minh.' -ForegroundColor Yellow }
if ($pendingOutside -gt 0) { Write-Host ("  Next: review outside_sample_review.csv ({0} pending outside sample(s))." -f $pendingOutside) -ForegroundColor Yellow }
if ($sampleRows -gt 0 -and $pcaTrust -ne 'VERIFIED') {
  Write-Host '  Next: run CHAY_NOI_SUY_BAN_DO.bat once to prepare/verify support covariates, PCA and Soil Type.' -ForegroundColor Yellow
} elseif ($filledIndicators.Count -eq 0) {
  Write-Host '  WAITING_LAB: predictors are ready; paste numeric lab values into sample_actual.csv, then run Workflow 2 again.' -ForegroundColor Yellow
} elseif ($confirmedMetadata -lt $filledIndicators.Count) {
  Write-Host '  Next: confirm method/unit in indicator_metadata.yml for every filled indicator.' -ForegroundColor Yellow
}
