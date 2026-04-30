@echo off
setlocal EnableDelayedExpansion

REM Dashboard URL file with retry ? handles the window where manager is
REM restarting but hasn't written the URL file yet.
set "URL_FILE=%USERPROFILE%\AppData\Local\manager-mcp\dashboard_url.txt"
set "MAX_TRIES=15"
set "TRIES=0"

:check_loop
set /a TRIES+=1
if exist "%URL_FILE%" goto found

if !TRIES! GEQ !MAX_TRIES! goto not_found

echo Dashboard URL not ready yet (attempt !TRIES!/!MAX_TRIES!) ? retrying in 2s...
timeout /t 2 /nobreak >nul
goto check_loop

:found
set /p URL=<"%URL_FILE%"
echo Opening: !URL!
start "" "!URL!"
exit /b 0

:not_found
echo.
echo Dashboard URL file not found after !MAX_TRIES! attempts:
echo   %URL_FILE%
echo.
echo Possible causes:
echo   - manager-mcp crashed or isn't configured in claude_desktop_config.json
echo   - Claude Desktop is closed (no manager process)
echo   - You're logged in as a different Windows user
echo.
echo Quick checks:
echo   1. Is manager.exe running? (Task Manager -^> Details)
echo   2. Is the config at %%APPDATA%%\Claude\claude_desktop_config.json valid?
echo   3. Run: type %%USERPROFILE%%\AppData\Local\manager-mcp\manager.lock
echo.
pause
exit /b 1
