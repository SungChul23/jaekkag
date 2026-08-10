@echo off
chcp 65001 > nul
setlocal

REM ============================================================
REM 재깍 프로젝트 전체 상태 확인 스크립트
REM AWS 및 Kubernetes 리소스를 조회만 하며 변경하거나 삭제하지 않는다.
REM ============================================================

REM scripts 폴더의 상위 경로인 프로젝트 최상위 폴더로 이동
cd /d "%~dp0.."

echo.
echo ============================================================
echo [1/10] 현재 AWS 접속 계정
echo ============================================================
aws sts get-caller-identity

if errorlevel 1 (
    echo.
    echo [오류] AWS 인증 정보를 확인하세요.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo [2/10] Terraform이 관리하는 AWS 리소스
echo ============================================================
terraform -chdir=terraform state list

echo.
echo ============================================================
echo [3/10] Terraform 출력값
echo ============================================================
terraform -chdir=terraform output

echo.
echo ============================================================
echo [4/10] EKS Cluster 목록
echo ============================================================
aws eks list-clusters ^
    --region us-east-1 ^
    --output table

echo.
echo ============================================================
echo [5/10] 실행 중인 EC2 Worker Node
echo ============================================================
aws ec2 describe-instances ^
    --region us-east-1 ^
    --filters "Name=instance-state-name,Values=running" ^
    --query "Reservations[].Instances[].{Name:Tags[?Key=='Name']|[0].Value,InstanceId:InstanceId,Type:InstanceType,PrivateIP:PrivateIpAddress}" ^
    --output table

echo.
echo ============================================================
echo [6/10] 비용 발생 가능성이 큰 AWS 리소스
echo ============================================================

echo.
echo ---------- NAT Gateway ----------
aws ec2 describe-nat-gateways ^
    --region us-east-1 ^
    --filter "Name=state,Values=available" ^
    --query "NatGateways[].{ID:NatGatewayId,VPC:VpcId,State:State,Created:CreateTime}" ^
    --output table

echo.
echo ---------- RDS ----------
aws rds describe-db-instances ^
    --region us-east-1 ^
    --query "DBInstances[].{Name:DBInstanceIdentifier,Class:DBInstanceClass,Engine:Engine,Status:DBInstanceStatus,MultiAZ:MultiAZ}" ^
    --output table

echo.
echo ---------- ALB ----------
aws elbv2 describe-load-balancers ^
    --region us-east-1 ^
    --query "LoadBalancers[].{Name:LoadBalancerName,Type:Type,State:State.Code,DNS:DNSName}" ^
    --output table

echo.
echo ---------- Kinesis ----------
aws kinesis list-streams ^
    --region us-east-1 ^
    --output table

echo.
echo ---------- ECR ----------
aws ecr describe-repositories ^
    --region us-east-1 ^
    --query "repositories[].{Name:repositoryName,URI:repositoryUri,Created:createdAt}" ^
    --output table

echo.
echo ============================================================
echo [7/10] EKS Node 상태
echo ============================================================
kubectl get nodes -o wide

echo.
echo ============================================================
echo [8/10] 애플리케이션 상태
echo ============================================================
kubectl get pods,service,ingress,hpa -n ecommerce -o wide

echo.
echo ============================================================
echo [9/10] Argo CD 및 Monitoring 상태
echo ============================================================

echo.
echo ---------- Argo CD ----------
kubectl get applications -n argocd

echo.
echo ---------- Monitoring Pod ----------
kubectl get pods -n monitoring

echo.
echo ---------- ServiceMonitor ----------
kubectl get servicemonitor -n monitoring

echo.
echo ---------- PrometheusRule ----------
kubectl get prometheusrule ecommerce-alert-rules -n monitoring

echo.
echo ============================================================
echo [10/10] Helm 설치 목록
echo ============================================================
helm list -A

echo.
echo ============================================================
echo 전체 상태 확인 완료
echo ============================================================
echo.
echo 확인 기준:
echo   1. EKS Node가 모두 Ready인지 확인
echo   2. ecommerce Pod가 모두 Running인지 확인
echo   3. Argo CD가 Synced / Healthy인지 확인
echo   4. Ingress에 ALB ADDRESS가 있는지 확인
echo   5. HPA TARGETS가 unknown이 아닌지 확인
echo   6. 예상보다 많은 NAT, RDS, ALB, EKS가 있는지 확인
echo.
echo 주의:
echo   이 스크립트는 조회만 하며 AWS 리소스를 변경하지 않습니다.
echo.

pause
endlocal