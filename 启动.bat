@echo off
setlocal EnableExtensions

cd /d "%~dp0"
title JP Tool Start

echo [JP Tool] Starting...

python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python is not available. Install Python 3.11+ first.
    echo [INFO]  https://www.python.org/downloads/
    pause
    exit /b 1
)

if not exist "backend\.venv\Scripts\python.exe" (
    echo [JP Tool] Creating backend virtual environment...
    pushd backend
    python -m venv .venv
    call .venv\Scripts\activate.bat
    python -m pip install --upgrade pip >nul
    pip install fastapi "uvicorn[standard]" websockets fugashi unidic-lite pydantic httpx pyperclip -q
    popd
)

if not exist "frontend\build\web\index.html" (
    where flutter >nul 2>&1
    if errorlevel 1 (
        echo [WARN] Flutter SDK not found. Web UI build is missing.
        echo [WARN] Install Flutter or run app with an existing web frontend.
    ) else (
        echo [JP Tool] Building Flutter Web (first time may take a while)...
        pushd frontend
        call flutter pub get
        call flutter build web --release --dart-define=FLUTTER_WEB_CANVASKIT_URL=/canvaskit/
        if errorlevel 1 (
            echo [WARN] Flutter web build failed. Backend will still start.
        )
        popd
    )
)

set "JP_TOOL_LLM=auto"
set "JP_TOOL_GRAMMAR_AUTO_LEARN=on"
set "JP_TOOL_PORT="

for %%P in (8765 18765 28675 38575 47865) do (
    if not defined JP_TOOL_PORT (
        netstat -ano | findstr /R /C:":%%P .*LISTENING" >nul
        if errorlevel 1 set "JP_TOOL_PORT=%%P"
    )
)

if not defined JP_TOOL_PORT (
    echo [ERROR] No candidate port is available.
    echo [ERROR] Checked ports: 8765 18765 28675 38575 47865
    pause
    exit /b 1
)

echo [JP Tool] Backend port selected: %JP_TOOL_PORT%
echo [JP Tool] Opening browser: http://localhost:%JP_TOOL_PORT%
start "" "http://localhost:%JP_TOOL_PORT%"

echo [JP Tool] Backend running on http://localhost:%JP_TOOL_PORT%
echo [JP Tool] Press Ctrl+C in this window to stop.

pushd backend
call .venv\Scripts\activate.bat
python main.py
popd

echo [JP Tool] Backend stopped.
pause