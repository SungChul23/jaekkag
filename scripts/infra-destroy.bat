@echo off
chcp 65001 > nul
setlocal EnableDelayedExpansion


REM ============================================================
REM 재깍 프로젝트 AWS 인프라 전체 삭제
REM
REM 삭제 대상:
REM - EKS와 모든 Worker Node
REM - Cluster Autoscaler
REM - RDS와 저장 데이터
REM - NAT Gateway
REM - VPC 및 Subnet
REM - ECR Repository와 이미지
REM - Kinesis Stream
REM - ALB 관련 프로젝트 리소스
REM - 프로젝트 IAM Role 및 Policy
REM
REM 공유 GitHub Actions OIDC Provider는 Terraform Data Source이므로
REM 이 스크립트에서 삭제하지 않는다.
REM ============================================================


REM scripts 폴더의 상위인 프로젝트 루트로 이동
cd /d "%~dp0.."


set "AWS_REGION=us-east-1"
set "AWS_ACCOUNT_ID=827913617635"
set "EKS_CLUSTER_NAME=ecommerce-dev-eks"
set "PROJECT_VPC_ID="
set "CURRENT_ACCOUNT_ID="
set "CURRENT_CONTEXT="


echo.
echo ============================================================
echo [주의] 재깍 프로젝트 전체 인프라 삭제
echo ============================================================
echo.
echo 다음 리소스와 데이터가 삭제됩니다.
echo.
echo - ecommerce-dev-eks
echo - EKS Managed Node Group 및 모든 Worker Node
echo - Cluster Autoscaler
echo - ecommerce-dev-rds 및 저장 데이터
echo - 프로젝트 NAT Gateway
echo - 프로젝트 ALB
echo - ecommerce-order-events Kinesis Stream
echo - 프로젝트 ECR Repository 및 이미지
echo - 프로젝트 VPC와 Subnet
echo - 프로젝트 IAM Role 및 Policy
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
echo [1/8] AWS 계정 검증
echo ============================================================


aws sts get-caller-identity


if errorlevel 1 (
    echo.
    echo [오류] AWS 인증 상태를 확인하세요.
    pause
    exit /b 1
)


for /f "delims=" %%A in ('aws sts get-caller-identity --query Account --output text 2^>nul') do (
    set "CURRENT_ACCOUNT_ID=%%A"
)


if not "!CURRENT_ACCOUNT_ID!"=="%AWS_ACCOUNT_ID%" (
    echo.
    echo [오류] 현재 AWS 계정이 프로젝트 계정과 다릅니다.
    echo.
    echo 프로젝트 계정: %AWS_ACCOUNT_ID%
    echo 현재 접속 계정: !CURRENT_ACCOUNT_ID!
    echo.
    echo 다른 AWS 계정의 리소스 삭제 방지를 위해 중단합니다.
    pause
    exit /b 1
)


echo.
echo [정상] 프로젝트 AWS 계정 확인 완료


echo.
echo ============================================================
echo [2/8] 프로젝트 VPC 확인
echo ============================================================


for /f "delims=" %%V in ('terraform -chdir=terraform output -raw vpc_id 2^>nul') do (
    set "PROJECT_VPC_ID=%%V"
)


if not defined PROJECT_VPC_ID (
    echo.
    echo [오류] Terraform Output에서 프로젝트 VPC ID를 확인하지 못했습니다.
    echo Terraform State와 Output을 확인하세요.
    pause
    exit /b 1
)


echo 프로젝트 VPC: !PROJECT_VPC_ID!


echo.
echo ============================================================
echo [3/8] 현재 EKS Context 검증
echo ============================================================


for /f "delims=" %%C in ('kubectl config current-context 2^>nul') do (
    set "CURRENT_CONTEXT=%%C"
)


if not defined CURRENT_CONTEXT (
    echo.
    echo [오류] 현재 Kubernetes Context를 확인하지 못했습니다.
    echo 아래 명령으로 EKS Context를 다시 설정하세요.
    echo.
    echo aws eks update-kubeconfig --region %AWS_REGION% --name %EKS_CLUSTER_NAME%
    echo.
    pause
    exit /b 1
)


echo 현재 Context: !CURRENT_CONTEXT!


echo !CURRENT_CONTEXT! | findstr /C:"%EKS_CLUSTER_NAME%" > nul


