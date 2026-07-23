param(
  [switch]$AllUniqueScenarios
)

$ErrorActionPreference = "Stop"
$internal = $PSScriptRoot
$project = Split-Path -Parent $internal
$root = Resolve-Path (Join-Path $project "..\..")
Set-Location $root
$rLibrary = Join-Path $root '_UNG_DUNG\runtime\R_library'
New-Item -ItemType Directory -Path $rLibrary -Force | Out-Null
$env:R_LIBS_USER = $rLibrary
$modelWork = Join-Path $internal "work\models"
$manifestFile = Join-Path $modelWork "qa\sensitivity_input_manifest.csv"
$primaryFile = Join-Path $modelWork "input\soil_points.csv"
$comparisonScript = Join-Path $internal "pipeline\compare_sensitivity_results.R"
$overrideConfig = Join-Path $internal "config\rk_sensitivity_override.R"
$rscript = Get-Command Rscript -ErrorAction SilentlyContinue
if (-not $rscript) { throw "Khong tim thay Rscript." }
if (-not (Test-Path -LiteralPath $manifestFile -PathType Leaf)) {
  throw "Chua co sensitivity_input_manifest.csv. Hay chay prepare_model_input truoc."
}
if (-not (Test-Path -LiteralPath $primaryFile -PathType Leaf)) {
  throw "Chua co primary model input: $primaryFile"
}
if (-not (Test-Path -LiteralPath $overrideConfig -PathType Leaf)) {
  throw "Thieu sensitivity override config: $overrideConfig"
}

function Run-Checked([string]$Command, [string[]]$Arguments) {
  & $Command @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Buoc xu ly that bai: $Command $($Arguments -join ' ')"
  }
}

function Code-Signature([string]$Path) {
  $rows = @(Import-Csv -LiteralPath $Path)
  if ($rows.Count -eq 0) { return "" }
  (($rows | ForEach-Object { [string]$_.code } | Sort-Object -Unique) -join "|")
}

$primaryRows = @(Import-Csv -LiteralPath $primaryFile)
if ($primaryRows.Count -eq 0) { throw "Primary model input khong co dong mau." }
$core = @("code", "lat", "lon")
$indicatorNames = @(
  $primaryRows[0].PSObject.Properties.Name | Where-Object { $_ -notin $core }
)
$filled = @($indicatorNames | Where-Object {
  $field = $_
  @($primaryRows | Where-Object {
    -not [string]::IsNullOrWhiteSpace([string]($_.$field))
  }).Count -gt 0
})
if ($filled.Count -eq 0) {
  throw "Khong co chi tieu nao co ket qua trong primary model input."
}

$manifest = @(Import-Csv -LiteralPath $manifestFile)
$scenarioIds = @("INSIDE_ROI_ONLY")
if ($AllUniqueScenarios) {
  $scenarioIds += @(
    "ELIGIBLE_AFTER_TARGET_SUPPORT_REVIEW",
    "ALL_ACTUAL_AUDIT"
  )
}
$primarySignature = Code-Signature $primaryFile
$seenSignatures = @{$primarySignature = "PRIMARY"}
$scenarios = @()
foreach ($scenarioId in $scenarioIds) {
  $row = @($manifest | Where-Object { $_.scenario_id -eq $scenarioId })
  if ($row.Count -ne 1) { continue }
  $pointFile = [string]$row[0].point_file
  if (-not (Test-Path -LiteralPath $pointFile -PathType Leaf)) { continue }
  $signature = Code-Signature $pointFile
  if ([string]::IsNullOrWhiteSpace($signature)) { continue }
  if ($seenSignatures.ContainsKey($signature)) {
    Write-Host ("[SKIP] {0} trung sample set voi {1}." -f `
      $scenarioId, $seenSignatures[$signature]) -ForegroundColor Yellow
    continue
  }
  $seenSignatures[$signature] = $scenarioId
  $scenarios += [pscustomobject]@{
    Id = $scenarioId
    PointFile = (Resolve-Path -LiteralPath $pointFile).Path
  }
}

$soilInput = Join-Path $project "01_THIET_KE_LAY_MAU\01_DAU_VAO\soil_type.geojson"
$soilRasters = @(Get-ChildItem -LiteralPath `
  (Join-Path $internal "work\interpolation") -Filter "SoilDummy_*.tif" `
  -File -ErrorAction SilentlyContinue)
$branches = @(
  [pscustomobject]@{
    Name = "PC_ONLY"
    Config = Join-Path $internal "config\rk_pc.R"
  }
)
if ((Test-Path -LiteralPath $soilInput -PathType Leaf) -and
    $soilRasters.Count -gt 0) {
  $branches += [pscustomobject]@{
    Name = "PC_PLUS_SOIL"
    Config = Join-Path $internal "config\rk_pc_soil.R"
  }
}

$environmentNames = @(
  "RK_TARGET_FIELD", "RK_RUN_NAME", "RK_CONFIG_OVERRIDE",
  "RK_SENSITIVITY_BASE_CONFIG", "RK_SENSITIVITY_POINT_FILE",
  "RK_SENSITIVITY_OUTPUT_ROOT"
)
$oldEnvironment = @{}
foreach ($name in $environmentNames) {
  $oldEnvironment[$name] = [Environment]::GetEnvironmentVariable(
    $name, "Process")
}

try {
  foreach ($scenario in $scenarios) {
    foreach ($branch in $branches) {
      $outputRoot = Join-Path $modelWork `
        ("SENSITIVITY\{0}\{1}" -f $scenario.Id, $branch.Name)
      New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
      foreach ($indicator in $filled) {
        $safeIndicator = ($indicator -replace '[^A-Za-z0-9_-]', '_') `
          -replace '_+', '_'
        $runName = "AKS_2026_${safeIndicator}_$($branch.Name)_$($scenario.Id)"
        Write-Host ("[SENSITIVITY] {0} - {1} - {2}" -f `
          $scenario.Id, $indicator, $branch.Name) -ForegroundColor Cyan
        $env:RK_TARGET_FIELD = $indicator
        $env:RK_RUN_NAME = $runName
        $env:RK_CONFIG_OVERRIDE = $overrideConfig
        $env:RK_SENSITIVITY_BASE_CONFIG = $branch.Config
        $env:RK_SENSITIVITY_POINT_FILE = $scenario.PointFile
        $env:RK_SENSITIVITY_OUTPUT_ROOT = $outputRoot
        Run-Checked $rscript.Source @("_UNG_DUNG\engine\scripts\main.R")
      }
    }
  }
}
finally {
  foreach ($name in $environmentNames) {
    $oldValue = $oldEnvironment[$name]
    if ($null -eq $oldValue) {
      [Environment]::SetEnvironmentVariable($name, $null, "Process")
    } else {
      [Environment]::SetEnvironmentVariable($name, $oldValue, "Process")
    }
  }
}

Run-Checked $rscript.Source @(
  "projects\AKS_2026\_NOI_BO\pipeline\compare_sensitivity_results.R"
)
if ($scenarios.Count -eq 0) {
  Write-Host "Khong co sample set sensitivity khac primary; da cap nhat QA summary." `
    -ForegroundColor Yellow
} else {
  Write-Host "Hoan tat sensitivity model comparison." -ForegroundColor Green
}
