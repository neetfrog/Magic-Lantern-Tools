@echo off
title MagicDump Configuration GUI

cd /d "%~dp0"

powershell.exe ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -WindowStyle Hidden ^
    -File "%~dp0core\Config-GUI.ps1"