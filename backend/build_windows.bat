@echo off
chcp 65001 >nul
title JP Grammar Analyzer - Build

echo ========================================
echo   日语语法解析器 - Windows 打包脚本
echo ========================================
echo.

REM ── 检查 Python ──
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] 未找到 Python，请先安装 Python 3.11+
    echo 下载地址：https://www.python.org/downloads/
    pause
    exit /b 1
)

REM ── 创建虚拟环境 ──
echo [1/4] 创建虚拟环境...
if not exist .venv (
    python -m venv .venv
)
call .venv\Scripts\activate.bat

REM ── 安装依赖 ──
echo [2/4] 安装依赖...
pip install fastapi "uvicorn[standard]" websockets fugashi unidic-lite pydantic httpx pyperclip pyinstaller -q

REM ── 打包 ──
echo [3/4] 打包为 exe...
pyinstaller --noconfirm --onedir --name jp_grammar ^
    --add-data "data;data" ^
    --add-data "analyzer;analyzer" ^
    --add-data "capture;capture" ^
    --add-data "llm;llm" ^
    --hidden-import uvicorn.logging ^
    --hidden-import uvicorn.loops ^
    --hidden-import uvicorn.loops.auto ^
    --hidden-import uvicorn.protocols ^
    --hidden-import uvicorn.protocols.http ^
    --hidden-import uvicorn.protocols.http.auto ^
    --hidden-import uvicorn.protocols.websockets ^
    --hidden-import uvicorn.protocols.websockets.auto ^
    --hidden-import uvicorn.lifespan ^
    --hidden-import uvicorn.lifespan.on ^
    --hidden-import fugashi ^
    --hidden-import unidic_lite ^
    --collect-data unidic_lite ^
    --collect-data fugashi ^
    main.py

REM ── 复制前端文件 ──
echo [4/4] 复制前端文件...
if not exist dist\jp_grammar\frontend mkdir dist\jp_grammar\frontend
if exist ..\jp_manager.html (
    copy /Y ..\jp_manager.html dist\jp_grammar\frontend\index.html >nul
) else (
    echo [WARN] 未找到 ..\jp_manager.html，前端页面可能缺失
)
if exist ..\jp_manager.ccs (
    copy /Y ..\jp_manager.ccs dist\jp_grammar\frontend\jp_manager.ccs >nul
)

REM ── 创建启动脚本 ──
(
echo @echo off
echo chcp 65001 ^>nul
echo title 日语语法解析器
echo echo 日语语法解析器启动中...
echo start "" "http://localhost:8765/app"
echo jp_grammar.exe
) > dist\jp_grammar\启动.bat

echo.
echo ========================================
echo   打包完成！
echo   输出目录：dist\jp_grammar\
echo   双击 dist\jp_grammar\启动.bat 即可运行
echo ========================================
pause
