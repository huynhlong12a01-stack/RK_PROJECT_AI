param(
  [string]$Profile = "core,sampling_design,tidy_io",
  [string]$Repos = "https://cloud.r-project.org",
  [switch]$SkipPython
)

$ErrorActionPreference = "Stop"
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
Set-Location $root
$rLibrary = Join-Path $root '_UNG_DUNG\runtime\R_library'
New-Item -ItemType Directory -Path $rLibrary -Force | Out-Null
$env:R_LIBS_USER = $rLibrary
$rscriptCmd = Get-Command Rscript -ErrorAction SilentlyContinue
if (-not $rscriptCmd) { throw "Khong tim thay Rscript trong PATH." }
& $rscriptCmd.Source "_UNG_DUNG\engine\scripts\install_dependencies.R" --profile $Profile --repos $Repos
if ($LASTEXITCODE -ne 0) { throw "Cai dat goi R that bai." }

if (-not $SkipPython) {
  $venvPython = Join-Path $root '.venv\Scripts\python.exe'
  if (-not (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
    $basePython = (Get-Command python -ErrorAction SilentlyContinue).Source

    if (-not $basePython) { throw "Khong tim thay Python de tao moi truong .venv." }
    & $basePython -m venv (Join-Path $root '.venv')
    if ($LASTEXITCODE -ne 0) { throw "Khong tao duoc .venv cua ung dung." }
  }
  & $venvPython -m pip install --disable-pip-version-check -r '_UNG_DUNG\engine\requirements.txt'
  if ($LASTEXITCODE -ne 0) { throw "Cai dat goi Python that bai." }
  & $venvPython '_UNG_DUNG\engine\scripts\check_python_dependencies.py'
  if ($LASTEXITCODE -ne 0) { throw "Moi truong Python chua day du." }
}
Write-Host '[OK] Moi truong RK_R_Project da san sang.' -ForegroundColor Green