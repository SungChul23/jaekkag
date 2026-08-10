@echo off
chcp 65001 > nul
setlocal

REM ============================================================
REM Grafana와 Prometheus 포트포워딩 시작
REM 각각 별도의 최소화된 CMD 창에서 실행된다.
REM ============================================================

echo.
echo Kubernetes 연결 상태를 확인합니다.

kubectl cluster-info > nul 2>&1

if errorlevel 1 (
    echo [오류] Kubernetes Cluster에 연결할 수 없습니다.
    echo AWS 인증과 kubectl context를 확인하세요.
    pause
    exit /b 1
)

echo.
echo Monitoring Service를 확인합니다.

kubectl get service kube-prometheus-stack-grafana -n monitoring > nul 2>&1

if errorlevel 1 (
    echo [오류] Grafana Service를 찾을 수 없습니다.
    pause
    exit /b 1
)

kubectl get service kube-prometheus-stack-prometheus -n monitoring > nul 2>&1

if errorlevel 1 (
    echo [오류] Prometheus Service를 찾을 수 없습니다.
    pause
    exit /b 1
)

netstat -ano | findstr /R /C:":3000 .*LISTENING" > nul

if errorlevel 1 (
    echo Grafana 포트포워딩을 시작합니다.
    start "JAEKKAG-GRAFANA" /min kubectl port-forward -n monitoring service/kube-prometheus-stack-grafana 3000:80
) else (
    echo Grafana 3000 포트가 이미 사용 중입니다.
)

netstat -ano | findstr /R /C:":9090 .*LISTENING" > nul

if errorlevel 1 (
    echo Prometheus 포트포워딩을 시작합니다.
    start "JAEKKAG-PROMETHEUS" /min kubectl port-forward -n monitoring service/kube-prometheus-stack-prometheus 9090:9090
) else (
    echo Prometheus 9090 포트가 이미 사용 중입니다.
)

timeout /t 3 /nobreak > nul

echo.
echo ============================================================
echo Monitoring 접속 정보
echo ============================================================
echo Grafana:    http://localhost:3000
echo Prometheus: http://localhost:9090
echo.

pause
endlocal