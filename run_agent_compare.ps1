param(
  [string]$Target = "",
  [string]$Results = "agent\responses",
  [string]$Output = "",
  [string]$RunPrefix = "",
  [string]$SourceContains = "",
  [switch]$IncludeOutput
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$rscriptCmd = Get-Command Rscript -ErrorAction SilentlyContinue
if (-not $rscriptCmd) {
  Write-Error "Rscript was not found on PATH. Please install R or add Rscript to PATH."
  exit 1
}

if (-not $Output) {
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  if ($Target) { $Output = "agent\history\run_comparison_${Target}_${stamp}.json" } else { $Output = "agent\history\run_comparison_${stamp}.json" }
}

$argsList = @("scripts\agent_compare_runs.R", "--results", $Results, "--output", $Output, "--include_output", ($(if ($IncludeOutput) { "true" } else { "false" })))
if ($Target) { $argsList += @("--target", $Target) }
if ($RunPrefix) { $argsList += @("--run_prefix", $RunPrefix) }
if ($SourceContains) { $argsList += @("--source_contains", $SourceContains) }

& $rscriptCmd.Source @argsList
if ($LASTEXITCODE -ne 0) {
  Write-Error "Agent run comparison failed. Check the filters and result folder."
  exit $LASTEXITCODE
}