@echo off
chcp 65001 > nul
setlocal EnableDelayedExpansion

REM ============================================================
REM Grafana, Prometheus, Argo CD Port-forward 일괄 상태 확인
REM ============================================================

cd /d "%~dp0.."


echo.
echo ============================================================
echo Port-forward 전체 상태
echo ============================================================

call :CHECK_PORT 3000 Grafana "http://localhost:3000"
call :CHECK_PORT 9090 Prometheus "http://localhost:9090"
call :CHECK_PORT 8080 "Argo CD" "https://localhost:8080"


echo.
echo ============================================================
echo Kubernetes 서비스 상태
echo ============================================================

echo.
echo ---------- Argo CD ----------
kubectl get applications -n argocd

echo.
echo ---------- Monitoring ----------
kubectl get pods -n monitoring


echo.
pause
endlocal
exit /b 0


:CHECK_PORT
set "CHECK_PID="
set "CHECK_PROCESS="

for /f "delims=" %%P in ('powershell -NoProfile -Command "$c = Get-NetTCPConnection -LocalPort %1 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1; if ($null -ne $c) { $c.OwningProcess }"') do (
    set "CHECK_PID=%%P"
)

if not defined CHECK_PID (
    echo [중지됨] %~2
    echo           Port: %1
    echo           주소: %~3
    echo.
    exit /b
)

for /f "delims=" %%N in ('powershell -NoProfile -Command "(Get-Process -Id !CHECK_PID! -ErrorAction SilentlyContinue).ProcessName"') do (
    set "CHECK_PROCESS=%%N"
)

echo [실행 중] %~2
echo           주소   : %~3
echo           Port   : %1
echo           PID    : !CHECK_PID!
echo           Process: !CHECK_PROCESS!
echo.

exit /b