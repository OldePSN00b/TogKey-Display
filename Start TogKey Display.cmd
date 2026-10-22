@echo off
where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo PowerShell 7 is required. Install it, then open this launcher again.
  pause
  exit /b 1
)
start "TogKey Display" pwsh.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0TogKey Display.ps1"
