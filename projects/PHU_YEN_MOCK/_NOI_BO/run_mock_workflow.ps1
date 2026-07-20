param([switch]$ForceRebuild)

$ErrorActionPreference = 'Stop'
$internal = [IO.Path]::GetFullPath($PSScriptRoot)
$project = [IO.Path]::GetFullPath((Split-Path -Parent $internal))
$root = [IO.Path]::GetFullPath((Join-Path $project '..\..'))
$pipeline = Join-Path $internal 'pipeline'
$manifest = Join-Path $project 'MOCK_RUN_MANIFEST.json'
$manifestTemplate = Join-Path $project 'MOCK_RUN_MANIFEST_TEMPLATE.json'
$contract = Join-Path $project 'MOCK_CONTRACT.json'
$result = Join-Path $project '02_NOI_SUY_BAN_DO\02_KET_QUA'
$quarantine = Join-Path $result 'MOCK_SYNTHETIC_NOT_FOR_USE'
$gate = Join-Path $quarantine 'MOCK_QA_GATE.json'
$boundary = Join-Path $internal 'work\field_area\VNM_ADM1_geoboundaries_2008.geojson'
$boundaryUrl = 'https://github.com/wmgeolab/geoBoundaries/raw/9469f09/releaseData/gbOpen/VNM/ADM1/geoBoundaries-VNM-ADM1.geojson'
$boundaryHash = '25dbc2fec9862016710118fc98042d3e803830c72361c91c4e864ae668fa9541'
$canonicalSoil = Join-Path $root 'shared_data\soil_type_vietnam\raw\VN_soil_type.geojson'

Set-Location $root
$rLibrary = Join-Path $root '_UNG_DUNG\runtime\R_library'
New-Item -ItemType Directory -Path $rLibrary -Force | Out-Null
$env:R_LIBS_USER = $rLibrary
function Assert-InsideProject([string]$Path) {
  $full = [IO.Path]::GetFullPath($Path)
  $prefix = $project.TrimEnd('\') + '\'
  if ($full -ne $project -and -not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe path outside PHU_YEN_MOCK: $full"
  }
  return $full
}

function Get-PythonPath {
  $local = Join-Path $root '.venv\Scripts\python.exe'
  if (Test-Path -LiteralPath $local -PathType Leaf) { return $local }
  $command = Get-Command python -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }
  throw 'Python is unavailable.'
}

function Invoke-Checked([string]$Command, [string[]]$Arguments) {
  & $Command @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed with exit code ${LASTEXITCODE}: $Command $($Arguments -join ' ')"
  }
}

function Invoke-ProjectPowerShell([string]$Path, [string[]]$Arguments = @()) {
  $safe = Assert-InsideProject $Path
  & $safe @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Project workflow failed with exit code ${LASTEXITCODE}: $safe"
  }
}

function Test-UnquarantinedOutput {
  foreach ($name in @('maps', 'reports', 'tables')) {
    $directory = Join-Path $result $name
    if (Test-Path -LiteralPath $directory) {
      $file = Get-ChildItem -LiteralPath $directory -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($file) { return $true }
    }
  }
  return $false
}

function Test-CompletedRun {
  if (-not (Test-Path -LiteralPath $manifest -PathType Leaf) -or
      -not (Test-Path -LiteralPath $gate -PathType Leaf) -or
      (Test-UnquarantinedOutput)) { return $false }
  try {
    $runtime = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
    $qa = Get-Content -LiteralPath $gate -Raw -Encoding UTF8 | ConvertFrom-Json
    $allowed = @('QA_FAILED_BLOCKED', 'SMOKE_QA_PASSED_NON_OPERATIONAL')
    return (
      [string]$runtime.runtime.stage2_status -in $allowed -and
      [string]$qa.status -in $allowed -and
      $runtime.non_operational -eq $true -and
      $runtime.map_use_prohibited -eq $true -and
      $runtime.runtime.maps_accepted -eq $false -and
      $qa.maps_accepted -eq $false -and
      [int]$runtime.output_quarantine.artifact_count -gt 0
    )
  } catch { return $false }
}

