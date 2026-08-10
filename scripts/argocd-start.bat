@echo off
chcp 65001 > nul
setlocal EnableDelayedExpansion

REM ============================================================
REM Argo CD 웹 화면 Port-forward 시작
REM 접속 주소: https://localhost:8080
REM ============================================================

cd /d "%~dp0.."


echo.
echo ============================================================
echo [1/4] Kubernetes Context 확인
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
echo [2/4] Argo CD Server 확인
echo ============================================================

kubectl get service argocd-server -n argocd > nul 2>&1

if errorlevel 1 (
    echo [오류] argocd-server Service를 찾을 수 없습니다.
    pause
    exit /b 1
)

echo [정상] argocd-server Service 확인


echo.
echo ============================================================
echo [3/4] 로컬 Port 8080 확인
echo ============================================================

powershell -NoProfile -Command "if (Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"

if not errorlevel 1 (
    echo [안내] Port 8080이 이미 사용 중입니다.
    echo 접속 주소: https://localhost:8080
    start "" "https://localhost:8080"
    pause
    exit /b 0
)


echo.
echo ============================================================
echo [4/4] Argo CD Port-forward 시작
echo ============================================================

start "Jaekkag Argo CD Port Forward" /min cmd /c "kubectl port-forward -n argocd service/argocd-server 8080:443"

echo Port-forward 시작 대기 중...
timeout /t 3 /nobreak > nul

powershell -NoProfile -Command "if (Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"

if errorlevel 1 (
    echo.
    echo [오류] Port 8080이 열리지 않았습니다.
    echo 최소화된 Port-forward 창의 오류를 확인하세요.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo Argo CD Port-forward 시작 완료
echo ============================================================
echo.
echo 접속 주소: https://localhost:8080
echo 사용자명  : admin
echo.
echo 인증서 경고가 나오면 고급 메뉴에서 접속을 계속하세요.
echo.

start "" "https://localhost:8080"

pause
endlocal