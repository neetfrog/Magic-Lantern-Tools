@echo off
cd /d "%~dp0"

powershell.exe ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%~dp0Config-GUI.ps1"

pause