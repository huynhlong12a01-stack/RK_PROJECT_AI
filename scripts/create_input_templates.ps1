param(
  [string]$OutputDir = "input\points"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

$rscriptCmd = Get-Command Rscript -ErrorAction SilentlyContinue
if (-not $rscriptCmd) {
  Write-Error "Rscript was not found on PATH. Cannot export input templates."
  exit 1
}

& $rscriptCmd.Source "scripts\export_input_templates.R" $OutputDir
if ($LASTEXITCODE -ne 0) {
  Write-Error "Template CSV export failed."
  exit $LASTEXITCODE
}

function Escape-Xml([string]$Value) {
  if ($null -eq $Value) { return "" }
  return [System.Security.SecurityElement]::Escape($Value)
}

function ConvertTo-SheetXml($Rows) {
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
  [void]$sb.Append('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>')
  for ($r = 0; $r -lt $Rows.Count; $r++) {
    [void]$sb.Append('<row r="' + ($r + 1) + '">')
    for ($c = 0; $c -lt $Rows[$r].Count; $c++) {
      $colName = ""
      $n = $c + 1
      while ($n -gt 0) {
        $rem = ($n - 1) % 26
        $colName = [char](65 + $rem) + $colName
        $n = [math]::Floor(($n - 1) / 26)
      }
      [void]$sb.Append('<c r="' + $colName + ($r + 1) + '" t="inlineStr"><is><t>' + (Escape-Xml $Rows[$r][$c]) + '</t></is></c>')
    }
    [void]$sb.Append('</row>')
  }
  [void]$sb.Append('</sheetData></worksheet>')
  return $sb.ToString()
}

function Read-CsvRows([string]$Path) {
  $data = @(Import-Csv -LiteralPath $Path)
  $headers = @()
  if ($data.Count -gt 0) {
    $headers = @($data[0].PSObject.Properties.Name)
  } else {
    $first = Get-Content -LiteralPath $Path -TotalCount 1
    $headers = @($first -split ',')
  }
  $rows = New-Object System.Collections.Generic.List[object]
  $rows.Add($headers)
  foreach ($row in $data) {
    $rows.Add(@($headers | ForEach-Object { [string]$row.$_ }))
  }
  return $rows
}

function Add-ZipTextEntry($Zip, [string]$Name, [string]$Content) {
  $entry = $Zip.CreateEntry($Name)
  $stream = $entry.Open()
  try {
    $encoding = [System.Text.UTF8Encoding]::new($false)
    $writer = [System.IO.StreamWriter]::new($stream, $encoding)
    try { $writer.Write($Content) } finally { $writer.Dispose() }
  } finally {
    $stream.Dispose()
  }
}

$resolvedOut = Resolve-Path -LiteralPath $OutputDir
$templateCsv = Join-Path $resolvedOut "soil_points_template.csv"
$profilesCsv = Join-Path $resolvedOut "indicator_profiles.csv"
$instructionsCsv = Join-Path $resolvedOut "soil_points_template_instructions.csv"
$xlsxPath = Join-Path $resolvedOut "soil_points_template.xlsx"
$workspaceTmpRoot = Join-Path $root ".tmp"
New-Item -ItemType Directory -Path $workspaceTmpRoot -Force | Out-Null
$buildXlsx = Join-Path $workspaceTmpRoot "soil_points_template_build.xlsx"

$contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/worksheets/sheet3.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>'
$rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
$workbook = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Template" sheetId="1" r:id="rId1"/><sheet name="Indicator Profiles" sheetId="2" r:id="rId2"/><sheet name="Instructions" sheetId="3" r:id="rId3"/></sheets></workbook>'
$workbookRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet3.xml"/></Relationships>'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$fs = [System.IO.File]::Open($buildXlsx, [System.IO.FileMode]::Create, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
try {
  $zip = [System.IO.Compression.ZipArchive]::new($fs, [System.IO.Compression.ZipArchiveMode]::Create, $true)
  try {
    Add-ZipTextEntry $zip "[Content_Types].xml" $contentTypes
    Add-ZipTextEntry $zip "_rels/.rels" $rels
    Add-ZipTextEntry $zip "xl/workbook.xml" $workbook
    Add-ZipTextEntry $zip "xl/_rels/workbook.xml.rels" $workbookRels
    Add-ZipTextEntry $zip "xl/worksheets/sheet1.xml" (ConvertTo-SheetXml (Read-CsvRows $templateCsv))
    Add-ZipTextEntry $zip "xl/worksheets/sheet2.xml" (ConvertTo-SheetXml (Read-CsvRows $profilesCsv))
    Add-ZipTextEntry $zip "xl/worksheets/sheet3.xml" (ConvertTo-SheetXml (Read-CsvRows $instructionsCsv))
  } finally {
    $zip.Dispose()
  }
} finally {
  $fs.Dispose()
}

$finalXlsxPath = $xlsxPath
try {
  [System.IO.File]::Copy($buildXlsx, $xlsxPath, $true)
} catch {
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $finalXlsxPath = Join-Path $resolvedOut "soil_points_template_$stamp.xlsx"
  [System.IO.File]::Copy($buildXlsx, $finalXlsxPath, $true)
  Write-Warning "Existing Excel template is locked or cannot be overwritten. Writing: $finalXlsxPath"
}
Write-Host "[INFO] Wrote Excel template: $finalXlsxPath"