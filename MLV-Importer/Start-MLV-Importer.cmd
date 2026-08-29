@echo off
title Magic Lantern MLV Importer

cd /d "%~dp0"

echo.
echo ============================================================
echo        Magic Lantern MLV Importer
echo ============================================================
echo.
echo Starting...
echo.

powershell.exe ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%~dp0MLV-Importer.ps1"

echo.
echo Importer stopped.
echo.
pause