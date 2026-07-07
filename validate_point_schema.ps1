param(
  [string]$Point = "",
  [string]$Output = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$rscriptCmd = Get-Command Rscript -ErrorAction SilentlyContinue
if (-not $rscriptCmd) {
  Write-Error "Rscript was not found on PATH. Please install R or add Rscript to PATH."
  exit 1
}

$argsList = @("scripts\validate_point_schema.R")
if ($Point) { $argsList += @("--point", $Point) }
if ($Output) { $argsList += @("--output", $Output) }

& $rscriptCmd.Source @argsList
if ($LASTEXITCODE -ne 0) {
  Write-Error "Point schema validation failed."
  exit $LASTEXITCODE
}
