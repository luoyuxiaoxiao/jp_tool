@echo off
REM ── JP Grammar Analyzer: Flutter Desktop Setup (Windows) ──
REM Run this script in PowerShell or CMD on Windows.
REM It initializes the Flutter project skeleton and copies in our source code.

echo === Step 1: Create Flutter project ===
cd /d "%~dp0"

REM If lib/ already has our code, back it up
if exist lib\main.dart (
    echo Backing up existing lib\ to lib_backup\
    xcopy /E /I /Y lib lib_backup >nul
)

REM Create a fresh Flutter project in a temp dir then merge
flutter create --org com.jptool --project-name jp_grammar_analyzer --platforms windows _temp_project

REM Copy platform files we don't have
if not exist windows (
    xcopy /E /I /Y _temp_project\windows windows >nul
)
if not exist test (
    xcopy /E /I /Y _temp_project\test test >nul
)

REM Copy .metadata and other root files if missing
if not exist ".metadata" copy _temp_project\.metadata . >nul
if not exist "l10n.yaml" if exist _temp_project\l10n.yaml copy _temp_project\l10n.yaml . >nul

REM Restore our source code
if exist lib_backup\main.dart (
    xcopy /E /I /Y lib_backup lib >nul
    rmdir /S /Q lib_backup
)

REM Clean up temp
rmdir /S /Q _temp_project

echo === Step 2: Install dependencies ===
flutter pub get

echo === Step 3: Verify ===
flutter doctor

echo.
echo === Done! Run with: flutter run -d windows ===
pause
