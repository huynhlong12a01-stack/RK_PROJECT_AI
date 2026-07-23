@echo off
chcp 65001 >nul
title Cai dat RK_R_Project
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_UNG_DUNG\tools\install_dependencies.ps1"
if errorlevel 1 (
  echo.
  echo [LOI] Cai dat chua hoan tat. Xem thong bao phia tren.
) else (
  echo.
  echo [OK] Ung dung da san sang.
)
pause