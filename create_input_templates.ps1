param(
  [string]$OutputDir = "input\points"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

& "scripts\create_input_templates.ps1" -OutputDir $OutputDir
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
