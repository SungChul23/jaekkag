@echo off
chcp 65001 > nul
setlocal EnableDelayedExpansion


REM ============================================================
REM 재깍 프로젝트 AWS 인프라 전체 삭제
REM
REM 주요 처리 순서:
REM 1. AWS 계정과 EKS Context 검증
REM 2. Terraform에서 프로젝트 VPC ID 조회
REM 3. Argo CD Application 삭제
REM 4. Ingress 및 ALB 삭제 확인
REM 5. Terraform Destroy
REM 6. 실패 시 EKS 잔여 ENI와 Security Group 정리
REM 7. Terraform Destroy 재시도
REM 8. 비용 발생 리소스 최종 확인
REM
REM 공유 GitHub Actions OIDC Provider는 Data Source이므로
REM 이 스크립트에서 삭제하지 않는다.
REM ============================================================


cd /d "%~dp0.."


if errorlevel 1 (
    echo.
    echo [오류] 프로젝트 최상위 폴더로 이동하지 못했습니다.
    pause
    exit /b 1
)


set "AWS_REGION=us-east-1"
set "AWS_ACCOUNT_ID=827913617635"
set "EKS_CLUSTER_NAME=ecommerce-dev-eks"

set "CURRENT_ACCOUNT_ID="
set "CURRENT_CONTEXT="
set "PROJECT_VPC_ID="
set "ALB_COUNT="

set "VPC_OUTPUT_FILE=%TEMP%\jaekkag-vpc-id.txt"
set "ALB_OUTPUT_FILE=%TEMP%\jaekkag-alb-count.txt"
set "STATE_OUTPUT_FILE=%TEMP%\jaekkag-terraform-state.txt"


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
echo 다른 교육생의 리소스는 삭제하지 않습니다.
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


del /q "%VPC_OUTPUT_FILE%" > nul 2>&1
del /q "%STATE_OUTPUT_FILE%" > nul 2>&1


terraform -chdir=terraform state list ^
    > "%STATE_OUTPUT_FILE%" 2>nul


if errorlevel 1 (
    echo.
    echo [오류] Terraform State를 확인하지 못했습니다.
    echo terraform init과 Backend 상태를 확인하세요.
    del /q "%STATE_OUTPUT_FILE%" > nul 2>&1
    pause
    exit /b 1
)


for %%F in ("%STATE_OUTPUT_FILE%") do set "STATE_FILE_SIZE=%%~zF"


if "!STATE_FILE_SIZE!"=="0" (
    echo.
    echo [안내] Terraform State에 관리 중인 리소스가 없습니다.
    echo 이미 전체 인프라가 삭제된 상태입니다.
    del /q "%STATE_OUTPUT_FILE%" > nul 2>&1
    pause
    exit /b 0
)


del /q "%STATE_OUTPUT_FILE%" > nul 2>&1


terraform -chdir=terraform output -raw vpc_id ^
    > "%VPC_OUTPUT_FILE%" 2>nul


if errorlevel 1 (
    echo.
    echo [오류] Terraform Output에서 VPC ID를 조회하지 못했습니다.
    echo.
    echo 직접 확인 명령:
    echo terraform -chdir=terraform output -raw vpc_id
    echo.
    del /q "%VPC_OUTPUT_FILE%" > nul 2>&1
    pause
    exit /b 1
)


set /p PROJECT_VPC_ID=<"%VPC_OUTPUT_FILE%"


del /q "%VPC_OUTPUT_FILE%" > nul 2>&1


if not defined PROJECT_VPC_ID (
    echo.
    echo [오류] 프로젝트 VPC ID가 비어 있습니다.
    pause
    exit /b 1
)


if /I not "!PROJECT_VPC_ID:~0,4!"=="vpc-" (
    echo.
    echo [오류] 조회된 값이 VPC ID 형식이 아닙니다.
    echo 조회 결과: !PROJECT_VPC_ID!
    pause
    exit /b 1
)


aws ec2 describe-vpcs ^
    --region %AWS_REGION% ^
    --vpc-ids !PROJECT_VPC_ID! ^
    --query "Vpcs[0].VpcId" ^
    --output text > nul 2>&1


