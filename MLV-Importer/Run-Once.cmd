@echo off
title Magic Lantern MLV Importer - Run Once

cd /d "%~dp0"

echo.
echo ============================================================
echo        Magic Lantern MLV Importer - Run Once
echo ============================================================
echo.

powershell.exe ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -Command "& '%~dp0MLV-Importer.ps1'"

pause