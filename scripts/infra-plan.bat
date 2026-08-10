@echo off
chcp 65001 > nul
setlocal

REM ============================================================
REM Terraform 구성 검증 및 실행 계획 생성
REM AWS 리소스를 실제로 생성, 변경, 삭제하지 않는다.
REM 생성된 계획은 terraform\jaekkag.tfplan에 저장한다.
REM ============================================================

REM 프로젝트의 terraform 폴더로 이동
pushd "%~dp0..\terraform"

if errorlevel 1 (
    echo [오류] terraform 폴더를 찾을 수 없습니다.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo [1/5] AWS 접속 계정 확인
echo ============================================================

aws sts get-caller-identity

if errorlevel 1 (
    echo.
    echo [오류] AWS 인증 상태를 확인하세요.
    popd
    pause
    exit /b 1
)

echo.
echo ============================================================
echo [2/5] Terraform 초기화
echo ============================================================

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
echo [3/5] Terraform 포맷 검사
echo ============================================================

terraform fmt -check

if errorlevel 1 (
    echo.
    echo [오류] Terraform 파일 포맷이 맞지 않습니다.
    echo 수정 명령: terraform fmt
    popd
    pause
    exit /b 1
)

echo.
echo ============================================================
echo [4/5] Terraform 구성 검증
echo ============================================================

terraform validate

if errorlevel 1 (
    echo.
    echo [오류] terraform validate 실패
    popd
    pause
    exit /b 1
)

echo.
echo ============================================================
echo [5/5] Terraform 실행 계획 생성
echo ============================================================
echo.
echo DB 비밀번호 입력 요청이 나오면 현재 RDS 비밀번호를 입력하세요.
echo 입력한 비밀번호는 화면에 표시되지 않을 수 있습니다.
echo.

terraform plan -out=jaekkag.tfplan

if errorlevel 1 (
    echo.
    echo [오류] terraform plan 실패
    echo AWS 권한, 변수값, DB 비밀번호를 확인하세요.
    popd
    pause
    exit /b 1
)

echo.
echo ============================================================
echo Terraform Plan 완료
echo ============================================================
echo.
echo 저장 위치:
echo terraform\jaekkag.tfplan
echo.
echo 확인 기준:
echo No changes가 나오면 현재 인프라와 코드가 일치합니다.
echo 변경 내용이 나오면 apply 전에 반드시 내용을 확인하세요.
echo.

popd
pause
endlocal