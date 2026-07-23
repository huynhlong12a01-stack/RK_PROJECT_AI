@echo off
chcp 65001 >nul
title Tao du an noi suy moi
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_UNG_DUNG\engine\scripts\create_new_project.ps1"
echo.
pause
