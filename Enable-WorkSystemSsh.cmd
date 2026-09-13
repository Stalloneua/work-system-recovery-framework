@echo off
setlocal EnableExtensions DisableDelayedExpansion

if "%WORKSYSTEM_SSH_PUBLIC_KEY%"=="" (
  echo ERROR: Set WORKSYSTEM_SSH_PUBLIC_KEY to the authorized ED25519 public key first.
  echo Example:
  echo   set "WORKSYSTEM_SSH_PUBLIC_KEY=ssh-ed25519 AAAA..."
  exit /b 2
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Enable-WorkSystemSsh.ps1" -PublicKey "%WORKSYSTEM_SSH_PUBLIC_KEY%"
set "RESULT=%errorlevel%"
if not "%RESULT%"=="0" (
  echo ERROR: OpenSSH bootstrap failed with exit code %RESULT%.
  exit /b %RESULT%
)

echo OpenSSH bootstrap completed.
exit /b 0
