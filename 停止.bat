@echo off
chcp 65001 >nul
echo.
echo  正在停止日语语法解析器...
echo.

REM 查找并关闭 python main.py 进程
taskkill /F /FI "WINDOWTITLE eq 日语语法解析器*" >nul 2>&1
taskkill /F /IM python.exe /FI "WINDOWTITLE eq 日语语法解析器*" >nul 2>&1

REM 更精准: 查找监听 8765 端口的进程并关闭
for /f "tokens=5" %%a in ('netstat -aon ^| findstr ":8765" ^| findstr "LISTENING"') do (
    echo  正在关闭进程 PID: %%a
    taskkill /F /PID %%a >nul 2>&1
)

echo.
echo  [完成] 后端已停止
echo.
pause
