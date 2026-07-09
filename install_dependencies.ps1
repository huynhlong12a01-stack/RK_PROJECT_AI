param(
  [string]$Profile = "core,rag",
  [string]$Repos = "https://cloud.r-project.org"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$rscriptCmd = Get-Command Rscript -ErrorAction SilentlyContinue
if (-not $rscriptCmd) {
  Write-Error "Rscript was not found on PATH. Please install R or add Rscript to PATH."
  exit 1
}

& $rscriptCmd.Source "scripts\install_dependencies.R" --profile $Profile --repos $Repos
if ($LASTEXITCODE -ne 0) {
  Write-Error "Dependency installation failed. Check the package installation log above."
  exit $LASTEXITCODE
}

Write-Host "[INFO] Dependency installation finished."