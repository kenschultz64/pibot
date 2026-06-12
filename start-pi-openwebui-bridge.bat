@echo off
setlocal

rem Legacy direct-host launcher. Prefer Docker for Open WebUI.
rem Workspace is the folder where you launch this batch file from.
set PI_WORKSPACE=%CD%

rem Bridge app is the folder where this script lives.
set BRIDGE_DIR=%~dp0
cd /d "%BRIDGE_DIR%"

if not exist .bridge-key (
  echo ERROR: .bridge-key not found in %BRIDGE_DIR%
  echo Create one first, for example: powershell -Command "'pi-' + [guid]::NewGuid().ToString('N') ^| Set-Content .bridge-key"
  pause
  exit /b 1
)

set /p PI_BRIDGE_API_KEY=<.bridge-key
if "%HOST%"=="" set HOST=0.0.0.0
if "%PORT%"=="" set PORT=11435
if "%PI_PUBLIC_BASE_URL%"=="" set PI_PUBLIC_BASE_URL=http://127.0.0.1:%PORT%
if "%PI_TOOLS%"=="" set PI_TOOLS=read,bash,edit,write,grep,find,ls

echo Starting PiBot legacy direct bridge...
echo Base URL: %PI_PUBLIC_BASE_URL%/v1
echo Bridge app: %BRIDGE_DIR%
echo Workspace: %PI_WORKSPACE%
echo Tools: %PI_TOOLS%
echo WARNING: Direct mode exposes the host workspace to the agent. Prefer Docker for Open WebUI.

node src\server.js

pause
