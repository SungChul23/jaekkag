@echo off
chcp 65001 > nul
setlocal

REM ============================================================
REM 재깍 프로젝트 AWS 인프라 전체 삭제
REM
REM 삭제 대상:
REM - EKS와 Worker Node
REM - RDS와 저장 데이터
REM - NAT Gateway
REM - VPC 및 Subnet
REM - ECR 이미지
REM - Kinesis Stream
REM - ALB 관련 프로젝트 리소스
REM - 프로젝트 IAM Role 및 Policy
REM
REM 공유 GitHub OIDC Provider는 Terraform Data Source이므로 삭제하지 않는다.
REM ============================================================

cd /d "%~dp0.."

echo.
echo ============================================================
echo [주의] 프로젝트 전체 인프라 삭제
echo ============================================================
echo.
echo 다음 리소스와 데이터가 삭제됩니다.
echo.
echo - ecommerce-dev-eks
echo - EC2 Worker Node 2대
echo - ecommerce-dev-rds 및 저장 데이터
echo - 프로젝트 NAT Gateway
echo - 프로젝트 ALB
echo - ecommerce-order-events Kinesis Stream
echo - 프로젝트 ECR Repository 및 이미지
echo - 프로젝트 VPC와 Subnet
echo.
echo 다른 교육생의 EKS, NAT Gateway, VPC는 삭제하지 않습니다.
echo.
echo 계속하려면 아래 문장을 정확하게 입력하세요.
echo.
echo DESTROY ecommerce-dev
echo.

set /p CONFIRM=입력: 

if /I not "%CONFIRM%"=="DESTROY ecommerce-dev" (
    echo.
    echo Terraform Destroy를 취소했습니다.
    pause
    exit /b 0
)

echo.
echo ============================================================
echo [1/7] AWS 계정 확인
echo ============================================================

aws sts get-caller-identity

if errorlevel 1 (
    echo.
    echo [오류] AWS 인증 상태를 확인하세요.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo [2/7] 현재 EKS Context 확인
echo ============================================================

kubectl config current-context

echo.
echo 현재 연결된 Cluster가 ecommerce-dev-eks인지 확인하세요.
echo 맞으면 CONTINUE를 입력하세요.
echo.

set /p CLUSTER_CONFIRM=입력: 

if /I not "%CLUSTER_CONFIRM%"=="CONTINUE" (
    echo.
    echo Cluster 확인 실패로 삭제를 취소했습니다.
    pause
    exit /b 0
)

echo.
echo ============================================================
echo [3/7] Argo CD 자동 동기화 대상 삭제
echo ============================================================

kubectl delete application ecommerce-monitoring ^
    -n argocd ^
    --ignore-not-found=true ^
    --wait=false

kubectl delete application ecommerce-platform ^
    -n argocd ^
    --ignore-not-found=true ^
    --wait=false

echo.
echo ============================================================
echo [4/7] Ingress 삭제 및 ALB 정리 요청
echo ============================================================

kubectl delete ingress ecommerce-ingress ^
    -n ecommerce ^
    --ignore-not-found=true

echo.
echo Ingress 삭제를 기다립니다.

kubectl wait ^
    --for=delete ^
    ingress/ecommerce-ingress ^
    -n ecommerce ^
    --timeout=300s > nul 2>&1

echo.
echo AWS Load Balancer Controller의 ALB 정리 시간을 기다립니다.
timeout /t 30 /nobreak > nul

echo.
echo 남아 있는 프로젝트 ALB를 확인합니다.

aws elbv2 describe-load-balancers ^
    --region us-east-1 ^
    --query "LoadBalancers[?contains(LoadBalancerName, 'ecommerc')].{Name:LoadBalancerName,State:State.Code}" ^
    --output table

echo.
echo ============================================================
echo [5/7] Terraform 초기화
echo ============================================================

pushd terraform

terraform init -input=false

if errorlevel 1 (
    echo.
    echo [오류] terraform init 실패
    popd
    pause
    exit /b 1
)

echo.
echo ============================================================
echo [6/7] Terraform 관리 리소스 확인
echo ============================================================

terraform state list

echo.
echo ============================================================
echo [7/7] Terraform 전체 삭제
echo ============================================================
echo.
echo DB 비밀번호 입력 요청이 나오면 현재 RDS 비밀번호를 입력하세요.
echo.

terraform destroy -auto-approve

if errorlevel 1 (
    echo.
    echo [오류] Terraform Destroy가 완전히 끝나지 않았습니다.
    echo 위 오류를 확인하고 다시 실행해야 합니다.
    popd
    pause
    exit /b 1
)

popd

echo.
echo ============================================================
echo Terraform Destroy 완료
echo ============================================================
echo.
echo 비용 발생 리소스가 남았는지 확인합니다.
echo.

aws eks list-clusters ^
    --region us-east-1 ^
    --query "clusters[?contains(@, 'ecommerce')]" ^
    --output table

aws rds describe-db-instances ^
    --region us-east-1 ^
    --query "DBInstances[?contains(DBInstanceIdentifier, 'ecommerce')].DBInstanceIdentifier" ^
    --output table

aws elbv2 describe-load-balancers ^
    --region us-east-1 ^
    --query "LoadBalancers[?contains(LoadBalancerName, 'ecommerc')].LoadBalancerName" ^
    --output table

aws ec2 describe-nat-gateways ^
    --region us-east-1 ^
    --filter "Name=vpc-id,Values=vpc-076971bfa20249595" ^
    --query "NatGateways[?State!='deleted'].{ID:NatGatewayId,State:State}" ^
    --output table

echo.
echo 목록이 비어 있으면 주요 프로젝트 리소스 삭제가 완료된 것입니다.
echo GitHub Actions 공용 OIDC Provider는 삭제하지 않았습니다.
echo.

pause
endlocal