@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ps = Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -match 'monitor\.ps1' }; foreach ($p in $ps) { Stop-Process -Id $p.ProcessId -ErrorAction SilentlyContinue; 'stopped PID ' + $p.ProcessId }; if (-not $ps) { 'not running' }; Remove-Item monitor.pid -ErrorAction SilentlyContinue"
