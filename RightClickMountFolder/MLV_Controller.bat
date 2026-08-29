@echo off
:: Re-run as Administrator if not already elevated
net session >nul 2>&1 || (
    powershell -Command "Start-Process '%~f0' -Verb RunAs -ArgumentList '%*'"
    exit
)

if "%~1"=="mount" goto :mount
if "%~1"=="mount-dual" goto :mount_dual
if "%~1"=="unmount" goto :unmount
goto :eof

:mount
set "EXTRA_ARGS=--stripes"
goto :run_mlvfs

:mount_dual
set "EXTRA_ARGS=--dual-iso"
goto :run_mlvfs

:run_mlvfs
:: Forcefully kill any existing mlvfs process to prevent conflicts
taskkill /F /IM mlvfs_x64_lossless.exe /T >nul 2>&1

:: Force unmount the drive letter if it is still active or hung[cite: 2]
"C:\Program Files\Dokan\Dokan Library-1.0.3\dokanctl.exe" /u Z /f >nul 2>&1

:: Change to the tool directory
cd /d "C:\MLVFS\MLVFS_x64_lossless"

:: Launch the process with optional arguments[cite: 2]
powershell -Command "Start-Process 'mlvfs_x64_lossless.exe' -ArgumentList 'Z:\ --mlv-dir=\"%~2\" --resolve-naming %EXTRA_ARGS%' -WindowStyle Hidden"
goto :eof

:unmount
:: Silence the output of dokanctl and force unmount[cite: 2]
"C:\Program Files\Dokan\Dokan Library-1.0.3\dokanctl.exe" /u Z /f >nul 2>&1
goto :eof