function Remove-ProjectTree([string]$Path) {
  $safe = Assert-InsideProject $Path
  if (Test-Path -LiteralPath $safe) {
    Remove-Item -LiteralPath $safe -Recurse -Force
  }
}

function Reset-Stage2Runtime {
  foreach ($candidate in @(
    (Join-Path $internal 'work\models\PC_ONLY'),
    (Join-Path $internal 'work\models\PC_PLUS_SOIL'),
    (Join-Path $result 'maps'),
    (Join-Path $result 'reports'),
    (Join-Path $result 'tables'),
    $quarantine
  )) { Remove-ProjectTree $candidate }
  foreach ($directory in @(
    (Join-Path $internal 'work\models\PC_ONLY'),
    (Join-Path $internal 'work\models\PC_PLUS_SOIL')
  )) { New-Item -ItemType Directory -Path (Assert-InsideProject $directory) -Force | Out-Null }
}

function Resolve-SoilSource {
  if (Test-Path -LiteralPath $canonicalSoil -PathType Leaf) { return $canonicalSoil }
  throw "Missing Vietnam Soil Type. Expected: $canonicalSoil"
}

$lockFile = Assert-InsideProject (Join-Path $internal 'work\mock_workflow.lock')
New-Item -ItemType Directory -Path (Split-Path -Parent $lockFile) -Force | Out-Null
try {
  $lockStream = [IO.File]::Open(
    $lockFile,
    [IO.FileMode]::OpenOrCreate,
    [IO.FileAccess]::ReadWrite,
    [IO.FileShare]::None
  )
} catch {
  throw 'Another PHU_YEN_MOCK workflow is already running. Wait for it to finish; concurrent writes are blocked.'
}

try {
$python = Get-PythonPath
if (-not (Test-Path -LiteralPath $contract -PathType Leaf)) { throw "Missing mock contract: $contract" }
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
  Copy-Item -LiteralPath $manifestTemplate -Destination $manifest
}

