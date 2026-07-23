@echo off
chcp 65001 >nul
title Kiem tra du an
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_NOI_BO\status.ps1"
echo.
pause
