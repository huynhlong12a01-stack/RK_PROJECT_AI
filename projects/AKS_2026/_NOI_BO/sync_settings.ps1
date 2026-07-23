$ErrorActionPreference = "Stop"
$internal = $PSScriptRoot
$project = Split-Path -Parent $internal
$projectSettings = Join-Path $project "THONG_SO_DU_AN.yml"
$sampling = Join-Path $project "01_THIET_KE_LAY_MAU\01_DAU_VAO\sampling.yml"
$interpretation = Join-Path $project "00_XAC_LAP_VUNG_MIA\01_DAU_VAO\interpretation.yml"
$config = Join-Path $internal "config\project.yml"

foreach ($required in @($projectSettings, $sampling, $interpretation, $config)) {
  if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
    throw "Thieu tep cau hinh: $required"
  }
}

function ReadSetting([string]$Text, [string]$Name, [string]$Default = "") {
  $match = [regex]::Match($Text, "(?m)^[ \t]*" + [regex]::Escape($Name) + "[ \t]*:[ \t]*([^#\r\n]+)")
  if ($match.Success) { return $match.Groups[1].Value.Trim().Trim('"').Trim("'") }
  return $Default
}

function UpdateSettings([string]$Path, [hashtable]$Values) {
  $text = [IO.File]::ReadAllText($Path)
  foreach ($name in $Values.Keys) {
    $pattern = "(?m)^([ \t]*" + [regex]::Escape($name) + "[ \t]*:[ \t]*).*$"
    if ([regex]::IsMatch($text, $pattern)) {
      $text = [regex]::Replace(
        $text,
        $pattern,
        { param($match) $match.Groups[1].Value + [string]$Values[$name] },
        1
      )
    } else {
      $text = $text.TrimEnd() + [Environment]::NewLine + "$($name): $($Values[$name])" + [Environment]::NewLine
    }
  }
  $temp = $Path + ".sync.tmp"
  [IO.File]::WriteAllText($temp, $text, (New-Object Text.UTF8Encoding($false)))
  try {
    [IO.File]::Replace($temp, $Path, $null)
  } catch {
    Move-Item -LiteralPath $temp -Destination $Path -Force
  }
}

$text = [IO.File]::ReadAllText($projectSettings)
$values = @{
  project_id = ReadSetting $text "project_id"
  crs_mode = (ReadSetting $text "crs_mode" "auto").ToLowerInvariant()
  crs_epsg = ReadSetting $text "crs_epsg"
  resolution_m = ReadSetting $text "resolution_m"
  covariate_support_buffer_m = ReadSetting $text "covariate_support_buffer_m" "300"
  gee_project_id = ReadSetting $text "gee_project_id"
  sampling_start_date = ReadSetting $text "sampling_start_date"
  sampling_end_date = ReadSetting $text "sampling_end_date"
}

$folderId = Split-Path -Leaf $project
if ([string]::IsNullOrWhiteSpace($values.project_id) -or $values.project_id -ne $folderId) {
  throw "project_id trong THONG_SO_DU_AN.yml phai trung ten thu muc: $folderId"
}
if ($values.crs_mode -notin @("auto", "manual")) {
  throw "crs_mode phai la auto hoac manual trong THONG_SO_DU_AN.yml"
}
$epsg = 0
if (-not [int]::TryParse($values.crs_epsg, [ref]$epsg) -or $epsg -le 0) {
  throw "crs_epsg phai la ma EPSG nguyen duong."
}
$resolution = 0.0
if (-not [double]::TryParse(
  $values.resolution_m,
  [Globalization.NumberStyles]::Float,
  [Globalization.CultureInfo]::InvariantCulture,
  [ref]$resolution
) -or $resolution -le 0) {
  throw "resolution_m phai la so duong."
}
$supportBuffer = 0.0
if (-not [double]::TryParse(
  $values.covariate_support_buffer_m,
  [Globalization.NumberStyles]::Float,
  [Globalization.CultureInfo]::InvariantCulture,
  [ref]$supportBuffer
) -or $supportBuffer -le 0) {
  throw "covariate_support_buffer_m phai la so duong (met)."
}
if ([string]::IsNullOrWhiteSpace($values.gee_project_id)) {
  throw "gee_project_id khong duoc de trong."
}
$startDate = [datetime]::MinValue
$endDate = [datetime]::MinValue
if (-not [datetime]::TryParseExact(
  $values.sampling_start_date, "yyyy-MM-dd",
  [Globalization.CultureInfo]::InvariantCulture,
  [Globalization.DateTimeStyles]::None, [ref]$startDate
)) { throw "sampling_start_date phai co dang YYYY-MM-DD." }
if (-not [datetime]::TryParseExact(
  $values.sampling_end_date, "yyyy-MM-dd",
  [Globalization.CultureInfo]::InvariantCulture,
  [Globalization.DateTimeStyles]::None, [ref]$endDate
)) { throw "sampling_end_date phai co dang YYYY-MM-DD." }
if ($startDate -ge $endDate) {
  throw "sampling_start_date phai nho hon sampling_end_date."
}

$common = @{
  crs_mode = $values.crs_mode
  crs_epsg = $epsg
  resolution_m = $values.resolution_m
  gee_project_id = $values.gee_project_id
}
UpdateSettings $sampling (@{
  project_id = $values.project_id
  crs_mode = $common.crs_mode
  crs_epsg = $common.crs_epsg
  resolution_m = $common.resolution_m
  gee_project_id = $common.gee_project_id
  start_date = $values.sampling_start_date
  end_date = $values.sampling_end_date
})
UpdateSettings $interpretation $common
UpdateSettings $config (@{
  project_id = $values.project_id
  crs_mode = $common.crs_mode
  crs_epsg = $common.crs_epsg
  resolution_m = $common.resolution_m
  gee_project_id = $common.gee_project_id
  covariate_support_buffer_m = $supportBuffer.ToString("0.########", [Globalization.CultureInfo]::InvariantCulture)
  start_date = $values.sampling_start_date
  end_date = $values.sampling_end_date
})
Write-Host ("[CONFIG] Da dong bo THONG_SO_DU_AN.yml: EPSG:{0}, grid={1} m, support buffer={2} m, GEE={3}, {4}..{5}" -f $epsg, $values.resolution_m, $supportBuffer, $values.gee_project_id, $values.sampling_start_date, $values.sampling_end_date)