if errorlevel 1 (
    echo.
    echo [오류] 조회한 VPC가 현재 AWS 계정 또는 리전에 없습니다.
    echo.
    echo AWS 계정: %AWS_ACCOUNT_ID%
    echo AWS 리전: %AWS_REGION%
    echo VPC ID: !PROJECT_VPC_ID!
    echo.
    pause
    exit /b 1
)


echo.
echo [정상] 프로젝트 VPC 확인 완료
echo 프로젝트 VPC: !PROJECT_VPC_ID!


echo.
echo ============================================================
echo [3/8] EKS Context 확인
echo ============================================================


aws eks describe-cluster ^
    --region %AWS_REGION% ^
    --name %EKS_CLUSTER_NAME% > nul 2>&1


if errorlevel 1 (
    echo.
    echo [안내] EKS Cluster가 이미 삭제됐거나 존재하지 않습니다.
    echo Kubernetes 리소스 정리 단계를 건너뜁니다.
    goto TERRAFORM_INITIALIZE
)


for /f "delims=" %%C in ('kubectl config current-context 2^>nul') do (
    set "CURRENT_CONTEXT=%%C"
)


if not defined CURRENT_CONTEXT (
    echo.
    echo [오류] 현재 Kubernetes Context를 확인하지 못했습니다.
    echo.
    echo 아래 명령을 실행한 후 다시 시도하세요.
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
    pause
    exit /b 1
)


echo.
echo [정상] EKS Context 확인 완료


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
        echo [오류] ecommerce-monitoring 삭제가 완료되지 않았습니다.
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
        echo [오류] ecommerce-platform 삭제가 완료되지 않았습니다.
        pause
        exit /b 1
    )
)


echo.
echo [정상] Argo CD Application 삭제 완료


echo.
echo ============================================================
echo [5/8] Ingress 및 ALB 정리
echo ============================================================


kubectl delete ingress ecommerce-ingress ^
    -n ecommerce ^
    --ignore-not-found=true ^
    --wait=false


kubectl get ingress ecommerce-ingress ^
    -n ecommerce > nul 2>&1


if not errorlevel 1 (
    kubectl wait ^
        --for=delete ^
        ingress/ecommerce-ingress ^
        -n ecommerce ^
        --timeout=300s

    if errorlevel 1 (
        echo.
        echo [오류] Ingress 삭제가 완료되지 않았습니다.
        pause
        exit /b 1
    )
)


echo.
echo AWS Load Balancer Controller가 ALB를 삭제할 때까지 기다립니다.


set /a ALB_CHECK_COUNT=0


:WAIT_FOR_ALB_DELETE


set "ALB_COUNT="


del /q "%ALB_OUTPUT_FILE%" > nul 2>&1


aws elbv2 describe-load-balancers ^
    --region %AWS_REGION% ^
    --query "length(LoadBalancers[?VpcId=='!PROJECT_VPC_ID!'])" ^
    --output text > "%ALB_OUTPUT_FILE%" 2>nul


if errorlevel 1 (
    echo.
    echo [오류] AWS ALB 상태 조회에 실패했습니다.
    del /q "%ALB_OUTPUT_FILE%" > nul 2>&1
    pause
    exit /b 1
)


set /p ALB_COUNT=<"%ALB_OUTPUT_FILE%"


del /q "%ALB_OUTPUT_FILE%" > nul 2>&1


