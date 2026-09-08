@echo off
setlocal DisableDelayedExpansion

:: ============================================================
:: MLVFS Controller (File-Hook Architecture)
:: ============================================================

set "HOOK_FILE=C:\MLVScripts\RightClickMountFolder\last_path.tmp"

:: Save incoming path cleanly without trailing spaces
if not "%~2"=="" (
    <nul set /p="%~2" > "%HOOK_FILE%"
)

:: Re-run as Administrator if not already elevated
net session >nul 2>&1
if errorlevel 1 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs -ArgumentList '%~1'"
    exit /b
)

:: ============================================================
:: Select operation
:: ============================================================

if /I "%~1"=="mount" goto :mount
if /I "%~1"=="mount-dual" goto :mount-dual
if /I "%~1"=="unmount" goto :unmount

exit /b


:: ============================================================
:: STANDARD MOUNT
:: ============================================================

:mount
set "EXTRA_ARGS=--stripes"
goto :read_hook


:: ============================================================
:: DUAL ISO MOUNT
:: ============================================================

:mount-dual
set "EXTRA_ARGS=--dual-iso"
goto :read_hook


:: ============================================================
:: READ PATH FROM HOOK FILE
:: ============================================================

:read_hook

if not exist "%HOOK_FILE%" exit /b 1

set /p TARGET_DIR= < "%HOOK_FILE%"

if "%TARGET_DIR%"=="" exit /b 1

set "MLV_DIR=%TARGET_DIR%"

if not exist "%MLV_DIR%" exit /b 1

:: ------------------------------------------------------------
:: Kill existing MLVFS process
:: ------------------------------------------------------------

taskkill /F /IM mlvfs_x64_lossless.exe /T >nul 2>&1

:: ------------------------------------------------------------
:: Force-unmount Z:
:: ------------------------------------------------------------

"C:\Program Files\Dokan\Dokan Library-1.0.3\dokanctl.exe" /u Z /f >nul 2>&1

:: ------------------------------------------------------------
:: MLVFS directory
:: ------------------------------------------------------------

cd /d "C:\MLVScripts\MLVFS\MLVFS_x64_lossless"

if errorlevel 1 exit /b 1

:: ============================================================
:: LAUNCH SILENTLY AND EXIT INSTANTLY
:: ============================================================

start "" /b mlvfs_x64_lossless.exe Z:\ --mlv-dir="%MLV_DIR%" --resolve-naming %EXTRA_ARGS%

exit /b


:: ============================================================
:: UNMOUNT
:: ============================================================

:unmount

"C:\Program Files\Dokan\Dokan Library-1.0.3\dokanctl.exe" /u Z /f

exit /b