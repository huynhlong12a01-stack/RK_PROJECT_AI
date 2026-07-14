$ErrorActionPreference = "Stop"
$internal = $PSScriptRoot
$project = Split-Path -Parent $internal
$settings = Join-Path $project "01_THIET_KE_LAY_MAU\01_DAU_VAO\sampling.yml"
$config = Join-Path $internal "config\project.yml"
if (-not (Test-Path -LiteralPath $settings)) { throw "Missing sampling.yml: $settings" }
if (-not (Test-Path -LiteralPath $config)) { throw "Missing internal config: $config" }

function ReadSetting([string]$Text, [string]$Name, [string]$Default) {
  $match = [regex]::Match($Text, "(?m)^\s*" + [regex]::Escape($Name) + "\s*:\s*([^#\r\n]+)")
  if ($match.Success) { return $match.Groups[1].Value.Trim().Trim('"').Trim("'") }
  return $Default
}

$settingsText = [IO.File]::ReadAllText($settings)
$configText = [IO.File]::ReadAllText($config)
$values = @{
  crs_epsg = ReadSetting $settingsText "crs_epsg" "32649"
  resolution_m = ReadSetting $settingsText "resolution_m" "10"
  gee_project_id = ReadSetting $settingsText "gee_project_id" "rkapp-492504"
  start_date = ReadSetting $settingsText "start_date" "2026-01-01"
  end_date = ReadSetting $settingsText "end_date" "2026-04-01"
}
foreach ($name in @('crs_epsg','resolution_m','gee_project_id','start_date','end_date')) {
  $pattern = "(?m)^(\s*" + [regex]::Escape($name) + "\s*:\s*).*$"
  if ([regex]::IsMatch($configText, $pattern)) {
    $configText = [regex]::Replace($configText, $pattern, '${1}' + $values[$name])
  }
}
[IO.File]::WriteAllText($config, $configText, (New-Object Text.UTF8Encoding($false)))
