@echo off
rem Double-click or run "deploy" / "deploy ZodUI". Passes arguments on to deploy.ps1.
rem Uses PowerShell 7 (pwsh) when installed. Windows PowerShell 5.1 started from a pwsh
rem terminal inherits pwsh's PSModulePath and cannot load Get-FileHash.
where pwsh >nul 2>nul
if %errorlevel%==0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1" %*
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1" %*
)
exit /b %errorlevel%
