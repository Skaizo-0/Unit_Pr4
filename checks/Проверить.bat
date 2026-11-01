@echo off
chcp 65001 >nul
setlocal
set "PYTHONUTF8=1"
if "%~1"=="" goto usage
set "practice=%~2"
if not defined practice set /p "practice=Practice (4.1 or 4.2): "
python -B "%~dp0check_submission.py" --practice "%practice%" "%~1"
set "result=%errorlevel%"
echo Exit code: %result%
pause
exit /b %result%
:usage
echo Drag the submission folder here or use: "%~nx0" "folder" 4.1
pause
exit /b 2
