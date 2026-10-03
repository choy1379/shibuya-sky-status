@echo off
cd /d "%~dp0"
call "%~dp0stop.cmd"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','\"%~dp0monitor.ps1\"'; Set-Content -Path '%~dp0monitor.pid' -Value $p.Id; 'started PID ' + $p.Id"
