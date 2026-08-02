# ecommerce-realtime 실제 배포 런북 (테스트 버전)

이 순서대로 하면 실제 AWS에 VPC/EKS/RDS/ECR/Kinesis가 뜨고,
주문 -> Outbox -> Kinesis -> 재고 차감까지 진짜로 동작하는 걸 확인할 수 있습니다.
아래 내용은 실제로 한 번 처음부터 끝까지 배포하면서 만난 문제들을 전부 반영한 버전입니다.

⚠️ 리전은 us-east-1(북부 버지니아), 노드는 t3.small 2대 기준으로 켜놓는 동안 시간당 대략 $0.2 정도 과금됩니다(EKS 컨트롤플레인 $0.10 + 노드 2대 $0.04 + NAT $0.045 + RDS $0.017). 확인 끝나면 맨 아래 "정리(destroy)"까지 꼭 실행하세요.

사전 준비: `aws configure`로 자격증명 설정, terraform >= 1.6, kubectl, docker, helm 설치.

---

## 1. Terraform 인프라 생성 (순서 중요 - 서로 참조함)

```powershell
cd terraform\vpc
terraform init
terraform apply -auto-approve

cd ..\eks
terraform init
terraform apply -auto-approve   # 15~20분 소요

cd ..\rds
terraform init
terraform apply -auto-approve  -var="db_password=원하는비밀번호"

cd ..\ecr
terraform init
terraform apply -auto-approve

cd ..\kinesis
terraform init
terraform apply -auto-approve

cd ..\irsa
terraform init
terraform apply -auto-approve
```

**참고 (실제 겪었던 이슈)**
- EKS `cluster_version`은 AWS가 표준 지원을 종료하면 신규 클러스터 생성이 막혀요. 다음 명령으로 지금 시점의 표준지원 버전을 확인하고, `terraform/eks/eks.tf`의 `cluster_version` 값을 그중 하나(제일 오래된 안정 버전 권장)로 맞춰주세요.
  ```powershell
  aws eks describe-cluster-versions --query "clusterVersions[?status=='STANDARD_SUPPORT'].clusterVersion"
  ```
- `terraform/eks/eks.tf`의 `module "eks"` 블록에는 아래 한 줄이 있어야 `kubectl`이 클러스터에 접근 가능합니다 (없으면 `the server has asked for the client to provide credentials` 에러):
  ```hcl
  enable_cluster_creator_admin_permissions = true
  ```

각 폴더에서 필요한 output 값을 적어두세요 (다음 단계에서 씁니다):

```powershell
cd terraform\rds
terraform output rds_endpoint

cd ..\ecr
terraform output

cd ..\irsa
terraform output
```

## 2. kubectl 연결

```powershell
aws eks update-kubeconfig --region us-east-1 --name test-ecommerce-dev-eks
kubectl get nodes   # 노드 2개 떠 있으면 정상
```

참고: t3.small은 vCPU 2 / 메모리 2GB라 EKS 시스템 파드(coredns, kube-proxy, aws-node) 떠 있는 채로 앱 파드까지 올리면 여유가 넉넉하진 않아요. `kubectl get pods -A` 했을 때 `Pending` 파드가 보이면 `terraform/eks/eks.tf`의 `desired_size`를 3으로 늘리거나 인스턴스 타입을 한 단계 올려주세요.

## 3. Helm 설치 (Windows)

