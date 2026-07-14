@echo off
chcp 65001 >nul
title Thiet ke lay mau
echo Dang kiem tra dau vao va chay quy trinh thiet ke lay mau...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\_NOI_BO\run_design_workflow.ps1"
echo.
pause
