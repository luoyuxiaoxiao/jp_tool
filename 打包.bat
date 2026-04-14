@echo off
chcp 65001 >nul
title 日语语法解析器 - Windows 打包

echo.
echo  ╔══════════════════════════════════════╗
echo  ║    日语语法解析器 - 打包为 EXE       ║
echo  ╚══════════════════════════════════════╝
echo.

REM ── 检查环境 ──
python --version >nul 2>&1
if errorlevel 1 (
    echo  [错误] 未检测到 Python
    pause
    exit /b 1
)

cd backend

REM ── 确保虚拟环境 ──
if not exist .venv (
    echo  [1/5] 创建虚拟环境...
    python -m venv .venv
)
call .venv\Scripts\activate.bat

REM ── 安装依赖 ──
echo  [2/5] 安装依赖...
pip install fastapi "uvicorn[standard]" websockets fugashi unidic-lite pydantic httpx pyperclip pyinstaller -q

REM ── 打包 ──
echo  [3/5] 正在打包 (可能需要1-2分钟)...
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

if errorlevel 1 (
    echo  [错误] 打包失败
    pause
    exit /b 1
)

REM ── 复制前端 ──
echo  [4/5] 复制前端文件...
if not exist dist\jp_grammar\frontend mkdir dist\jp_grammar\frontend
copy /Y ..\test.html dist\jp_grammar\frontend\index.html >nul

REM ── 创建启动脚本 ──
echo  [5/5] 创建启动脚本...
(
echo @echo off
echo chcp 65001 ^>nul
echo title 日语语法解析器
echo echo.
echo echo  日语语法解析器启动中...
echo echo  浏览器将自动打开 http://localhost:8765
echo echo  按 Ctrl+C 停止
echo echo.
echo start "" "http://localhost:8765"
echo jp_grammar.exe
) > dist\jp_grammar\启动.bat

cd ..

echo.
echo  ╔══════════════════════════════════════╗
echo  ║           打包完成!                  ║
echo  ╠══════════════════════════════════════╣
echo  ║  输出: backend\dist\jp_grammar\      ║
echo  ║  双击「启动.bat」即可运行            ║
echo  ╚══════════════════════════════════════╝
echo.
pause
