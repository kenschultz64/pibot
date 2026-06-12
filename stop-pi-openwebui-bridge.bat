@echo off
setlocal

echo Stopping Pi OpenWebUI Bridge on port 11435...

powershell -NoProfile -ExecutionPolicy Bypass -Command "$conns = Get-NetTCPConnection -LocalPort 11435 -State Listen -ErrorAction SilentlyContinue; if (-not $conns) { Write-Host 'No bridge listener found on port 11435.'; exit 0 }; foreach ($conn in $conns) { Write-Host ('Stopping PID ' + $conn.OwningProcess); Stop-Process -Id $conn.OwningProcess -Force }"

echo Done.
pause
