@echo off
setlocal

rem Legacy direct-host hidden launcher. Prefer Docker for Open WebUI.
set PI_WORKSPACE=%CD%
set BRIDGE_DIR=%~dp0
cd /d "%BRIDGE_DIR%"

if not exist .bridge-key exit /b 1
set /p PI_BRIDGE_API_KEY=<.bridge-key
if "%HOST%"=="" set HOST=0.0.0.0
if "%PORT%"=="" set PORT=11435
if "%PI_PUBLIC_BASE_URL%"=="" set PI_PUBLIC_BASE_URL=http://127.0.0.1:%PORT%
if "%PI_TOOLS%"=="" set PI_TOOLS=read,bash,edit,write,grep,find,ls

start "PiBot Legacy Direct Bridge" /min cmd /c "node src\server.js > bridge.out.log 2> bridge.err.log"
