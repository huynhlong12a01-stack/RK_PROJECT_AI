param(
  [string]$Profile = "core,sampling_design,tidy_io",
  [switch]$SkipPython
)

$ErrorActionPreference = "Stop"
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
Set-Location $root
$rLibrary = Join-Path $root '_UNG_DUNG\runtime\R_library'
New-Item -ItemType Directory -Path $rLibrary -Force | Out-Null
$env:R_LIBS_USER = $rLibrary
$failed = $false

$rscriptCmd = Get-Command Rscript -ErrorAction SilentlyContinue
if (-not $rscriptCmd) {
  Write-Error "Khong tim thay Rscript trong PATH."
  $failed = $true
} else {
  & $rscriptCmd.Source "_UNG_DUNG\engine\scripts\check_dependencies.R" --profile $Profile
  if ($LASTEXITCODE -ne 0) { $failed = $true }
}

if (-not $SkipPython) {
  $python = Join-Path $root '.venv\Scripts\python.exe'
  if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    $python = if ($pythonCommand) { $pythonCommand.Source } else { $null }
  }
  if (-not $python) {
    Write-Error "Khong tim thay Python. Hay chay CAI_DAT_UNG_DUNG.bat."
    $failed = $true
  } else {
    & $python '_UNG_DUNG\engine\scripts\check_python_dependencies.py'
    if ($LASTEXITCODE -ne 0) { $failed = $true }
  }
}
if ($failed) { exit 1 }
Write-Host '[OK] Kiem tra dependency dat.' -ForegroundColor Green