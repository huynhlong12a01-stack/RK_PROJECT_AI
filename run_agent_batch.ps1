param(
  [string]$Targets = "",
  [string]$Request = "agent\requests\run_request_template.json",
  [string]$Output = "",
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

Write-Host "[INFO] Starting batch agent-ready RK run..."
if ($Targets) { Write-Host "[INFO] Targets: $Targets" } else { Write-Host "[INFO] Targets: auto-detect analysis columns" }
Write-Host "[INFO] Request template: $Request"

$rscriptCmd = Get-Command Rscript -ErrorAction SilentlyContinue
if (-not $rscriptCmd) {
  Write-Error "Rscript was not found on PATH. Please install R or add Rscript to PATH."
  exit 1
}
if (-not (Test-Path -LiteralPath $Request)) {
  Write-Error "Request JSON not found: $Request"
  exit 1
}

$argsList = @("scripts\agent_batch_run.R", "--request", $Request)
if ($Targets) { $argsList += @("--targets", $Targets) }
if ($Output) { $argsList += @("--output", $Output) }
if ($DryRun) { $argsList += @("--dry-run", "true") }

& $rscriptCmd.Source @argsList
if ($LASTEXITCODE -ne 0) {
  Write-Error "Batch agent-ready RK run failed. Check agent\history and agent\responses for details."
  exit $LASTEXITCODE
}

Write-Host "[INFO] Batch agent-ready RK run finished."