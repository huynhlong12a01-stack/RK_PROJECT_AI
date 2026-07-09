param(
  [string]$Target = "",
  [string]$Request = "agent\requests\run_request_template.json",
  [int]$MaxIterations = 3,
  [string]$LoopId = "",
  [string]$DecisionsDir = "",
  [switch]$AutoDecision,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

Write-Host "[INFO] Starting controlled agent loop..."
if ($Target) { Write-Host "[INFO] Target: $Target" }
Write-Host "[INFO] Request: $Request"
Write-Host "[INFO] Max iterations: $MaxIterations"
if ($AutoDecision) { Write-Host "[INFO] Auto-decision heuristic: enabled" } else { Write-Host "[INFO] Auto-decision heuristic: disabled; external ai_decision.json required for rerun" }
if ($DryRun) { Write-Host "[INFO] Dry run: enabled" }

$rscriptCmd = Get-Command Rscript -ErrorAction SilentlyContinue
if (-not $rscriptCmd) {
  Write-Error "Rscript was not found on PATH. Please install R or add Rscript to PATH."
  exit 1
}
if (-not (Test-Path -LiteralPath $Request)) {
  Write-Error "Request JSON not found: $Request"
  exit 1
}

$argsList = @("scripts\agent_loop.R", "--request", $Request, "--max_iterations", "$MaxIterations")
if ($Target) { $argsList += @("--target", $Target) }
if ($LoopId) { $argsList += @("--loop_id", $LoopId) }
if ($DecisionsDir) { $argsList += @("--decisions_dir", $DecisionsDir) }
if ($AutoDecision) { $argsList += @("--auto_decision", "true") }
if ($DryRun) { $argsList += @("--dry_run", "true") }

& $rscriptCmd.Source @argsList
if ($LASTEXITCODE -ne 0) {
  Write-Error "Controlled agent loop failed. Check agent\history\<loop_id> for details."
  exit $LASTEXITCODE
}

Write-Host "[INFO] Controlled agent loop finished."