if errorlevel 1 (
    echo.
    echo [오류] 현재 Kubernetes Context가 %EKS_CLUSTER_NAME%가 아닙니다.
    echo 다른 Cluster 삭제 방지를 위해 중단합니다.
    echo.
    echo 아래 명령으로 Context를 다시 설정하세요.
    echo aws eks update-kubeconfig --region %AWS_REGION% --name %EKS_CLUSTER_NAME%
    echo.
    pause
    exit /b 1
)


echo.
echo [정상] %EKS_CLUSTER_NAME% Context 확인 완료


echo.
echo ============================================================
echo [4/8] Argo CD 자동 동기화 중지
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
echo Argo CD Application 삭제를 기다립니다.
timeout /t 10 /nobreak > nul


kubectl get application ecommerce-monitoring ^
    -n argocd > nul 2>&1


if not errorlevel 1 (
    kubectl wait ^
        --for=delete ^
        application/ecommerce-monitoring ^
        -n argocd ^
        --timeout=120s

    if errorlevel 1 (
        echo.
        echo [오류] ecommerce-monitoring Application 삭제가 완료되지 않았습니다.
        echo Argo CD 상태를 확인한 후 다시 실행하세요.
        pause
        exit /b 1
    )
)


kubectl get application ecommerce-platform ^
    -n argocd > nul 2>&1


if not errorlevel 1 (
    kubectl wait ^
        --for=delete ^
        application/ecommerce-platform ^
        -n argocd ^
        --timeout=120s

    if errorlevel 1 (
        echo.
        echo [오류] ecommerce-platform Application 삭제가 완료되지 않았습니다.
        echo Argo CD 상태를 확인한 후 다시 실행하세요.
        pause
        exit /b 1
    )
)


echo.
echo [정상] Argo CD 자동 동기화 대상 삭제 완료


echo.
echo ============================================================
echo [5/8] Ingress 삭제 및 ALB 정리
echo ============================================================


kubectl delete ingress ecommerce-ingress ^
    -n ecommerce ^
    --ignore-not-found=true ^
    --wait=false


kubectl get ingress ecommerce-ingress ^
    -n ecommerce > nul 2>&1


if not errorlevel 1 (
    echo.
    echo Kubernetes Ingress 삭제를 기다립니다.

    kubectl wait ^
        --for=delete ^
        ingress/ecommerce-ingress ^
        -n ecommerce ^
        --timeout=300s

    if errorlevel 1 (
        echo.
        echo [오류] Kubernetes Ingress 삭제가 완료되지 않았습니다.
        echo AWS Load Balancer Controller 상태를 확인하세요.
        pause
        exit /b 1
    )
)


echo.
echo AWS Load Balancer Controller가 ALB를 삭제할 때까지 기다립니다.
echo 최대 5분 동안 10초 간격으로 확인합니다.


set /a ALB_CHECK_COUNT=0


:WAIT_FOR_ALB_DELETE


set "ALB_COUNT="


for /f "delims=" %%L in ('aws elbv2 describe-load-balancers --region %AWS_REGION% --query "length(LoadBalancers[?VpcId=='!PROJECT_VPC_ID!'])" --output text 2^>nul') do (
    set "ALB_COUNT=%%L"
)


if not defined ALB_COUNT (
    echo.
    echo [오류] AWS ALB 상태를 조회하지 못했습니다.
    pause
    exit /b 1
)


if "!ALB_COUNT!"=="0" goto ALB_DELETE_COMPLETE


set /a ALB_CHECK_COUNT+=1


echo [!ALB_CHECK_COUNT!/30] 프로젝트 VPC에 ALB !ALB_COUNT!개가 남아 있습니다.


if !ALB_CHECK_COUNT! GEQ 30 goto ALB_DELETE_TIMEOUT


timeout /t 10 /nobreak > nul
goto WAIT_FOR_ALB_DELETE


:ALB_DELETE_TIMEOUT


echo.
echo [오류] 5분 안에 프로젝트 ALB가 삭제되지 않았습니다.
echo.
echo EKS와 AWS Load Balancer Controller를 먼저 삭제하면
echo ALB와 Security Group이 고아 리소스로 남을 수 있습니다.
echo.
echo 아래 명령으로 Controller 상태와 로그를 확인하세요.
echo.
echo kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
echo kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=100
echo.
echo Terraform Destroy를 중단합니다.
pause
exit /b 1


