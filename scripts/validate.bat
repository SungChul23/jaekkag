@echo off
chcp 65001 > nul
setlocal

REM ============================================================
REM 재깍 프로젝트 배포 전 설정 검증 스크립트
REM 실제 AWS 및 Kubernetes 리소스는 변경하지 않는다.
REM ============================================================

REM 프로젝트 최상위 폴더로 이동
cd /d "%~dp0.."

set VALIDATION_FAILED=0


echo.
echo ============================================================
echo [1/5] Git 공백 및 충돌 표시 검사
echo ============================================================
git diff --check

if errorlevel 1 (
    echo [실패] Git 변경 내용에 공백 또는 충돌 문제가 있습니다.
    set VALIDATION_FAILED=1
) else (
    echo [정상] Git 변경 내용 검사 완료
)


echo.
echo ============================================================
echo [2/5] Terraform 포맷 검사
echo ============================================================
pushd terraform

terraform fmt -check -recursive

if errorlevel 1 (
    echo [실패] Terraform 포맷 수정이 필요합니다.
    echo        수정 명령: terraform -chdir=terraform fmt -recursive
    set VALIDATION_FAILED=1
) else (
    echo [정상] Terraform 포맷 검사 완료
)


echo.
echo ============================================================
echo [3/5] Terraform 구성 검증
echo ============================================================
terraform validate

if errorlevel 1 (
    echo [실패] Terraform 구성에 오류가 있습니다.
    set VALIDATION_FAILED=1
) else (
    echo [정상] Terraform 구성 검증 완료
)

popd


echo.
echo ============================================================
echo [4/5] Kubernetes 애플리케이션 Manifest 검증
echo ============================================================
kubectl kustomize .\k8s > nul

if errorlevel 1 (
    echo [실패] k8s Manifest 또는 kustomization.yaml에 오류가 있습니다.
    set VALIDATION_FAILED=1
) else (
    echo [정상] Kubernetes 애플리케이션 Manifest 검증 완료
)


echo.
echo ============================================================
echo [5/5] Monitoring Manifest 검증
echo ============================================================
kubectl kustomize .\monitoring > nul

if errorlevel 1 (
    echo [실패] monitoring Manifest 또는 kustomization.yaml에 오류가 있습니다.
    set VALIDATION_FAILED=1
) else (
    echo [정상] Monitoring Manifest 검증 완료
)


echo.
echo ============================================================

if "%VALIDATION_FAILED%"=="0" (
    echo 전체 검증 성공
    echo Terraform 및 Kubernetes 설정에서 오류가 발견되지 않았습니다.
    echo ============================================================
    echo.
    pause
    endlocal
    exit /b 0
) else (
    echo 전체 검증 실패
    echo 위의 실패 항목을 수정한 후 다시 실행하세요.
    echo ============================================================
    echo.
    pause
    endlocal
    exit /b 1
)