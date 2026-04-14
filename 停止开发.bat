@echo off
setlocal EnableExtensions

cd /d "%~dp0"
title JP Tool Dev Stop

set "QUIET=0"
if /i "%~1"=="/quiet" set "QUIET=1"
set "RUN_DIR=.run"

call :kill_by_pid_file backend
call :kill_by_pid_file frontend

call :kill_by_port 8765
call :kill_by_port 5173

if "%QUIET%"=="1" exit /b 0

echo [JP Tool Dev] Stop completed.
pause
exit /b 0

:kill_by_pid_file
set "NAME=%~1"
set "PID_FILE=%RUN_DIR%\%NAME%.pid"
if not exist "%PID_FILE%" goto :eof

set "PID="
set /p PID=<"%PID_FILE%"
if defined PID (
    taskkill /PID %PID% /T /F >nul 2>&1
)
del /q "%PID_FILE%" >nul 2>&1
if "%QUIET%"=="0" echo [JP Tool Dev] Stopped %NAME% (pid file).
goto :eof

:kill_by_port
set "PORT=%~1"
for /f "tokens=5" %%P in ('netstat -ano ^| findstr ":%PORT%" ^| findstr "LISTENING"') do (
    taskkill /PID %%P /T /F >nul 2>&1
)
if "%QUIET%"=="0" echo [JP Tool Dev] Port %PORT% checked.
goto :eof
