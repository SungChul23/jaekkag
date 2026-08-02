# [테스트] ecommerce-realtime 실제 배포 런북 

이 순서대로 하면 실제 AWS에 VPC/EKS/RDS/ECR/Kinesis가 뜨고,
주문 -> Outbox -> Kinesis -> 재고 차감까지 진짜로 동작하는 걸 확인할 수 있습니다.

⚠️ 리전은 us-east-1(북부 버지니아), 노드는 t3.small 2대 기준으로 켜놓는 동안 시간당 대략 $0.2 정도 과금됩니다(EKS 컨트롤플레인 $0.10 + 노드 2대 $0.04 + NAT $0.045 + RDS $0.017). 확인 끝나면 맨 아래 "정리(destroy)"까지 꼭 실행하세요.

사전 준비: `aws configure`로 자격증명 설정, terraform >= 1.6, kubectl, docker, helm 설치.

---

## 1. Terraform 인프라 생성 (순서 중요 - 서로 참조함)

```bash
cd terraform/vpc     && terraform init && terraform apply -auto-approve
cd ../eks             && terraform init && terraform apply -auto-approve   # 15~20분 소요
cd ../rds             && terraform init && terraform apply -auto-approve
cd ../ecr             && terraform init && terraform apply -auto-approve
cd ../kinesis         && terraform init && terraform apply -auto-approve
cd ../irsa            && terraform init && terraform apply -auto-approve
```

각 폴더에서 필요한 output 값을 적어두세요 (다음 단계에서 씁니다):

```bash
cd ../rds    && terraform output rds_endpoint
cd ../ecr    && terraform output
cd ../irsa   && terraform output
```

## 2. kubectl 연결

```bash
aws eks update-kubeconfig --region us-east-1 --name test-ecommerce-dev-eks
kubectl get nodes   # 노드 2개 떠 있으면 정상
```

참고: t3.small은 vCPU 2 / 메모리 2GB라 EKS 시스템 파드(coredns, kube-proxy, aws-node) 떠 있는 채로 앱 파드까지 올리면 여유가 넉넉하진 않아요. `kubectl get pods -A` 했을 때 `Pending` 파드가 보이면 `terraform/eks/eks.tf`의 `desired_size`를 3으로 늘리거나 인스턴스 타입을 한 단계 올려주세요.

## 3. ALB Ingress를 쓰려면 AWS Load Balancer Controller 설치 (최소 명령)

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=ecommerce-dev-eks \
  --set region=us-east-1 \
  --set vpcId=$(cd terraform/vpc && terraform output -raw vpc_id)
```
(IAM 권한 이슈가 나면 AWS 공식 가이드의 `AWSLoadBalancerControllerIAMPolicy`를 노드 역할 또는 별도 IRSA에 붙여야 합니다. 지금은 학습용이라 최소 명령만 적었습니다.)

## 4. Docker 이미지 빌드 & ECR 푸시

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

for app in order-api outbox-publisher inventory-worker; do
  docker build -t $app:latest apps/$app
  docker tag $app:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$app:latest
  docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$app:latest
done
```

## 5. k8s 매니페스트 값 채워넣기

아래 파일들의 `<...>` placeholder를 1단계에서 적어둔 terraform output 값으로 교체하세요:
- `k8s/base/configmap.yaml` → `DB_HOST`
- `k8s/base/secret.example.yaml` → `DB_PASSWORD` 채워서 `k8s/base/secret.yaml`로 저장 (git에는 example만 유지)
- `k8s/order-api/deployment.yaml`, `k8s/outbox-publisher/deployment.yaml`, `k8s/inventory-worker/deployment.yaml` → `image:` 를 ECR repo url + latest로 교체
- `k8s/outbox-publisher/deployment.yaml`, `k8s/inventory-worker/deployment.yaml` → `eks.amazonaws.com/role-arn` 을 irsa output 값으로 교체

## 6. 배포

```bash
kubectl apply -f k8s/base/namespace.yaml
kubectl apply -f k8s/base/configmap.yaml
kubectl apply -f k8s/base/secret.yaml
kubectl apply -f k8s/base/db-schema-job.yaml   # RDS에 테이블 생성 (1회성 Job)
kubectl apply -f k8s/order-api/
kubectl apply -f k8s/outbox-publisher/
kubectl apply -f k8s/inventory-worker/

kubectl get pods -n ecommerce -w
```

## 7. 확인

```bash
kubectl get ingress -n ecommerce   # ADDRESS 컬럼에 ALB 주소 뜰 때까지 몇 분 대기

curl -X POST http://<ALB주소>/orders -H "Content-Type: application/json" \
  -d '{"product_id": 10, "quantity": 2}'

# 로그로 흐름 확인
kubectl logs -n ecommerce -l app=outbox-publisher -f
kubectl logs -n ecommerce -l app=inventory-worker -f
```

## 8. 정리 (반드시 실행)

```bash
kubectl delete -f k8s/order-api/ -f k8s/outbox-publisher/ -f k8s/inventory-worker/
kubectl delete -f k8s/base/

cd terraform/irsa    && terraform destroy -auto-approve
cd ../kinesis         && terraform destroy -auto-approve
cd ../ecr             && terraform destroy -auto-approve
cd ../rds             && terraform destroy -auto-approve -var="db_password=원하는비밀번호"
cd ../eks             && terraform destroy -auto-approve
cd ../vpc             && terraform destroy -auto-approve
```
