@echo off
REM === BAR Caster Widget Deploy Script ===
REM Copies the widget to the BAR widgets folder

set "BAR_DIR=C:\Program Files\Beyond-All-Reason\data\LuaUI\Widgets"
set "WIDGET=gui_caster_widget.lua"
set "MODULES=caster_modules"

echo === BAR Caster Widget Deploy ===
echo.

REM Create widgets folder if needed
if not exist "%BAR_DIR%" (
    echo Creating folder: %BAR_DIR%
    mkdir "%BAR_DIR%"
)

REM Copy main widget
echo Copying %WIDGET% to %BAR_DIR%\
copy /Y "%~dp0%WIDGET%" "%BAR_DIR%\%WIDGET%"

REM Copy modules folder (all .lua files from caster_modules/)
if exist "%~dp0%MODULES%" (
    echo Copying %MODULES%\ to %BAR_DIR%\%MODULES%\
    if not exist "%BAR_DIR%\%MODULES%" mkdir "%BAR_DIR%\%MODULES%"
    xcopy /Y /E /I "%~dp0%MODULES%\*.lua" "%BAR_DIR%\%MODULES%\" >nul
)

if %ERRORLEVEL% EQU 0 (
    echo.
    echo Done! Widget copied.
    echo.
    echo Next steps:
    echo   1. Start BAR
    echo   2. Watch a replay or spectate a game
    echo   3. Press F11 and enable "BAR Caster Widget"
    echo   4. After changes: /luaui reload in game
) else (
    echo.
    echo ERROR: Copy failed!
    echo Tip: Run this script as Administrator
)

echo.
pause
