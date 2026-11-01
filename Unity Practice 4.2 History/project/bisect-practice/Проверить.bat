@echo off
setlocal
set GIT_MASTER=1
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dpn0.ps1" %*
exit /b %errorlevel%
