@echo off
title MagicDump

cd /d "%~dp0"

echo.
echo ============================================================
echo        MagicDump
echo ============================================================
echo.
echo Starting...
echo.

powershell.exe ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%~dp0core\MLV-Importer.ps1"

echo.
echo Importer stopped.
echo.
pause