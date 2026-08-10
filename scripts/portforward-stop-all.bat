@echo off
chcp 65001 > nul
setlocal EnableDelayedExpansion

REM ============================================================
REM Grafana, Prometheus, Argo CD Port-forward 일괄 종료
REM EKS 내부 Pod와 Service는 종료하지 않는다.
REM ============================================================

echo.
echo ============================================================
echo Port-forward 전체 종료
echo ============================================================

call :STOP_PORT 3000 Grafana
call :STOP_PORT 9090 Prometheus
call :STOP_PORT 8080 "Argo CD"


echo.
echo ============================================================
echo Port-forward 전체 종료 작업 완료
echo ============================================================
echo.
echo EKS 내부 Grafana, Prometheus, Argo CD는 계속 실행 중입니다.
echo.

pause
endlocal
exit /b 0


:STOP_PORT
set "STOP_PID="
set "STOP_PROCESS="

for /f "delims=" %%P in ('powershell -NoProfile -Command "$c = Get-NetTCPConnection -LocalPort %1 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1; if ($null -ne $c) { $c.OwningProcess }"') do (
    set "STOP_PID=%%P"
)

if not defined STOP_PID (
    echo [중지됨] %~2 - Port %1
    exit /b
)

for /f "delims=" %%N in ('powershell -NoProfile -Command "(Get-Process -Id !STOP_PID! -ErrorAction SilentlyContinue).ProcessName"') do (
    set "STOP_PROCESS=%%N"
)

if /I not "!STOP_PROCESS!"=="kubectl" (
    echo [건너뜀] %~2 - Port %1
    echo           kubectl이 아닌 !STOP_PROCESS! 프로세스가 사용 중입니다.
    exit /b
)

taskkill /PID !STOP_PID! /T /F > nul 2>&1

if errorlevel 1 (
    echo [실패] %~2 - PID !STOP_PID!
) else (
    echo [정상 종료] %~2 - PID !STOP_PID!
)

exit /b