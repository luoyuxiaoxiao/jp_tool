@echo off
chcp 65001 >nul
title 日语语法解析器 - 启动面板

echo.
echo  ╔══════════════════════════════════════╗
echo  ║      日语语法解析器 - 启动面板       ║
echo  ╚══════════════════════════════════════╝
echo.

REM ── 检测 Python 3.11+ ──
python --version >nul 2>&1
if errorlevel 1 (
    echo  [错误] 未检测到 Python，请先安装 Python 3.11+
    echo  下载地址: https://www.python.org/downloads/
    pause
    exit /b 1
)

REM 检测Python版本（确保3.11+）
for /f "tokens=2 delims=." %%a in ('python --version 2^>^&1 ^| findstr /i "Python"') do (
    set "PY_MINOR=%%a"
)
for /f "tokens=1 delims= " %%a in ('python --version 2^>^&1 ^| findstr /i "Python"') do (
    set "PY_MAJOR=%%a"
)
set "PY_MAJOR=%PY_MAJOR:Python 3.=%"
if %PY_MAJOR% LSS 3 (
    echo  [错误] Python版本需3.11+，当前版本过低
    pause
    exit /b 1
)
if %PY_MINOR% LSS 11 (
    echo  [错误] Python版本需3.11+，当前版本：3.%PY_MINOR%
    pause
    exit /b 1
)

REM ── 检测虚拟环境 ──
if not exist "backend\.venv" (
    echo  [首次运行] 正在创建虚拟环境并安装依赖...
    cd backend
    python -m venv .venv
    call .venv\Scripts\activate.bat
    pip install fastapi "uvicorn[standard]" websockets fugashi unidic-lite pydantic httpx pyperclip -q
    cd ..
    echo  [完成] 依赖安装完毕
    echo.
)

REM ── 选择模式 ──
echo  请选择启动模式:
echo.
echo    [1] 完整模式 (后端 + 浏览器界面 + Ollama 深度分析)
echo    [2] 轻量模式 (后端 + 浏览器界面, 不使用大模型)
echo    [3] 仅启动后端 (用于 Flutter 前端连接)
echo    [4] 自定义 LLM 设置
echo.
set "choice="
set /p choice="  输入选项 (1-4, 默认1): "
if "%choice%"=="" set "choice=1"

REM ── 配置 LLM ──
if "%choice%"=="1" (
    set "JP_TOOL_LLM=auto"
    echo.
    echo  [模式] 完整模式 - 自动检测 Ollama
) else if "%choice%"=="2" (
    set "JP_TOOL_LLM=off"
    echo.
    echo  [模式] 轻量模式 - 仅本地分词 + 语法匹配
) else if "%choice%"=="3" (
    set "JP_TOOL_LLM=auto"
    echo.
    echo  [模式] 仅后端 - 等待前端连接
    goto :start_backend
) else if "%choice%"=="4" (
    goto :custom_llm
) else (
    set "JP_TOOL_LLM=auto"
)

REM ── 打开浏览器 ──
echo  [启动] 3秒后打开浏览器...
timeout /t 3 /nobreak >nul
start "" "http://localhost:8765"

:start_backend
echo  [启动] 正在启动后端服务...
echo.
echo  ════════════════════════════════════════
echo   后端运行中: http://localhost:8765
echo   WebSocket:  ws://localhost:8765/ws
echo   按 Ctrl+C 停止服务
echo  ════════════════════════════════════════
echo.

cd backend
call .venv\Scripts\activate.bat
python main.py
goto :end

:custom_llm
echo.
echo  选择 LLM 提供者:
echo    [1] Ollama (本地大模型, 默认 qwen2.5:7b)
echo    [2] Ollama (自定义模型名)
echo    [3] Claude API (需要 API Key)
echo    [4] 不使用大模型
echo.
set "llm_choice="
set /p llm_choice="  输入选项 (1-4): "

if "%llm_choice%"=="1" (
    set "JP_TOOL_LLM=ollama"
    set "OLLAMA_MODEL=qwen2.5:7b"
) else if "%llm_choice%"=="2" (
    set "JP_TOOL_LLM=ollama"
    set "OLLAMA_MODEL="
    set /p OLLAMA_MODEL="  输入模型名 (如 qwen3:8b): "
) else if "%llm_choice%"=="3" (
    set "JP_TOOL_LLM=claude"
    set "ANTHROPIC_API_KEY="
    set /p ANTHROPIC_API_KEY="  输入 Anthropic API Key: "
) else (
    set "JP_TOOL_LLM=off"
)

echo.
start "" "http://localhost:8765"
goto :start_backend

:end
pause