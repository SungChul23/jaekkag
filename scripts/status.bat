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
echo [4/10] EKS Cluster
echo ============================================================
aws eks describe-cluster ^
    --name ecommerce-dev-eks ^
    --region us-east-1 ^
    --query "cluster.{Name:name,Status:status,Version:version,Endpoint:endpoint}" ^
    --output table


echo.
echo ============================================================
echo [5/10] 프로젝트 EC2 Worker Node
echo ============================================================
aws ec2 describe-instances ^
    --region us-east-1 ^
    --filters ^
        "Name=instance-state-name,Values=running" ^
        "Name=tag:eks:cluster-name,Values=ecommerce-dev-eks" ^
    --query "Reservations[].Instances[].{Name:Tags[?Key=='Name']|[0].Value,InstanceId:InstanceId,Type:InstanceType,PrivateIP:PrivateIpAddress,AZ:Placement.AvailabilityZone}" ^
    --output table


echo.
echo ============================================================
echo [6/10] 비용 발생 가능성이 큰 AWS 리소스
echo ============================================================

echo.
echo 주의: NAT Gateway는 팀 공용 AWS 계정 전체에서 조회됩니다.
echo       다른 팀의 리소스도 함께 표시될 수 있습니다.

echo.
echo ---------- NAT Gateway: 계정 전체 ----------
aws ec2 describe-nat-gateways ^
    --region us-east-1 ^
    --filter "Name=state,Values=available" ^
    --query "NatGateways[].{ID:NatGatewayId,VPC:VpcId,State:State,Created:CreateTime}" ^
    --output table


echo.
echo ---------- 프로젝트 RDS ----------
aws rds describe-db-instances ^
    --db-instance-identifier ecommerce-dev-rds ^
    --region us-east-1 ^
    --query "DBInstances[0].{Name:DBInstanceIdentifier,Class:DBInstanceClass,Engine:Engine,Status:DBInstanceStatus,MultiAZ:MultiAZ,Pending:PendingModifiedValues}" ^
    --output table


echo.
echo ---------- 프로젝트 ALB ----------
aws elbv2 describe-load-balancers ^
    --region us-east-1 ^
    --query "LoadBalancers[?contains(LoadBalancerName, 'ecommerc')].{Name:LoadBalancerName,Type:Type,State:State.Code,DNS:DNSName}" ^
    --output table


echo.
echo ---------- 프로젝트 Kinesis ----------
aws kinesis describe-stream-summary ^
    --stream-name ecommerce-order-events ^
    --region us-east-1 ^
    --query "StreamDescriptionSummary.{Name:StreamName,Status:StreamStatus,Mode:StreamModeDetails.StreamMode,OpenShards:OpenShardCount,RetentionHours:RetentionPeriodHours}" ^
    --output table


echo.
echo ---------- 프로젝트 ECR ----------
aws ecr describe-repositories ^
    --region us-east-1 ^
    --query "repositories[?repositoryName=='order-api' || repositoryName=='outbox-publisher' || repositoryName=='inventory-worker'].{Name:repositoryName,URI:repositoryUri,Created:createdAt}" ^
    --output table


echo.
echo ============================================================
echo [7/10] EKS 연결, Node Group 및 Autoscaler 상태
echo ============================================================

echo.
echo ---------- 현재 kubectl Context ----------
kubectl config current-context

echo.
echo ---------- 현재 연결된 Cluster ----------
kubectl cluster-info

echo.
echo ---------- EKS Node ----------
kubectl get nodes -o wide

echo.
echo ---------- EKS Managed Node Group ----------
aws eks describe-nodegroup ^
    --cluster-name ecommerce-dev-eks ^
    --nodegroup-name ecommerce-dev-node-group ^
    --region us-east-1 ^
    --query "nodegroup.{Status:status,Desired:scalingConfig.desiredSize,Min:scalingConfig.minSize,Max:scalingConfig.maxSize,InstanceTypes:instanceTypes}" ^
    --output table

echo.
echo ---------- Cluster Autoscaler ----------
kubectl get deployment,pods ^
    -n kube-system ^
    -l app.kubernetes.io/instance=cluster-autoscaler ^
    -o wide


echo.
echo ============================================================
echo [8/10] 애플리케이션 상태
echo ============================================================
kubectl get pods,service,ingress,hpa -n ecommerce -o wide

echo.
echo ---------- Order API Pod 노드 배치 ----------
kubectl get pods ^
    -n ecommerce ^
    -l app=order-api ^
    -o wide


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
echo   1. AWS Account가 프로젝트에서 사용하는 계정인지 확인
echo   2. Terraform State에 예상한 리소스만 존재하는지 확인
echo   3. EKS Cluster와 Managed Node Group이 ACTIVE인지 확인
echo   4. EKS Node가 모두 Ready인지 확인
echo   5. ecommerce Pod가 모두 Running인지 확인
echo   6. Argo CD Application이 Synced / Healthy인지 확인
echo   7. Ingress에 ALB ADDRESS가 있는지 확인
echo   8. HPA TARGETS가 unknown이 아닌지 확인
echo   9. Cluster Autoscaler Pod가 Running인지 확인
echo  10. RDS Pending 값이 비어 있는지 확인
echo  11. 예상보다 많은 NAT, RDS, ALB, EKS가 있는지 확인
echo.
echo 참고:
echo   EC2 Worker Node의 Name이 None이어도 Kubernetes Node가
echo   Ready라면 Cluster Autoscaler로 생성된 정상 Node일 수 있습니다.
echo.
echo 주의:
echo   이 스크립트는 조회만 하며 AWS 및 Kubernetes 리소스를 변경하지 않습니다.
echo.

pause
endlocal