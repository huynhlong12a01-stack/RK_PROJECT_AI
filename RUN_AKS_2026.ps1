param(
  [Parameter(Position = 0)]
  [ValidateSet("status", "design", "interpolate")]
  [string]$Action = "status"
)

$runner = "$PSScriptRoot\projects\AKS_2026\RUN.ps1"
& $runner -Action $Action
if (-not $?) { exit 1 }
exit $LASTEXITCODE
