@echo off
chcp 65001 > nul
setlocal

REM ============================================================
REM infra-plan.bat에서 생성한 Terraform Plan 적용
REM terraform\jaekkag.tfplan 파일만 적용한다.
REM
REM Terraform Apply 성공 후:
REM 1. EKS kubeconfig 갱신
REM 2. kubectl Context 확인
REM 3. EKS Node 연결 상태 확인
REM ============================================================


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
    echo .\scripts\infra-plan.bat
    echo.
    popd
    pause
    exit /b 1
)


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
echo [1/4] Terraform Plan 적용
echo ============================================================
echo.

terraform apply jaekkag.tfplan

if errorlevel 1 (
    echo.
    echo [오류] Terraform Apply 실패
    echo 오류 메시지를 확인하세요.
    popd
    pause
    exit /b 1
)


echo.
echo ============================================================
echo [2/4] Terraform Apply 완료 및 출력값 확인
echo ============================================================
echo.

terraform output

if errorlevel 1 (
    echo.
    echo [경고] Terraform 적용은 완료됐지만 Output 조회에 실패했습니다.
)


REM 적용된 Plan의 재사용을 방지하기 위해 삭제
del /q jaekkag.tfplan > nul 2>&1

echo.
echo 사용 완료된 jaekkag.tfplan 파일을 삭제했습니다.


REM 프로젝트 최상위 폴더로 복귀
popd


echo.
echo ============================================================
echo [3/4] EKS kubeconfig 갱신
echo ============================================================
echo.

aws eks update-kubeconfig ^
    --region us-east-1 ^
    --name ecommerce-dev-eks

if errorlevel 1 (
    echo.
    echo [경고] Terraform Apply는 완료됐지만
    echo EKS kubeconfig 갱신에 실패했습니다.
    echo AWS 인증 정보와 EKS Cluster 상태를 확인하세요.
    echo.
    pause
    exit /b 1
)


echo.
echo 현재 kubectl Context:
kubectl config current-context


echo.
echo ============================================================
echo [4/4] EKS Node 연결 상태 확인
echo ============================================================
echo.

kubectl get nodes -o wide

if errorlevel 1 (
    echo.
    echo [경고] kubeconfig는 갱신됐지만 Node 조회에 실패했습니다.
    echo EKS Node Group 생성 상태와 접근 권한을 확인하세요.
    echo.
    pause
    exit /b 1
)


echo.
echo ============================================================
echo 인프라 적용 및 EKS 연결 확인 완료
echo ============================================================
echo.
echo 완료 항목:
echo   1. 저장된 Terraform Plan 적용
echo   2. Terraform Output 확인
echo   3. 사용 완료 Plan 파일 삭제
echo   4. EKS kubeconfig 갱신
echo   5. EKS Node 연결 확인
echo.

pause
endlocal