$runError = $null
$guardError = $null
$previousMockToken = $env:RK_PHU_YEN_MOCK_SAFE_RUN
$env:RK_PHU_YEN_MOCK_SAFE_RUN = 'orchestrated-v1'
try {
  Invoke-Checked $python @((Join-Path $pipeline 'enforce_mock_isolation.py'))

  $alreadyComplete = (-not $ForceRebuild) -and (Test-CompletedRun)
  if ($alreadyComplete) {
    Write-Host '[OK] Existing mock run is complete and quarantined; expensive stages were skipped.' -ForegroundColor Green
  } else {
    Reset-Stage2Runtime
    Copy-Item -LiteralPath $manifestTemplate -Destination $manifest -Force
    Invoke-Checked $python @((Join-Path $pipeline 'configure_mock_project.py'))
    Invoke-Checked $python @((Join-Path $pipeline 'configure_mock_smoke_runtime.py'))
    Invoke-Checked $python @((Join-Path $pipeline 'enforce_mock_isolation.py'))

    $soil = Resolve-SoilSource
    if ((Get-Item -LiteralPath $soil).Length -lt 100MB) {
      throw "Vietnam Soil Type appears incomplete: $soil"
    }

    New-Item -ItemType Directory -Path (Assert-InsideProject (Split-Path -Parent $boundary)) -Force | Out-Null
    $needBoundary = -not (Test-Path -LiteralPath $boundary -PathType Leaf)
    if (-not $needBoundary) {
      $needBoundary = (Get-FileHash -LiteralPath $boundary -Algorithm SHA256).Hash.ToLowerInvariant() -ne $boundaryHash
    }
    if ($needBoundary) {
      $temporary = Assert-InsideProject ($boundary + '.download')
      Invoke-WebRequest -Uri $boundaryUrl -OutFile $temporary
      $downloadHash = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash.ToLowerInvariant()
      if ($downloadHash -ne $boundaryHash) {
        Remove-Item -LiteralPath $temporary -Force
        throw "Downloaded boundary SHA-256 mismatch: $downloadHash"
      }
      Move-Item -LiteralPath $temporary -Destination $boundary -Force
    }

    Invoke-Checked $python @((Join-Path $pipeline 'prepare_phu_yen_mock_inputs.py'))

    # Stage 0 is always followed immediately by the isolation guard, even on error.
    try {
      Invoke-ProjectPowerShell (Join-Path $internal 'run_field_area_workflow.ps1')
    } finally {
      Invoke-Checked $python @((Join-Path $pipeline 'enforce_mock_isolation.py'))
    }

    Invoke-ProjectPowerShell (Join-Path $internal 'run_design_workflow.ps1')
    Invoke-Checked $python @((Join-Path $pipeline 'generate_synthetic_lab_fixture.py'))

    $designWork = Join-Path $internal 'work\design'
    $actualWork = Join-Path $internal 'work\interpolation'
    New-Item -ItemType Directory -Path (Assert-InsideProject $actualWork) -Force | Out-Null
    foreach ($name in @('CHIRPS.tif','DEM.tif','NDVI.tif','Slope.tif','TWI.tif','PC1.tif','PC2.tif','PC3.tif','PC4.tif','PC5.tif')) {
      Copy-Item -LiteralPath (Join-Path $designWork $name) -Destination (Join-Path $actualWork $name) -Force
    }
    $actualQa = Join-Path $actualWork 'qa'
    Remove-Item -LiteralPath (Join-Path $actualQa 'pca_current_provenance.json') -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $actualQa 'pca_current_provenance_points.csv') -Force -ErrorAction SilentlyContinue
    $rscript = (Get-Command Rscript -ErrorAction Stop).Source
    Invoke-Checked $rscript @('projects/PHU_YEN_MOCK/_NOI_BO/pipeline/preflight_actual.R')
    Invoke-Checked $rscript @('projects/PHU_YEN_MOCK/_NOI_BO/pipeline/verify_current_pca_provenance.R')
    Invoke-Checked $rscript @('projects/PHU_YEN_MOCK/_NOI_BO/pipeline/preflight_actual.R')
    Invoke-ProjectPowerShell (Join-Path $internal 'run_interpolation_workflow.ps1')
  }
} catch {
  $runError = $_
} finally {
  # Fail closed: always attempt both isolation stamping and final quarantine.
  $isolationError = $null
  try {
    Invoke-Checked $python @((Join-Path $pipeline 'enforce_mock_isolation.py'))
  } catch {
    $isolationError = $_
  }
  try {
    Invoke-Checked $python @((Join-Path $pipeline 'finalize_mock_run.py'))
  } catch {
    $guardError = $_
  }
  if ($isolationError) {
    if ($guardError) {
      Write-Warning "Isolation guard also failed: $($isolationError.Exception.Message)"
    } else {
      $guardError = $isolationError
    }
  }
  $env:RK_PHU_YEN_MOCK_SAFE_RUN = $previousMockToken
}

if ($guardError) {
  if ($runError) { Write-Warning "Workflow error before safety finalization: $($runError.Exception.Message)" }
  throw $guardError
}
if ($runError) { throw $runError }

Invoke-ProjectPowerShell (Join-Path $internal 'status.ps1')
Write-Host 'PHU_YEN_MOCK finished safely. Read MOCK_RUN_MANIFEST.json and MOCK_QA_GATE.json.' -ForegroundColor Green
} finally {
  if ($null -ne $lockStream) { $lockStream.Dispose() }
  Remove-Item -LiteralPath $lockFile -Force -ErrorAction SilentlyContinue
}
