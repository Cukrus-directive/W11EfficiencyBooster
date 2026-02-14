@echo off
:: EfficiencyMode-Setup Launcher
:: Checks for admin and runs the PowerShell setup script

:: Check for administrative privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo [!] This script requires administrative privileges for task registration.
    echo [!] Restarting with elevated rights...
    powershell -Command "Start-Process '%~f0' -Verb runAs"
    exit /b
)

:: Confirm elevation
echo [+] Running with administrative privileges.
echo.

:: Set PowerShell script path
set "PS1_FILE=%~dp0EfficiencyMode-Setup.ps1"

:: Validate existence
if not exist "%PS1_FILE%" (
    echo [X] Cannot find PowerShell script: %PS1_FILE%
    pause
    exit /b 1
)

:: Run PowerShell script with ExecutionPolicy Bypass
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1_FILE%"

pause
