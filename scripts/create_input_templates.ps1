param(
  [string]$OutputDir = "input\points"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

$rscriptCmd = Get-Command Rscript -ErrorAction SilentlyContinue
if (-not $rscriptCmd) {
  Write-Error "Rscript was not found on PATH. Cannot export input templates."
  exit 1
}

& $rscriptCmd.Source "scripts\export_input_templates.R" $OutputDir
if ($LASTEXITCODE -ne 0) {
  Write-Error "Input template export failed. Check the tidy_io dependency profile."
  exit $LASTEXITCODE
}

$required = @(
  "soil_points_template.csv",
  "indicator_profiles.csv",
  "soil_points_template_instructions.csv",
  "soil_points_template.xlsx"
)
foreach ($name in $required) {
  $path = Join-Path $OutputDir $name
  if (-not (Test-Path -LiteralPath $path)) {
    Write-Error "Template export completed without required file: $path"
    exit 1
  }
}

Write-Host "[INFO] Input templates are ready in: $OutputDir"
