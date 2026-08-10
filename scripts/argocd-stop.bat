@echo off
chcp 65001 > nul
setlocal EnableDelayedExpansion

set "ARGO_PID="
set "ARGO_PROCESS="

echo.
echo ============================================================
echo Argo CD Port-forward 종료
echo ============================================================

for /f "delims=" %%P in ('powershell -NoProfile -Command "$c = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1; if ($null -ne $c) { $c.OwningProcess }"') do (
    set "ARGO_PID=%%P"
)

if not defined ARGO_PID (
    echo [안내] Port 8080에서 실행 중인 프로세스가 없습니다.
    echo Argo CD Port-forward는 이미 중지된 상태입니다.
    pause
    exit /b 0
)

for /f "delims=" %%N in ('powershell -NoProfile -Command "(Get-Process -Id !ARGO_PID! -ErrorAction SilentlyContinue).ProcessName"') do (
    set "ARGO_PROCESS=%%N"
)

echo PID     : !ARGO_PID!
echo Process : !ARGO_PROCESS!

if /I not "!ARGO_PROCESS!"=="kubectl" (
    echo.
    echo [중단] Port 8080을 사용하는 프로세스가 kubectl이 아닙니다.
    echo 다른 프로그램을 보호하기 위해 종료하지 않습니다.
    pause
    exit /b 1
)

taskkill /PID !ARGO_PID! /T /F > nul 2>&1

if errorlevel 1 (
    echo [오류] Port-forward 프로세스 종료에 실패했습니다.
    pause
    exit /b 1
)

echo.
echo [정상] Argo CD Port-forward를 종료했습니다.
echo EKS의 Argo CD와 자동 배포는 계속 동작합니다.
echo.

pause
endlocal