:ALB_DELETE_COMPLETE


echo.
echo [정상] 프로젝트 VPC의 ALB 삭제 완료


echo.
echo ============================================================
echo [6/8] Terraform 초기화
echo ============================================================


pushd "%~dp0..\terraform"


if errorlevel 1 (
    echo.
    echo [오류] terraform 폴더를 찾을 수 없습니다.
    pause
    exit /b 1
)


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
echo [7/8] Terraform 관리 리소스 확인
echo ============================================================


terraform state list


if errorlevel 1 (
    echo.
    echo [오류] Terraform State를 확인하지 못했습니다.
    popd
    pause
    exit /b 1
)


echo.
echo ============================================================
echo [8/8] Terraform 전체 삭제
echo ============================================================
echo.
echo DB 비밀번호 입력 요청이 나오면 현재 RDS 비밀번호를 입력하세요.
echo.


terraform destroy -auto-approve


if errorlevel 1 (
    echo.
    echo [오류] Terraform Destroy가 완전히 끝나지 않았습니다.
    echo 위 오류를 확인한 후 스크립트를 다시 실행하세요.
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
echo 비용 발생 가능성이 있는 프로젝트 리소스를 최종 확인합니다.
echo 목록이 비어 있어야 정상입니다.
echo.


echo.
echo ---------- EKS ----------
aws eks list-clusters ^
    --region %AWS_REGION% ^
    --query "clusters[?@=='%EKS_CLUSTER_NAME%']" ^
    --output table


echo.
echo ---------- EC2 Worker Node ----------
aws ec2 describe-instances ^
    --region %AWS_REGION% ^
    --filters ^
        "Name=tag:eks:cluster-name,Values=%EKS_CLUSTER_NAME%" ^
        "Name=instance-state-name,Values=pending,running,stopping,stopped" ^
    --query "Reservations[].Instances[].{ID:InstanceId,State:State.Name,Type:InstanceType}" ^
    --output table


echo.
echo ---------- RDS ----------
aws rds describe-db-instances ^
    --region %AWS_REGION% ^
    --query "DBInstances[?DBInstanceIdentifier=='ecommerce-dev-rds'].{Name:DBInstanceIdentifier,Status:DBInstanceStatus}" ^
    --output table


echo.
echo ---------- ALB ----------
aws elbv2 describe-load-balancers ^
    --region %AWS_REGION% ^
    --query "LoadBalancers[?VpcId=='!PROJECT_VPC_ID!'].{Name:LoadBalancerName,State:State.Code}" ^
    --output table


echo.
echo ---------- NAT Gateway ----------
aws ec2 describe-nat-gateways ^
    --region %AWS_REGION% ^
    --filter "Name=vpc-id,Values=!PROJECT_VPC_ID!" ^
    --query "NatGateways[?State!='deleted'].{ID:NatGatewayId,State:State}" ^
    --output table


echo.
echo ---------- Kinesis ----------
aws kinesis list-streams ^
    --region %AWS_REGION% ^
    --query "StreamNames[?@=='ecommerce-order-events']" ^
    --output table


echo.
echo ---------- ECR ----------
aws ecr describe-repositories ^
    --region %AWS_REGION% ^
    --query "repositories[?repositoryName=='order-api' || repositoryName=='outbox-publisher' || repositoryName=='inventory-worker'].repositoryName" ^
    --output table


echo.
echo ---------- 프로젝트 VPC ----------
aws ec2 describe-vpcs ^
    --region %AWS_REGION% ^
    --vpc-ids !PROJECT_VPC_ID! ^
    --query "Vpcs[].{VPC:VpcId,State:State}" ^
    --output table 2> nul


echo.
echo ============================================================
echo 최종 확인 완료
echo ============================================================
echo.
echo 위 프로젝트 리소스 목록이 모두 비어 있으면
echo 주요 AWS 인프라 삭제가 완료된 것입니다.
echo.
echo NAT Gateway는 잠시 deleting 상태로 표시될 수 있습니다.
echo 완전히 deleted 상태가 되면 목록에서 사라집니다.
echo.
echo 공유 GitHub Actions OIDC Provider는 삭제하지 않았습니다.
echo 다른 교육생의 AWS 리소스도 삭제하지 않았습니다.
echo.


pause
endlocal