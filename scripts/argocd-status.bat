@echo off
chcp 65001 > nul
setlocal EnableDelayedExpansion

cd /d "%~dp0.."

echo.
echo ============================================================
echo [1/3] Argo CD Pod 상태
echo ============================================================
kubectl get pods -n argocd

echo.
echo ============================================================
echo [2/3] Argo CD Application 상태
echo ============================================================
kubectl get applications -n argocd

echo.
echo ============================================================
echo [3/3] Argo CD Port-forward 상태
echo ============================================================

set "ARGO_PID="
set "ARGO_PROCESS="

for /f "delims=" %%P in ('powershell -NoProfile -Command "$c = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1; if ($null -ne $c) { $c.OwningProcess }"') do (
    set "ARGO_PID=%%P"
)

if not defined ARGO_PID (
    echo [중지됨] 로컬 Port 8080이 열려 있지 않습니다.
    echo 시작 명령: .\scripts\argocd-start.bat
    goto END
)

for /f "delims=" %%N in ('powershell -NoProfile -Command "(Get-Process -Id !ARGO_PID! -ErrorAction SilentlyContinue).ProcessName"') do (
    set "ARGO_PROCESS=%%N"
)

echo [실행 중] Argo CD Port-forward
echo 접속 주소: https://localhost:8080
echo PID       : !ARGO_PID!
echo Process   : !ARGO_PROCESS!

:END
echo.
pause
endlocal