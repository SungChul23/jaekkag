@echo off
chcp 65001 > nul
setlocal EnableDelayedExpansion

REM ============================================================
REM Grafana, Prometheus, Argo CD Port-forward 일괄 시작
REM EKS 내부 리소스는 변경하지 않는다.
REM ============================================================

cd /d "%~dp0.."

set "START_FAILED=0"


echo.
echo ============================================================
echo [1/5] Kubernetes Context 확인
echo ============================================================

for /f "delims=" %%A in ('kubectl config current-context 2^>nul') do (
    set "CURRENT_CONTEXT=%%A"
)

if not defined CURRENT_CONTEXT (
    echo [오류] Kubernetes Context를 확인할 수 없습니다.
    pause
    exit /b 1
)

echo !CURRENT_CONTEXT!

echo !CURRENT_CONTEXT! | findstr /C:"ecommerce-dev-eks" > nul

if errorlevel 1 (
    echo [오류] 현재 Context가 ecommerce-dev-eks가 아닙니다.
    pause
    exit /b 1
)


echo.
echo ============================================================
echo [2/5] Kubernetes Service 확인
echo ============================================================

kubectl get service kube-prometheus-stack-grafana ^
    -n monitoring > nul 2>&1

if errorlevel 1 (
    echo [오류] Grafana Service를 찾을 수 없습니다.
    set "START_FAILED=1"
) else (
    echo [정상] Grafana Service
)

kubectl get service kube-prometheus-stack-prometheus ^
    -n monitoring > nul 2>&1

if errorlevel 1 (
    echo [오류] Prometheus Service를 찾을 수 없습니다.
    set "START_FAILED=1"
) else (
    echo [정상] Prometheus Service
)

kubectl get service argocd-server ^
    -n argocd > nul 2>&1

if errorlevel 1 (
    echo [오류] Argo CD Service를 찾을 수 없습니다.
    set "START_FAILED=1"
) else (
    echo [정상] Argo CD Service
)

if "!START_FAILED!"=="1" (
    echo.
    echo 필요한 Service가 없어 Port-forward를 시작할 수 없습니다.
    pause
    exit /b 1
)


echo.
echo ============================================================
echo [3/5] Grafana Port-forward 시작
echo ============================================================

powershell -NoProfile -Command "if (Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"

if errorlevel 1 (
    start "Jaekkag Grafana Port Forward" /min cmd /c "kubectl port-forward -n monitoring service/kube-prometheus-stack-grafana 3000:80"
    echo Grafana Port-forward 시작 요청 완료
) else (
    echo [안내] Port 3000이 이미 사용 중이므로 시작하지 않습니다.
)


echo.
echo ============================================================
echo [4/5] Prometheus Port-forward 시작
echo ============================================================

powershell -NoProfile -Command "if (Get-NetTCPConnection -LocalPort 9090 -State Listen -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"

if errorlevel 1 (
    start "Jaekkag Prometheus Port Forward" /min cmd /c "kubectl port-forward -n monitoring service/kube-prometheus-stack-prometheus 9090:9090"
    echo Prometheus Port-forward 시작 요청 완료
) else (
    echo [안내] Port 9090이 이미 사용 중이므로 시작하지 않습니다.
)


echo.
echo ============================================================
echo [5/5] Argo CD Port-forward 시작
echo ============================================================

powershell -NoProfile -Command "if (Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"

if errorlevel 1 (
    start "Jaekkag Argo CD Port Forward" /min cmd /c "kubectl port-forward -n argocd service/argocd-server 8080:443"
    echo Argo CD Port-forward 시작 요청 완료
) else (
    echo [안내] Port 8080이 이미 사용 중이므로 시작하지 않습니다.
)


echo.
echo Port-forward 시작을 5초 동안 기다립니다.
timeout /t 5 /nobreak > nul


echo.
echo ============================================================
echo Port-forward 시작 결과
echo ============================================================

call :CHECK_PORT 3000 Grafana
call :CHECK_PORT 9090 Prometheus
call :CHECK_PORT 8080 "Argo CD"

echo.
echo 접속 주소:
echo   Grafana    : http://localhost:3000
echo   Prometheus : http://localhost:9090
echo   Argo CD    : https://localhost:8080
echo.
echo Argo CD 접속 시 인증서 경고가 나오면
echo 고급 메뉴에서 접속을 계속하세요.
echo.

start "" "http://localhost:3000"
start "" "http://localhost:9090"
start "" "https://localhost:8080"

pause
endlocal
exit /b 0


:CHECK_PORT
powershell -NoProfile -Command "if (Get-NetTCPConnection -LocalPort %1 -State Listen -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"

if errorlevel 1 (
    echo [실패] %~2 - Port %1
) else (
    echo [정상] %~2 - Port %1
)

exit /b