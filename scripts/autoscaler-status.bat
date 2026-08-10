@echo off
chcp 65001 >nul
setlocal

set CLUSTER_NAME=ecommerce-dev-eks
set NODEGROUP_NAME=ecommerce-dev-node-group
set AWS_REGION=us-east-1
set NAMESPACE=kube-system

echo ============================================================
echo Cluster Autoscaler 상태 확인
echo ============================================================
echo.

echo [1/7] Helm Release
helm list -n %NAMESPACE% | findstr /I "cluster-autoscaler"
echo.

echo [2/7] Cluster Autoscaler Deployment
kubectl get deployment -n %NAMESPACE% -l app.kubernetes.io/instance=cluster-autoscaler
echo.

echo [3/7] Cluster Autoscaler Pod
kubectl get pods -n %NAMESPACE% -l app.kubernetes.io/instance=cluster-autoscaler -o wide
echo.

echo [4/7] EKS Worker Node
kubectl get nodes -o wide
echo.

echo [5/7] Node Group Scaling 설정
aws eks describe-nodegroup ^
  --cluster-name %CLUSTER_NAME% ^
  --nodegroup-name %NODEGROUP_NAME% ^
  --region %AWS_REGION% ^
  --query "nodegroup.scalingConfig" ^
  --output table
echo.

echo [6/7] Pending Pod
kubectl get pods -A --field-selector=status.phase=Pending
echo.

echo [7/7] Cluster Autoscaler 최근 로그
kubectl logs ^
  -n %NAMESPACE% ^
  -l app.kubernetes.io/instance=cluster-autoscaler ^
  --tail=30 ^
  --prefix
echo.

echo ============================================================
echo 확인 기준
echo - Autoscaler Deployment: READY 1/1
echo - Autoscaler Pod: Running
echo - Node Group: min 2 / desired 3~4 / max 4
echo - Pending Pod 발생 시 Node 자동 증설
echo ============================================================
echo.

pause
endlocal