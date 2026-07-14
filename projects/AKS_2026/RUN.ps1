param(
  [Parameter(Position = 0)]
  [ValidateSet('status','interpret','reference','design','interpolate')]
  [string]$Action = 'status'
)
$project = $PSScriptRoot
switch ($Action) {
  'status' { & "$project\_NOI_BO\status.ps1" }
  'interpret' { & "$project\_NOI_BO\run_field_area_workflow.ps1" }
  'reference' { & "$project\_NOI_BO\run_positive_reference_features_safe.ps1" }
  'design' { & "$project\_NOI_BO\run_design_workflow.ps1" }
  'interpolate' { & "$project\_NOI_BO\run_interpolation_workflow.ps1" }
}
if (-not $?) { exit 1 }
exit $LASTEXITCODE
