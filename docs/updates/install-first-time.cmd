@echo off
setlocal

set "SCRIPT_URL=https://c3812600.github.io/RCC-Release/updates/install-first-time.ps1"
set "TEMP_SCRIPT=%TEMP%\RCC-install-first-time.ps1"

echo Downloading first-time installer...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%SCRIPT_URL%' -OutFile '%TEMP_SCRIPT%' -UseBasicParsing"
if errorlevel 1 (
    echo Failed to download install-first-time.ps1
    pause
    exit /b 1
)

echo Launching first-time installer...
powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP_SCRIPT%"
if errorlevel 1 (
    echo First-time installer failed.
    pause
    exit /b 1
)

echo Install flow completed.
pause
