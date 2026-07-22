@echo off
REM Double-click this file to run the palette creator (PLAN §19.5 — no command line).
REM It starts the local server and opens the app in your browser. Close this window to stop.

setlocal
cd /d "%~dp0"

where node >nul 2>nul
if errorlevel 1 (
  echo.
  echo   Node.js is not installed, or not on your PATH.
  echo   Install Node 22 or newer from https://nodejs.org and run this again.
  echo.
  pause
  exit /b 1
)

echo Starting the palette creator... your browser will open in a moment.
echo Close this window when you are finished.
echo.
REM --replace: if this was already running, take the port back from it, so double-clicking
REM this file again is a restart rather than an "address already in use" error.
node tools/serve.mjs --open --replace

echo.
echo The server has stopped.
pause
