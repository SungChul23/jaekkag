@echo off
chcp 65001 > nul
setlocal

REM ============================================================
REM infra-plan.bat에서 생성한 Terraform Plan 적용
REM terraform\jaekkag.tfplan 파일만 적용한다.
REM ============================================================

pushd "%~dp0..\terraform"

if errorlevel 1 (
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
echo Terraform Plan을 적용합니다.
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
echo Terraform Apply 완료
echo ============================================================
echo.

REM 적용된 Plan의 재사용을 방지하기 위해 삭제
del /q jaekkag.tfplan > nul 2>&1

echo 사용 완료된 jaekkag.tfplan 파일을 삭제했습니다.
echo.

terraform output

popd
pause
endlocal