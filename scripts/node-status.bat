@echo off
chcp 65001 > nul
setlocal

title EKS Node and Scaling Status

set "NAMESPACE=ecommerce"
set "DEPLOYMENT=order-api"
set "CLUSTER_NAME=ecommerce-dev-eks"
set "AWS_REGION=us-east-1"

echo ============================================================
echo EKS 노드 및 확장 상태 확인
echo ============================================================
echo.

where kubectl >nul 2>&1
if errorlevel 1 (
    echo [오류] kubectl을 찾을 수 없습니다.
    pause
    exit /b 1
)

echo [1/9] 현재 Kubernetes Context
kubectl config current-context
if errorlevel 1 goto :connection_error

echo.
echo [2/9] Worker Node 상태
kubectl get nodes -o wide
if errorlevel 1 goto :connection_error

echo.
echo [3/9] 노드 CPU 및 메모리 사용량
kubectl top nodes
if errorlevel 1 (
    echo [경고] Metrics Server가 없거나 메트릭 수집 준비가 안 됐습니다.
)

echo.
echo [4/9] Order API Deployment 및 Pod 개수
kubectl get deployment %DEPLOYMENT% -n %NAMESPACE%
kubectl get pods -n %NAMESPACE% -l app=order-api -o wide

echo.
echo [5/9] Order API Pod의 노드별 배치 상태
echo ------------------------------------------------------------
echo 아래 NODE 열에서 특정 노드에 Pod가 몰려 있는지 확인하세요.
kubectl get pods -n %NAMESPACE% -l app=order-api ^
  -o custom-columns="POD:.metadata.name,READY:.status.containerStatuses[0].ready,STATUS:.status.phase,NODE:.spec.nodeName,POD_IP:.status.podIP"

echo.
echo [6/9] Order API HPA 확장 상태
kubectl get hpa order-api-hpa -n %NAMESPACE%
if errorlevel 1 (
    echo [경고] order-api-hpa를 찾을 수 없습니다.
) else (
    echo.
    echo TARGETS가 설정값을 초과하면 Pod가 증가합니다.
    echo REPLICAS가 MAXPODS에 도달했는데 부하가 계속 높으면 Node 용량을 확인하세요.
)

echo.
echo [7/9] Pending Pod 및 스케줄링 실패 확인
kubectl get pods -A --field-selector=status.phase=Pending -o wide
echo.
echo 최근 스케줄링 관련 이벤트:
kubectl get events -A ^
  --field-selector reason=FailedScheduling ^
  --sort-by=.metadata.creationTimestamp

echo.
echo [8/9] 노드별 Pod 사용량 및 할당 가능 자원
kubectl describe nodes | findstr /C:"Name:" /C:"cpu" /C:"memory" /C:"Non-terminated Pods:" /C:"Allocated resources:"

echo.
echo [9/9] Karpenter 설치 및 동작 상태
echo ------------------------------------------------------------

kubectl get namespace karpenter >nul 2>&1
if errorlevel 1 (
    echo [미설치] karpenter Namespace가 없습니다.
    echo 현재는 EKS Managed Node Group만 사용하는 상태일 가능성이 높습니다.
    goto :summary
)

echo Karpenter Namespace:
kubectl get namespace karpenter

echo.
echo Karpenter Controller:
kubectl get deployment,pods -n karpenter -o wide

echo.
kubectl api-resources | findstr /I "nodepool" >nul 2>&1
if errorlevel 1 (
    echo [경고] Karpenter NodePool CRD를 찾을 수 없습니다.
) else (
    echo Karpenter NodePool:
    kubectl get nodepool
)

echo.
kubectl api-resources | findstr /I "ec2nodeclass" >nul 2>&1
if errorlevel 1 (
    echo [경고] EC2NodeClass CRD를 찾을 수 없습니다.
) else (
    echo Karpenter EC2NodeClass:
    kubectl get ec2nodeclass
)

echo.
kubectl api-resources | findstr /I "nodeclaim" >nul 2>&1
if errorlevel 1 (
    echo [경고] NodeClaim CRD를 찾을 수 없습니다.
) else (
    echo Karpenter가 생성한 NodeClaim:
    kubectl get nodeclaim
)

:summary
echo.
echo ============================================================
echo 확인 기준
echo ============================================================
echo 1. 모든 Node의 STATUS가 Ready인지 확인
echo 2. Order API Pod가 여러 Node에 분산되는지 확인
echo 3. HPA TARGETS 상승 시 REPLICAS가 증가하는지 확인
echo 4. Pending Pod와 FailedScheduling 이벤트가 없는지 확인
echo 5. Pod를 배치할 자원이 부족하면 Node 확장 검토
echo 6. Karpenter 사용 시 Controller, NodePool, EC2NodeClass 확인
echo ============================================================
echo.
echo 주의:
echo - Pod가 한 노드에 몰렸다는 이유만으로 바로 Node를 늘리지는 않습니다.
echo - 여유 노드가 있는데도 몰리면 topologySpreadConstraints 설정을 확인합니다.
echo - Pending Pod가 자원 부족으로 발생하면 Managed Node Group 또는
echo   Karpenter를 통한 Node 확장을 검토합니다.
echo.
pause
exit /b 0

:connection_error
echo.
echo [오류] EKS 연결 상태를 확인하세요.
echo aws eks update-kubeconfig --region %AWS_REGION% --name %CLUSTER_NAME%
pause
exit /b 1