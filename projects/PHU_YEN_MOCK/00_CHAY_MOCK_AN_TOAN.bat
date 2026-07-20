@echo off
chcp 65001 >nul
title PHU_YEN_MOCK - CHAY AN TOAN
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_NOI_BO\run_mock_workflow.ps1" %*
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo [DA CHAN] Mock khong hoan tat; ket qua tam thoi da duoc co lap neu co the.
pause
exit /b %RC%
