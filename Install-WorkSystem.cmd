@echo off
setlocal EnableExtensions

set "REPOSITORY=rclone:work-drive:Work System/00 Recovery/restic-foundation"

where powershell.exe >nul 2>&1
if errorlevel 1 (
  echo ERROR: Windows PowerShell is required.
  exit /b 1
)

echo Starting Work System bootstrap.
echo Secure Google sign-in and the independently stored recovery passphrase may be requested.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0bootstrap.ps1" -Repository "%REPOSITORY%" -Apply
set "RESULT=%ERRORLEVEL%"

if not "%RESULT%"=="0" (
  echo ERROR: Bootstrap failed with exit code %RESULT%.
  echo Run Repair-WorkSystem.ps1 after correcting the reported prerequisite.
  exit /b %RESULT%
)

echo Work System bootstrap completed.
exit /b 0
