@echo off
chcp 65001 > nul
setlocal

echo.
echo ============================================================
echo Monitoring Port-forward 상태
echo ============================================================

netstat -ano | findstr /R /C:":3000 .*LISTENING" > nul

if errorlevel 1 (
    echo [중지됨] Grafana - http://localhost:3000
) else (
    echo [실행 중] Grafana - http://localhost:3000
)

netstat -ano | findstr /R /C:":9090 .*LISTENING" > nul

if errorlevel 1 (
    echo [중지됨] Prometheus - http://localhost:9090
) else (
    echo [실행 중] Prometheus - http://localhost:9090
)

echo.
pause
endlocal