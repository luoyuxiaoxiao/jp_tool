@echo off
chcp 65001 >nul
title 日语语法解析器 - Flutter 打包

echo.
echo  ╔══════════════════════════════════════╗
echo  ║   日语语法解析器 - Flutter 桌面打包  ║
echo  ╚══════════════════════════════════════╝
echo.

REM ── 检查 Flutter ──
flutter --version >nul 2>&1
if errorlevel 1 (
    echo  [错误] 未检测到 Flutter SDK
    echo  下载地址: https://docs.flutter.dev/get-started/install/windows
    pause
    exit /b 1
)

cd frontend

REM ── 初始化项目 (如果没有 windows/ 目录) ──
if not exist windows (
    echo  [1/4] 初始化 Flutter Desktop 项目...

    REM 备份源码
    if exist lib\main.dart xcopy /E /I /Y lib lib_backup >nul

    REM 创建临时项目获取平台文件
    flutter create --org com.jptool --project-name jp_grammar_analyzer --platforms windows _temp >nul 2>&1
    xcopy /E /I /Y _temp\windows windows >nul
    if not exist test xcopy /E /I /Y _temp\test test >nul
    if not exist ".metadata" copy _temp\.metadata . >nul 2>&1
    rmdir /S /Q _temp

    REM 恢复源码
    if exist lib_backup\main.dart (
        xcopy /E /I /Y lib_backup lib >nul
        rmdir /S /Q lib_backup
    )
    echo  [完成] 平台文件已生成
)

REM ── 安装依赖 ──
echo  [2/4] 安装 Flutter 依赖...
flutter pub get

REM ── 编译 ──
echo  [3/4] 编译 Windows 桌面应用 (可能需要几分钟)...
flutter build windows --release

if errorlevel 1 (
    echo  [错误] 编译失败
    pause
    exit /b 1
)

REM ── 完成 ──
echo  [4/4] 完成!
echo.
echo  ╔══════════════════════════════════════════════════╗
echo  ║  输出: build\windows\x64\runner\Release\         ║
echo  ║  运行: jp_grammar_analyzer.exe                   ║
echo  ║  注意: 需要先启动后端 (启动.bat)                  ║
echo  ╚══════════════════════════════════════════════════╝
echo.

cd ..
pause
