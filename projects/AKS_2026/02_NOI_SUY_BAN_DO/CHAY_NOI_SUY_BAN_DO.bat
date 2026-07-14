@echo off
chcp 65001 >nul
title Noi suy ban do dinh duong
echo Dang kiem tra sample_actual va chay noi suy tat ca chi tieu co ket qua...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\_NOI_BO\run_interpolation_workflow.ps1"
echo.
pause
