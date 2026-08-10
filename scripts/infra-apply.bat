@echo off
chcp 65001 > nul
setlocal EnableDelayedExpansion


REM ============================================================
REM infra-plan.bat에서 생성한 Terraform Plan 적용
REM terraform\jaekkag.tfplan 파일만 적용한다.
REM
REM Terraform Apply 성공 후:
REM 1. EKS Cluster Active 상태 대기
REM 2. kubeconfig 갱신
REM 3. kubectl Context 검증
REM 4. Worker Node 생성 및 Ready 상태 대기
REM ============================================================


set "AWS_REGION=us-east-1"
set "AWS_ACCOUNT_ID=827913617635"
set "EKS_CLUSTER_NAME=ecommerce-dev-eks"
set "CURRENT_ACCOUNT_ID="
set "CURRENT_CONTEXT="


REM terraform 폴더로 이동
pushd "%~dp0..\terraform"


if errorlevel 1 (
    echo.
    echo [오류] terraform 폴더를 찾을 수 없습니다.
    pause
    exit /b 1
)


if not exist "jaekkag.tfplan" (
    echo.
    echo [오류] jaekkag.tfplan 파일이 없습니다.
    echo 먼저 아래 명령을 실행하세요.
    echo.
    echo .\scripts\infra-plan.bat
    echo.
    popd
    pause
    exit /b 1
)


echo.
echo ============================================================
echo [사전 확인] AWS 계정 검증
echo ============================================================


aws sts get-caller-identity


if errorlevel 1 (
    echo.
    echo [오류] AWS 인증 상태를 확인하세요.
    popd
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
    echo 다른 AWS 계정에 인프라가 생성되는 것을 방지하기 위해 중단합니다.
    popd
    pause
    exit /b 1
)


echo.
echo [정상] 프로젝트 AWS 계정 확인 완료


echo.
echo ============================================================
echo Terraform Apply 준비
echo ============================================================
echo.
echo 적용할 Plan:
echo terraform\jaekkag.tfplan
echo.
echo 실제 AWS 리소스가 생성, 변경 또는 삭제될 수 있습니다.
echo Plan 내용을 확인한 경우에만 APPLY를 입력하세요.
echo.


set /p CONFIRM=입력: 


if /I not "%CONFIRM%"=="APPLY" (
    echo.
    echo Terraform Apply를 취소했습니다.
    popd
    pause
    exit /b 0
)


echo.
echo ============================================================
echo [1/6] Terraform Plan 적용
echo ============================================================
echo.


terraform apply jaekkag.tfplan


if errorlevel 1 (
    echo.
    echo [오류] Terraform Apply 실패
    echo 오류 메시지를 확인하세요.
    echo.
    echo jaekkag.tfplan 파일은 삭제하지 않았습니다.
    popd
    pause
    exit /b 1
)


echo.
echo ============================================================
echo [2/6] Terraform Output 확인
echo ============================================================
echo.


terraform output


if errorlevel 1 (
    echo.
    echo [경고] Terraform Apply는 완료됐지만 Output 조회에 실패했습니다.
)


REM 성공한 Plan의 재사용 방지
del /q jaekkag.tfplan > nul 2>&1


if exist "jaekkag.tfplan" (
    echo.
    echo [경고] 사용 완료된 jaekkag.tfplan 파일 삭제에 실패했습니다.
) else (
    echo.
    echo 사용 완료된 jaekkag.tfplan 파일을 삭제했습니다.
)


REM 프로젝트 최상위 폴더로 복귀
popd


echo.
echo ============================================================
echo [3/6] EKS Cluster Active 상태 확인
echo ============================================================
echo.
echo EKS Cluster가 Active 상태가 될 때까지 기다립니다.
echo.


aws eks wait cluster-active ^
    --region %AWS_REGION% ^
    --name %EKS_CLUSTER_NAME%


if errorlevel 1 (
    echo.
    echo [오류] EKS Cluster가 제한 시간 안에 Active 상태가 되지 않았습니다.
    echo.
    echo 아래 명령으로 상태를 확인하세요.
    echo aws eks describe-cluster --region %AWS_REGION% --name %EKS_CLUSTER_NAME%
    echo.
    pause
    exit /b 1
)


echo.
echo [정상] EKS Cluster Active 상태 확인 완료


echo.
echo ============================================================
echo [4/6] EKS kubeconfig 갱신
echo ============================================================
echo.


