@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "if (Test-Path monitor.pid) { $id = Get-Content monitor.pid; Stop-Process -Id $id -ErrorAction SilentlyContinue; Remove-Item monitor.pid; 'stopped PID ' + $id } else { 'not running (no monitor.pid)' }"
