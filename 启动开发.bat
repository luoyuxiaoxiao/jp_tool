@echo off
setlocal EnableExtensions

cd /d "%~dp0"
title JP Tool Dev Start

set "RUN_DIR=.run"
if not exist "%RUN_DIR%" mkdir "%RUN_DIR%"

call "停止开发.bat" /quiet >nul 2>&1

echo [JP Tool Dev] Preparing environment...

python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python is not available. Install Python 3.11+ first.
    pause
    exit /b 1
)

if not exist "backend\.venv\Scripts\python.exe" (
    echo [JP Tool Dev] Creating backend virtual environment...
    pushd backend
    python -m venv .venv
    call .venv\Scripts\activate.bat
    python -m pip install --upgrade pip >nul
    pip install fastapi "uvicorn[standard]" websockets fugashi unidic-lite pydantic httpx pyperclip -q
    popd
)

where flutter >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Flutter SDK is not available in PATH.
    pause
    exit /b 1
)

echo [JP Tool Dev] Starting backend window...
for /f %%P in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/k','cd /d \"%cd%\backend\" && call .venv\Scripts\activate.bat && python main.py' -PassThru; $p.Id"') do set "BACKEND_PID=%%P"
if not defined BACKEND_PID (
    echo [ERROR] Failed to start backend process.
    pause
    exit /b 1
)
> "%RUN_DIR%\backend.pid" echo %BACKEND_PID%

echo [JP Tool Dev] Starting Flutter Web (hot reload) window...
for /f %%P in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/k','cd /d \"%cd%\frontend\" && flutter pub get && flutter run -d chrome --web-hostname localhost --web-port 5173 --dart-define=FLUTTER_WEB_CANVASKIT_URL=http://localhost:5173/canvaskit/' -PassThru; $p.Id"') do set "FRONTEND_PID=%%P"
if not defined FRONTEND_PID (
    echo [ERROR] Failed to start Flutter web process.
    pause
    exit /b 1
)
> "%RUN_DIR%\frontend.pid" echo %FRONTEND_PID%

echo.
echo [JP Tool Dev] Started.
echo   Backend PID : %BACKEND_PID%
echo   Frontend PID: %FRONTEND_PID%
echo   Backend URL : http://localhost:8765
echo   Frontend URL: http://localhost:5173
echo.
echo [JP Tool Dev] Use 停止开发.bat to stop both processes.

start "" "http://localhost:5173"