aws eks update-kubeconfig ^
    --region %AWS_REGION% ^
    --name %EKS_CLUSTER_NAME%


if errorlevel 1 (
    echo.
    echo [오류] Terraform Apply는 완료됐지만
    echo EKS kubeconfig 갱신에 실패했습니다.
    echo AWS 인증 정보와 EKS Cluster 상태를 확인하세요.
    echo.
    pause
    exit /b 1
)


echo.
echo ============================================================
echo [5/6] kubectl Context 검증
echo ============================================================
echo.


for /f "delims=" %%C in ('kubectl config current-context 2^>nul') do (
    set "CURRENT_CONTEXT=%%C"
)


if not defined CURRENT_CONTEXT (
    echo.
    echo [오류] 현재 kubectl Context를 확인하지 못했습니다.
    pause
    exit /b 1
)


echo 현재 Context: !CURRENT_CONTEXT!


echo !CURRENT_CONTEXT! | findstr /C:"%EKS_CLUSTER_NAME%" > nul


if errorlevel 1 (
    echo.
    echo [오류] 현재 kubectl Context가 %EKS_CLUSTER_NAME%가 아닙니다.
    echo.
    echo 현재 Context:
    echo !CURRENT_CONTEXT!
    echo.
    pause
    exit /b 1
)


echo.
echo [정상] %EKS_CLUSTER_NAME% Context 확인 완료


echo.
echo ============================================================
echo [6/6] EKS Worker Node 연결 및 Ready 상태 확인
echo ============================================================
echo.
echo Worker Node가 등록될 때까지 기다립니다.
echo 최대 10분 정도 걸릴 수 있습니다.
echo.


set /a NODE_CHECK_COUNT=0


:WAIT_FOR_NODE_REGISTRATION


kubectl get nodes -o name 2>nul | findstr /R /C:"^node/" > nul


if not errorlevel 1 goto NODE_REGISTERED


set /a NODE_CHECK_COUNT+=1


echo [!NODE_CHECK_COUNT!/60] 아직 등록된 Worker Node가 없습니다.


if !NODE_CHECK_COUNT! GEQ 60 goto NODE_REGISTRATION_TIMEOUT


timeout /t 10 /nobreak > nul
goto WAIT_FOR_NODE_REGISTRATION


:NODE_REGISTRATION_TIMEOUT


echo.
echo [오류] 10분 안에 Worker Node가 등록되지 않았습니다.
echo EKS Managed Node Group 상태를 확인하세요.
echo.
echo aws eks describe-nodegroup --region %AWS_REGION% --cluster-name %EKS_CLUSTER_NAME% --nodegroup-name ecommerce-dev-node-group
echo.
pause
exit /b 1


:NODE_REGISTERED


echo.
echo Worker Node가 등록되었습니다.
echo 모든 Node가 Ready 상태가 될 때까지 기다립니다.
echo.


kubectl wait ^
    --for=condition=Ready ^
    nodes ^
    --all ^
    --timeout=600s


if errorlevel 1 (
    echo.
    echo [오류] 일부 Worker Node가 제한 시간 안에 Ready 상태가 되지 않았습니다.
    echo.
    kubectl get nodes -o wide
    echo.
    pause
    exit /b 1
)


echo.
echo 최종 Worker Node 상태:
echo.


kubectl get nodes -o wide


if errorlevel 1 (
    echo.
    echo [오류] Worker Node 조회에 실패했습니다.
    pause
    exit /b 1
)


echo.
echo EKS Managed Node Group 확장 설정:
echo.


aws eks describe-nodegroup ^
    --region %AWS_REGION% ^
    --cluster-name %EKS_CLUSTER_NAME% ^
    --nodegroup-name ecommerce-dev-node-group ^
    --query "nodegroup.{Status:status,Desired:scalingConfig.desiredSize,Min:scalingConfig.minSize,Max:scalingConfig.maxSize}" ^
    --output table


echo.
echo ============================================================
echo 인프라 적용 및 EKS 연결 확인 완료
echo ============================================================
echo.
echo 완료 항목:
echo   1. AWS 프로젝트 계정 검증
echo   2. 저장된 Terraform Plan 적용
echo   3. Terraform Output 확인
echo   4. 사용 완료 Plan 파일 삭제
echo   5. EKS Cluster Active 상태 확인
echo   6. EKS kubeconfig 갱신
echo   7. kubectl Context 검증
echo   8. Worker Node 등록 및 Ready 상태 확인
echo.


pause
endlocal