```powershell
winget install Helm.Helm
```
설치 후 터미널/VSCode를 완전히 재시작해야 PATH가 반영돼요. winget이 권한 문제로 실패하면 수동 설치:
1. https://get.helm.sh 에서 `helm-vX.X.X-windows-amd64.zip` 다운로드
2. **영문 경로**(예: `C:\tools\helm\`)에 압축 해제 (사용자 이름에 한글이 있으면 경로 문제로 설치가 실패할 수 있어요)
3. 시스템 환경변수 `Path`에 그 폴더 추가 후 터미널 재시작

## 4. ALB Ingress를 쓰려면 AWS Load Balancer Controller 설치 + IAM 권한

**4-1. 컨트롤러 설치**
```powershell
cd terraform\vpc
$VPC_ID = terraform output -raw vpc_id
cd ..\eks

helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller `
  -n kube-system `
  --set clusterName=test-ecommerce-dev-eks `
  --set region=us-east-1 `
  --set vpcId=$VPC_ID
```

**4-2. IAM 권한 부여 (실제로 반드시 필요합니다 — 안 하면 `AccessDenied: elasticloadbalancing:DescribeLoadBalancers` 에러로 ALB가 영원히 안 생겨요)**

```powershell
# 공식 정책 다운로드 및 생성
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://iam_policy.json
```

`terraform/eks`에서 OIDC ID 확인:
```powershell
terraform output oidc_provider_arn
# arn:aws:iam::<ACCOUNT_ID>:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/<OIDC_ID>
```

`trust-policy.json` 파일 생성 (ACCOUNT_ID, OIDC_ID를 실제 값으로 교체):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/<OIDC_ID>"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.us-east-1.amazonaws.com/id/<OIDC_ID>:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller",
          "oidc.eks.us-east-1.amazonaws.com/id/<OIDC_ID>:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

Role 생성 및 연결:
```powershell
aws iam create-role --role-name AmazonEKSLoadBalancerControllerRole --assume-role-policy-document file://trust-policy.json
aws iam attach-role-policy --role-name AmazonEKSLoadBalancerControllerRole --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy

kubectl annotate serviceaccount aws-load-balancer-controller -n kube-system `
  eks.amazonaws.com/role-arn=arn:aws:iam::<ACCOUNT_ID>:role/AmazonEKSLoadBalancerControllerRole `
  --overwrite

kubectl rollout restart deployment aws-load-balancer-controller -n kube-system
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

**4-3. Ingress yaml 문법 주의**

`kubernetes.io/ingress.class: alb` annotation은 최신 컨트롤러 버전에서 무시될 수 있어요. `k8s/order-api/service.yaml`의 Ingress는 반드시 `spec.ingressClassName: alb`를 쓰세요:
```yaml
spec:
  ingressClassName: alb
  rules:
    ...
```

## 5. ECR 로그인 & Docker 이미지 빌드 & push

```powershell
$ACCOUNT_ID = "<본인 계정 ID>"
$REGION = "us-east-1"

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

docker build --no-cache -t order-api:latest apps\order-api
docker tag order-api:latest "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/order-api:latest"
docker push "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/order-api:latest"

docker build --no-cache -t outbox-publisher:fix1 apps\outbox-publisher
docker tag outbox-publisher:fix1 "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/test-outbox-publisher:fix1"
docker push "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/test-outbox-publisher:fix1"

docker build --no-cache -t inventory-worker:fix1 apps\inventory-worker
docker tag inventory-worker:fix1 "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/test-inventory-worker:fix1"
docker push "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/test-inventory-worker:fix1"
```

**참고 (실제 겪었던 이슈)**
- `apps/outbox-publisher/requirements.txt`, `apps/inventory-worker/requirements.txt`에는 반드시 `boto3`가 들어있어야 합니다 (fastapi/uvicorn 아님 — order-api용 requirements와 다릅니다).
- ECR 저장소를 `IMMUTABLE`로 만들면 같은 태그(`:latest`)로 재push해도 태그가 갱신 안 될 수 있어요. 코드 수정 후 재배포할 땐 **매번 다른 태그**(`:fix1`, `:fix2`...)를 쓰거나, 커밋 SHA를 태그로 쓰는 걸 권장합니다.
- `k8s/*/deployment.yaml`에는 `imagePullPolicy: Always`를 추가해두세요 — 없으면 같은 태그를 재push해도 노드가 캐시된 옛날 이미지를 계속 쓰는 경우가 있어요.

## 6. k8s 매니페스트 값 채워넣기

아래 파일들의 `<...>` placeholder를 1, 5단계에서 적어둔 값으로 교체하세요:
- `k8s/base/configmap.yaml` → `DB_HOST` (rds_endpoint)
- `k8s/base/secret.example.yaml` → 복사해서 `k8s/base/secret.yaml`로 저장, `DB_PASSWORD` 채우기 (git에는 example만 유지)
- `k8s/order-api/deployment.yaml`, `k8s/outbox-publisher/deployment.yaml`, `k8s/inventory-worker/deployment.yaml` → `image:` 를 5단계에서 push한 실제 ECR URI+태그로 교체
- `k8s/outbox-publisher/deployment.yaml`, `k8s/inventory-worker/deployment.yaml` → `eks.amazonaws.com/role-arn` 을 irsa output 값으로 교체

## 7. 배포

```powershell
kubectl apply -f k8s\base\namespace.yaml
kubectl apply -f k8s\base\configmap.yaml
kubectl apply -f k8s\base\secret.yaml
kubectl apply -f k8s\base\db-schema-job.yaml   # RDS에 테이블 생성 (1회성 Job)
kubectl apply -f k8s\order-api\
kubectl apply -f k8s\outbox-publisher\
kubectl apply -f k8s\inventory-worker\

kubectl get pods -n ecommerce -w
```
`db-schema-init`가 `Completed`, 나머지 전부 `1/1 Running`이면 정상입니다.

## 8. 확인

```powershell
kubectl get ingress -n ecommerce   # ADDRESS 컬럼에 ALB 주소 뜰 때까지 몇 분 대기 (DNS 전파도 추가로 1~5분 더 걸릴 수 있음)

Invoke-RestMethod -Uri "http://<ALB주소>/orders" -Method Post -ContentType "application/json" -Body '{"product_id": 10, "quantity": 2}'
```

로그로 흐름 확인 (터미널 2개, 로그부터 먼저 켜두고 그다음 위 요청을 보내야 놓치지 않아요):
```powershell
kubectl logs -n ecommerce -l app=outbox-publisher -f
kubectl logs -n ecommerce -l app=inventory-worker -f
```
> Python `print()`는 컨테이너 로그로 나갈 때 버퍼링될 수 있어 로그가 안 보일 수 있습니다. `Dockerfile`의 `CMD`를 `["python", "-u", "publisher.py"]`처럼 `-u`(unbuffered) 옵션을 붙이면 즉시 출력됩니다.

로그가 안 보이면 DB/메트릭으로 직접 확인 (별도 파드 안 띄우고 order-api 파드를 그대로 이용):
```powershell
kubectl exec -n ecommerce deploy/order-api -- python -c "import pymysql, os; conn = pymysql.connect(host=os.environ['DB_HOST'], user=os.environ['DB_USER'], password=os.environ['DB_PASSWORD'], db=os.environ['DB_NAME']); cur = conn.cursor(); cur.execute('SELECT * FROM master_inventory'); [print(row) for row in cur.fetchall()]"

kubectl exec -n ecommerce inventory-worker-xxxxx -- python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8002/metrics').read().decode())"
```

## 9. 모니터링 (Prometheus + Grafana)

```powershell
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace

kubectl apply -f k8s\outbox-publisher\service.yaml
kubectl apply -f k8s\inventory-worker\service.yaml
kubectl apply -f k8s\monitoring\servicemonitors.yaml
```

Grafana 접속 (로컬 포트포워딩):
```powershell
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```
`http://localhost:3000` 접속. 계정 `admin` / 비밀번호 조회:
```powershell
kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 -d
```

## 10. 정리 (반드시 실행 — 순서 중요)

**ALB는 Terraform이 아니라 컨트롤러가 만든 리소스라 kubectl로 먼저 지워야 합니다.** 순서를 안 지키면 VPC destroy 시 "subnet has dependencies" 에러가 납니다.

```powershell
helm uninstall prometheus -n monitoring
kubectl delete namespace monitoring

kubectl delete -f k8s\order-api\
kubectl delete -f k8s\outbox-publisher\
kubectl delete -f k8s\inventory-worker\
kubectl delete -f k8s\base\

cd terraform\irsa
terraform destroy -auto-approve

cd ..\kinesis
terraform destroy -auto-approve

cd ..\ecr
terraform destroy -auto-approve

cd ..\rds
terraform destroy -auto-approve -var="db_password=원하는비밀번호"

cd ..\eks
terraform destroy -auto-approve

cd ..\vpc
terraform destroy -auto-approve
```

당장 시간이 없어 일부만 지운다면, 비용이 큰 **eks, rds**부터 우선 지우세요. vpc/irsa/kinesis/ecr는 켜놔도 하루 약 $1.5 수준입니다.

---

## 11. 향후 개선 방향

### 11-1. Outbox 발행 방식: 폴링 → CDC (Change Data Capture)

**지금 구조의 한계**

현재 `outbox-publisher`는 1초 주기로 `SELECT ... WHERE status='PENDING'`을 반복 실행하는 **폴링(Polling) 방식**입니다. 이벤트가 뜸하게 발생할 때는 문제없지만, 트래픽이 폭주하면 두 가지 한계가 드러납니다.

- **지연**: 최대 `POLL_INTERVAL_SEC`(현재 1초)만큼 발행이 늦어짐
- **DB 부하**: 폴링 주기를 줄일수록 `SELECT` 쿼리 자체가 부하가 되어, 정작 중요한 쓰기(주문 INSERT)를 방해할 수 있음

**대안: CDC (Debezium 등)**

Outbox 패턴 자체를 벗어나는 게 아니라, **"Outbox 이벤트를 어떻게 밖으로 꺼내느냐"는 구현 전략만 바꾸는 것**입니다. Outbox 패턴의 본질(비즈니스 데이터 + 이벤트를 하나의 트랜잭션으로 저장)은 그대로 유지됩니다.

```
현재: MySQL → (1초마다 폴링) → Outbox Publisher → Kinesis
개선: MySQL binlog → Debezium(CDC) → Kinesis (또는 Kafka)
```

Debezium이 MySQL의 binlog(트랜잭션 로그)를 실시간으로 tailing하면서, `outbox_events`에 INSERT가 커밋되는 즉시(수십 ms 이내) 감지해 스트림으로 흘려보냅니다. 폴링 쿼리 자체가 사라지므로 DB 부하와 지연이 동시에 해결됩니다. 다만 Debezium(Kafka Connect 기반) 운영 자체가 별도 인프라와 학습 비용을 요구하므로, 트래픽 규모가 실제로 폴링의 한계에 부딪힐 때 도입을 검토하는 것이 합리적입니다.

### 11-2. 재고 차감: 폭주 트래픽 대응

인기 상품 하나에 동시 요청이 몰리면 `master_inventory`의 특정 row에 락 경합이 집중되어 처리량이 급감합니다. 현업에서는 다음과 같은 방식으로 대응합니다.

- **인메모리 캐시(Redis) 선차감**: `DECR` 같은 원자적 연산으로 재고를 Redis에서 초고속 차감하고, MySQL은 최종 정합성을 맞추는 백엔드로만 사용
- **재고 파티셔닝(샤딩)**: 상품 하나의 재고를 여러 row로 쪼개어 동시 요청을 분산시켜 락 경합 완화
- **Kinesis 샤드 + Worker 확장**: `IteratorAge` 지표가 계속 증가하면 샤드 수와 Worker replica 수를 함께 늘려 병렬 처리량 확보 (이 경우 Worker가 여러 개가 되므로 KCL 등 샤드 배정/체크포인트 관리가 필요해짐)

### 11-3. 실패 이벤트 복구

현재는 발행 실패 시 `PENDING` 상태로 남아 무한 재시도됩니다. 재시도 횟수 추적, 임계값 초과 시 `FAILED` 전환, 수동 재발행 API 등은 팀 문서상 "시간 여유 시 2순위" 항목으로, 핵심 흐름이 안정화된 이후 확장 대상입니다.