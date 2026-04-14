@echo off
:: 设置代码页为 UTF-8 确保中文不乱码
chcp 65001 >nul
title 日语语法解析器 - Flutter 打包

echo.
echo  ========================================
echo    日语语法解析器 - Flutter 桌面打包
echo  ========================================
echo.

:: 1. 跳过复杂的环境检查，直接尝试进入目录
if not exist "frontend" (
    echo [错误] 找不到 frontend 文件夹，请在项目根目录运行此脚本。
    pause
    exit /b 1
)

cd frontend

:: 2. 初始化项目（如果 windows 目录不存在）
if not exist "windows" (
    echo [1/3] 正在生成 Windows 平台文件...
    call flutter create --platforms windows . 
)

:: 3. 获取依赖
echo [2/3] 正在安装依赖...
call flutter pub get

:: 4. 执行编译
echo [3/3] 正在编译 Windows 桌面应用 (Release)...
:: 使用 call 确保命令执行完后返回脚本
call flutter build windows --release

if %errorlevel% neq 0 (
    echo.
    echo [错误] 编译过程中出现问题，请检查上方日志。
    pause
    exit /b 1
)

echo.
echo  ================================================
echo   打包成功!
echo   输出目录: build\windows\x64\runner\Release\
echo  ================================================
echo.
pause