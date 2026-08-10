@echo off
chcp 65001 > nul
setlocal

REM ============================================================
REM 3000, 9090 포트를 사용하는 kubectl port-forward만 종료
REM ============================================================

echo.
echo Monitoring 포트포워딩을 종료합니다.

powershell.exe -NoProfile -Command "$connections=Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue; foreach($connection in $connections){$process=Get-Process -Id $connection.OwningProcess -ErrorAction SilentlyContinue; if($process.ProcessName -eq 'kubectl'){Stop-Process -Id $process.Id -Force; Write-Host 'Grafana 포트포워딩 종료 완료'}}"

powershell.exe -NoProfile -Command "$connections=Get-NetTCPConnection -LocalPort 9090 -State Listen -ErrorAction SilentlyContinue; foreach($connection in $connections){$process=Get-Process -Id $connection.OwningProcess -ErrorAction SilentlyContinue; if($process.ProcessName -eq 'kubectl'){Stop-Process -Id $process.Id -Force; Write-Host 'Prometheus 포트포워딩 종료 완료'}}"

timeout /t 2 /nobreak > nul

echo.
echo 현재 상태:
call "%~dp0monitoring-status.bat"

endlocal