if not defined ALB_COUNT (
    echo.
    echo [오류] ALB 조회 결과를 확인하지 못했습니다.
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
echo Terraform Destroy를 중단합니다.
pause
exit /b 1


:ALB_DELETE_COMPLETE


echo.
echo [정상] 프로젝트 ALB 삭제 완료


:TERRAFORM_INITIALIZE


echo.
echo ============================================================
echo [6/8] Terraform 초기화 및 State 확인
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


terraform state list


if errorlevel 1 (
    echo.
    echo [오류] Terraform State 조회 실패
    popd
    pause
    exit /b 1
)


echo.
echo ============================================================
echo [7/8] Terraform 전체 삭제
echo ============================================================
echo.
echo 첫 번째 Terraform Destroy를 실행합니다.
echo.


terraform destroy -auto-approve


if not errorlevel 1 goto TERRAFORM_DESTROY_SUCCESS


echo.
echo ============================================================
echo Terraform Destroy 1차 실패
echo ============================================================
echo.
echo EKS가 동적으로 생성한 잔여 ENI와 Security Group을 확인합니다.
echo.


popd


call :CLEANUP_EKS_ORPHANS


echo.
echo 잔여 리소스 정리 후 10초 동안 기다립니다.
timeout /t 10 /nobreak > nul


pushd "%~dp0..\terraform"


if errorlevel 1 (
    echo.
    echo [오류] terraform 폴더를 찾을 수 없습니다.
    pause
    exit /b 1
)


echo.
echo ============================================================
echo Terraform Destroy 재시도
echo ============================================================
echo.


terraform destroy -auto-approve


if errorlevel 1 (
    echo.
    echo [오류] Terraform Destroy 재시도도 실패했습니다.
    echo.
    echo 아래 명령으로 남아 있는 State를 확인하세요.
    echo terraform -chdir=terraform state list
    echo.
    popd
    pause
    exit /b 1
)


:TERRAFORM_DESTROY_SUCCESS


popd


echo.
echo ============================================================
echo [8/8] 삭제 결과 확인
echo ============================================================
echo.


echo.
echo ---------- Terraform State ----------
terraform -chdir=terraform state list


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
    --query "Reservations[].Instances[].{ID:InstanceId,State:State.Name}" ^
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
echo 전체 인프라 삭제 완료
echo ============================================================
echo.
echo Terraform State와 프로젝트 리소스 목록이 비어 있으면 정상입니다.
echo 공유 GitHub Actions OIDC Provider는 삭제하지 않았습니다.
echo.


del /q "%VPC_OUTPUT_FILE%" > nul 2>&1
del /q "%ALB_OUTPUT_FILE%" > nul 2>&1
del /q "%STATE_OUTPUT_FILE%" > nul 2>&1


pause
endlocal
exit /b 0


REM ============================================================
REM EKS가 동적으로 생성하고 남긴 리소스 정리
REM ============================================================

:CLEANUP_EKS_ORPHANS


echo.
echo ---------- EKS 잔여 ENI 확인 ----------
echo.


for /f "delims=" %%E in ('aws ec2 describe-network-interfaces --region %AWS_REGION% --filters "Name=vpc-id,Values=!PROJECT_VPC_ID!" "Name=status,Values=available" "Name=requester-managed,Values=false" "Name=description,Values=aws-K8S-*" --query "NetworkInterfaces[].NetworkInterfaceId" --output text 2^>nul') do (
    for %%I in (%%E) do (
        if /I not "%%I"=="None" (
            echo EKS 잔여 ENI 삭제: %%I

            aws ec2 delete-network-interface ^
                --region %AWS_REGION% ^
                --network-interface-id %%I

            if errorlevel 1 (
                echo [경고] ENI %%I 삭제 실패
            ) else (
                echo [정상] ENI %%I 삭제 완료
            )
        )
    )
)


echo.
echo ---------- EKS Cluster 존재 여부 확인 ----------
echo.


aws eks describe-cluster ^
    --region %AWS_REGION% ^
    --name %EKS_CLUSTER_NAME% > nul 2>&1


if not errorlevel 1 (
    echo [경고] EKS Cluster가 아직 존재합니다.
    echo EKS 자동 생성 Security Group은 삭제하지 않습니다.
    exit /b 0
)


echo EKS Cluster가 삭제된 상태입니다.
echo 잔여 EKS Cluster Security Group을 확인합니다.


echo.
echo ---------- EKS 잔여 Security Group 정리 ----------
echo.


for /f "delims=" %%G in ('aws ec2 describe-security-groups --region %AWS_REGION% --filters "Name=vpc-id,Values=!PROJECT_VPC_ID!" "Name=group-name,Values=eks-cluster-sg-%EKS_CLUSTER_NAME%-*" --query "SecurityGroups[].GroupId" --output text 2^>nul') do (
    for %%S in (%%G) do (
        if /I not "%%S"=="None" (
            echo EKS 잔여 Security Group 삭제: %%S

            aws ec2 delete-security-group ^
                --region %AWS_REGION% ^
                --group-id %%S

            if errorlevel 1 (
                echo [경고] Security Group %%S 삭제 실패
            ) else (
                echo [정상] Security Group %%S 삭제 완료
            )
        )
    )
)


exit /b 0