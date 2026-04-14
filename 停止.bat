@echo off
setlocal EnableExtensions

title JP Tool Stop

set "KILLED=0"
for %%L in (8765 18765 28675 38575 47865) do (
    for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R /C:":%%L .*LISTENING"') do (
        taskkill /PID %%P /F >nul 2>&1
        if not errorlevel 1 set "KILLED=1"
    )
)

if "%KILLED%"=="1" (
    echo [JP Tool] Stopped process on candidate ports.
) else (
    echo [JP Tool] No process is listening on candidate ports.
)

pause
