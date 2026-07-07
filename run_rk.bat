@echo off
setlocal
cd /d "%~dp0"
where Rscript >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Rscript was not found on PATH. Please install R or add Rscript to PATH.
  pause
  exit /b 1
)
Rscript scripts\main.R
set EXIT_CODE=%ERRORLEVEL%
if not "%EXIT_CODE%"=="0" echo [ERROR] RK run failed with exit code %EXIT_CODE%.
pause
exit /b %EXIT_CODE%