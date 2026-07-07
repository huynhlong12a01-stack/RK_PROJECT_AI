param(
  [string]$Target = "",
  [string]$Request = "agent\requests\run_request_template.json"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

Write-Host "[INFO] Starting agent-ready RK run..."
if ($Target) { Write-Host "[INFO] Target: $Target" }
Write-Host "[INFO] Request: $Request"

$rscriptCmd = Get-Command Rscript -ErrorAction SilentlyContinue
if (-not $rscriptCmd) {
  Write-Error "Rscript was not found on PATH. Please install R or add Rscript to PATH."
  exit 1
}
if (-not (Test-Path -LiteralPath $Request)) {
  Write-Error "Request JSON not found: $Request"
  exit 1
}

$argsList = @("scripts\agent_run.R", "--request", $Request)
if ($Target) { $argsList += @("--target", $Target) }

& $rscriptCmd.Source @argsList
if ($LASTEXITCODE -ne 0) {
  Write-Error "Agent-ready RK run failed. Check agent\history\<run_id>\agent_run_<run_id>.log for details."
  exit $LASTEXITCODE
}

Write-Host "[INFO] Agent-ready RK run finished."