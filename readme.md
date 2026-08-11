# 🛒 트래픽 폭증에도 흔들리지 않는, 정합성을 지키는 이커머스 재고 파이프라인

주문 요청과 재고 처리를 분리하여 트래픽 급증과 일부 컴포넌트 장애 상황에서도 안정적으로 주문 이벤트를 처리하는 AWS·Kubernetes 기반 이커머스 파이프라인입니다.

Outbox Pattern과 Amazon Kinesis Data Streams를 사용해 주문 이벤트 유실을 방지하고, Inventory Worker의 멱등성 처리와 조건부 재고 차감을 통해 데이터 정합성을 보장합니다.

---

## 🎯 프로젝트 목표

- 주문과 이벤트를 동일한 데이터베이스 트랜잭션으로 저장
- 주문 API와 재고 처리 시스템을 비동기 구조로 분리
- 중복 이벤트가 발생해도 재고는 한 번만 차감
- 재고가 0보다 작아지지 않도록 조건부 차감
- 트래픽 증가 시 Order API Pod 자동 확장
- Git Push 이후 이미지 빌드부터 EKS 배포까지 자동화
- 전체 처리 흐름과 장애 상태를 Prometheus와 Grafana에서 확인
- Terraform을 이용해 AWS 인프라를 코드로 관리

---

## 📐 전체 아키텍처

```text
k6 부하 테스트
      │
      ▼
AWS Application Load Balancer
      │
      ▼
Kubernetes Ingress
      │
      ▼
Order API Service
      │
      ▼
Order API Deployment + HPA
      │
      ├── orders
      └── outbox_events
             │
             ▼
      Outbox Publisher
             │
             ▼
Amazon Kinesis Data Streams
             │
             ▼
Inventory Worker StatefulSet
      │
      ├── master_inventory
      └── processed_events
```

### 핵심 설계 원칙

Order API, Outbox Publisher, Inventory Worker는 서로 직접 호출하지 않는 독립적인 워크로드로 구성했습니다.

Order API는 주문과 Outbox 이벤트를 RDS에 저장하고, Outbox Publisher는 저장된 이벤트를 Kinesis에 발행합니다. Inventory Worker는 Kinesis 이벤트를 소비하여 재고를 차감합니다.

RDS와 Kinesis를 매개로 비동기 연결되므로 한 컴포넌트의 처리 지연이나 장애가 다른 컴포넌트로 즉시 전파되는 것을 줄일 수 있습니다.

각 워크로드는 역할에 따라 독립적으로 배포하고 확장할 수 있습니다.

---

## 🔄 주문 처리 흐름

### 1. k6 부하 테스트

동시 사용자의 주문 요청을 생성하여 타임세일과 같은 트래픽 급증 상황을 재현합니다.

일반 주문, 순간 트래픽 증가, 재고 부족, Worker 장애, 중복 이벤트 등의 시나리오를 단계별로 검증합니다.

### 2. AWS Application Load Balancer

인터넷 요청을 수신하여 EKS 내부의 Order API Pod로 전달하는 외부 진입점입니다.

### 3. Kubernetes Ingress

다음 요청을 `order-api-service`로 전달합니다.

- `/orders`
- `/health`

AWS Load Balancer Controller가 Ingress 리소스를 감지하여 실제 ALB와 Target Group을 구성합니다.

### 4. Kubernetes Service

Pod가 재생성되어 IP가 변경되어도 고정된 Service 주소를 통해 정상 상태의 Order API Pod로 요청을 전달합니다.

### 5. Order API

주문 요청을 받아 하나의 데이터베이스 트랜잭션 안에서 다음 데이터를 함께 저장합니다.

- `orders`: 주문 정보
- `outbox_events`: Kinesis에 발행할 주문 이벤트

주문 데이터와 이벤트 발행 정보를 하나의 트랜잭션으로 처리하여 주문만 저장되고 이벤트가 유실되는 이중 쓰기 문제를 방지합니다.

### 6. Outbox Publisher

`outbox_events` 테이블에서 `PENDING` 상태의 이벤트를 조회하여 Kinesis로 발행합니다.

여러 Publisher Pod가 동시에 실행되어도 `SELECT ... FOR UPDATE SKIP LOCKED` 방식을 사용하여 서로 다른 이벤트를 안전하게 처리합니다.

발행 결과는 다음 상태로 관리합니다.

- `PENDING`: 발행 대기
- `PUBLISHED`: 발행 완료
- `FAILED`: 최대 재시도 횟수 초과

### 7. Amazon Kinesis Data Streams

Order API 영역과 Inventory Worker 사이의 비동기 이벤트 스트림입니다.

| 항목 | 설정 |
|---|---|
| Stream 이름 | `ecommerce-order-events` |
| 모드 | `PROVISIONED` |
| Shard 수 | 3개 |
| 보관 기간 | 24시간 |
| Partition Key | `order_id` |

동일한 주문의 이벤트는 같은 Shard로 전달되어 Shard 내부 순서를 유지합니다.

### 8. Inventory Worker

Kinesis의 주문 이벤트를 소비하여 재고를 처리합니다.

처리 과정은 다음과 같습니다.

1. `event_id` 처리 여부 확인
2. 이미 처리한 이벤트이면 재고 차감 생략
3. `product_id` 기준 현재 재고 조회
4. 재고가 충분한 경우에만 조건부 차감
5. 처리 결과를 `processed_events`에 저장
6. 성공, 실패, 재고 부족 메트릭 기록

Inventory Worker는 3개의 StatefulSet Pod로 실행되며, 3개의 Kinesis Shard에서 이벤트를 병렬로 소비합니다.

---

## 🗄️ 데이터베이스 구성

Amazon RDS MySQL을 사용하며 외부 인터넷에 공개하지 않고 Private Subnet에 배치했습니다.

### 테이블 구성

| 테이블 | 역할 |
|---|---|
| `orders` | 주문 정보 저장 |
| `outbox_events` | Kinesis 발행 대상과 발행 상태 저장 |
| `master_inventory` | 상품별 현재 재고 저장 |
| `processed_events` | 이벤트 중복 방지 및 처리 결과 저장 |

### 상품 코드

| product_id | 모델 | 색상 |
|---|---|---|
| 101 | FOLD | BLACK |
| 102 | FOLD | WHITE |
| 103 | FOLD | LAVENDER |
| 104 | FOLD | GRAY |
| 201 | FLIP | BLACK |
| 202 | FLIP | WHITE |
| 203 | FLIP | LAVENDER |
| 204 | FLIP | GRAY |
| 301 | ULTRA | BLACK |
| 302 | ULTRA | WHITE |
| 303 | ULTRA | LAVENDER |
| 304 | ULTRA | GRAY |

`product_id`는 애플리케이션, 이벤트, 데이터베이스에서 `VARCHAR(10)` 형식으로 통일했습니다.

### 부하 테스트 기반 RDS 개선

초기에는 비용을 고려하여 RDS 인스턴스를 `db.t3.micro`로 구성했습니다.

Spike Test 과정에서 RDS 연결 수가 약 `54/61`까지 증가하는 것을 확인했습니다. Order API, Outbox Publisher, Inventory Worker가 동시에 RDS 연결을 사용하면서 트래픽이 급격히 증가할 경우 데이터베이스 연결 한도에 가까워질 수 있었습니다.

이를 해결하기 위해 다음과 같이 개선했습니다.

| 구분 | 초기 구성 | 최종 구성 |
|---|---|---|
| RDS 인스턴스 | `db.t3.micro` | `db.t3.small` |
| 변경 적용 방식 | 일반 적용 | `apply_immediately = true` |
| 애플리케이션 연결 | 기본 연결 설정 | 컴포넌트별 연결 풀 크기 조정 |
| 검증 | 일반 주문 테스트 | Spike 및 전체 파이프라인 테스트 |

Terraform의 RDS 설정에 `apply_immediately = true`를 적용하여 프로젝트 테스트 과정에서 인스턴스 변경 사항을 즉시 반영할 수 있도록 구성했습니다.

인스턴스 변경과 애플리케이션 연결 풀 조정 후 일반 주문, Spike, 재고 처리 및 전체 파이프라인 테스트를 다시 수행하여 정상 동작을 확인했습니다.

---

## ☸️ Kubernetes 구성

| 컴포넌트 | Kubernetes 리소스 | 실행 수 |
|---|---|---:|
| Order API | Deployment + HPA | 2~4 Pods |
| Outbox Publisher | Deployment | 3 Pods |
| Inventory Worker | StatefulSet | 3 Pods |
| Order API 외부 연결 | Ingress + ALB | 1개 |
| 애플리케이션 설정 | ConfigMap | 1개 |
| DB 인증정보 | Secret | 1개 |
| AWS 권한 | ServiceAccount + Pod Identity | 2개 |

### Order API 안정성 설정

| 구성 | 역할 |
|---|---|
| HPA | CPU 사용률에 따라 Pod 수 자동 조절 |
| Readiness Probe | 요청 처리 준비가 된 Pod만 Service에 연결 |
| Liveness Probe | 비정상 Pod 자동 재시작 |
| Resource Request | HPA 계산과 Pod 스케줄링 기준 제공 |
| Resource Limit | Pod가 사용할 수 있는 최대 CPU와 메모리 제한 |

### HPA 최종 설정

| 항목 | 설정 |
|---|---:|
| 최소 Pod 수 | 2 |
| 최대 Pod 수 | 4 |
| 목표 CPU 사용률 | 50% |

Spike Test에서 CPU 사용률 증가에 따라 Order API Pod가 자동으로 확장되는 것을 확인했습니다.

부하가 감소한 후에는 HPA 정책에 따라 Pod 수가 최소 Replica 수까지 축소되는 것도 확인했습니다.

---

## 🔐 AWS 권한 관리

### EKS Pod Identity

Outbox Publisher와 Inventory Worker Pod에 AWS Access Key를 직접 저장하지 않습니다.

EKS Pod Identity를 통해 Kubernetes ServiceAccount와 IAM Role을 연결하고, 각 컴포넌트에 필요한 Kinesis 권한만 임시 자격 증명으로 부여합니다.

| 컴포넌트 | AWS 권한 |
|---|---|
| Outbox Publisher | Kinesis 이벤트 발행 권한 |
| Inventory Worker | Kinesis Shard 조회 및 이벤트 소비 권한 |

### GitHub Actions OIDC

GitHub Actions에도 장기 AWS Access Key를 저장하지 않습니다.

GitHub OIDC Token을 사용하여 AWS IAM Role의 임시 자격 증명을 발급받고 Amazon ECR에 컨테이너 이미지를 Push합니다.

IAM 신뢰 정책은 팀 GitHub 저장소의 `main` 브랜치에서 실행된 워크플로만 해당 Role을 사용할 수 있도록 제한했습니다.

---

## 🚀 CI/CD 및 GitOps

```text
main 브랜치 Push
        │
        ▼
GitHub Actions
        │
        ├── GitHub OIDC 인증
        ├── Docker 이미지 3개 빌드
        └── Amazon ECR Push
                 │
                 ▼
Kubernetes 매니페스트 이미지 태그 변경
                 │
                 ▼
Argo CD 자동 동기화
                 │
                 ▼
Amazon EKS Rolling Update
```

### CI

GitHub Actions가 다음 세 개의 이미지를 병렬로 빌드합니다.

- `order-api`
- `outbox-publisher`
- `inventory-worker`

이미지 태그는 Git Commit SHA를 사용하여 어떤 코드가 배포되었는지 추적할 수 있도록 구성했습니다.

### CD

Argo CD는 다음 두 Application을 관리합니다.

| Application | Git 경로 | 역할 |
|---|---|---|
| `ecommerce-platform` | `k8s/` | 애플리케이션과 Kubernetes 리소스 배포 |
| `ecommerce-monitoring` | `monitoring/` | ServiceMonitor, Grafana 대시보드, 알림 규칙 배포 |

두 Application 모두 다음 GitOps 정책을 사용합니다.

- 자동 동기화
- `prune`
- `selfHeal`

최종적으로 두 Application의 `Synced / Healthy` 상태를 확인했습니다.

---

## 📊 Prometheus 및 Grafana

Helm의 `kube-prometheus-stack`을 사용하여 다음 구성요소를 설치했습니다.

- Prometheus
- Grafana
- Alertmanager
- Prometheus Operator
- kube-state-metrics
- Node Exporter

### 애플리케이션 메트릭 수집

| 서비스 | 주요 메트릭 | 의미 |
|---|---|---|
| Order API | `order_requests_total` | 전체 주문 요청 |
| Order API | `order_success_total` | 주문 접수 성공 |
| Order API | `order_failure_total` | 주문 처리 실패 |
| Order API | `order_request_duration_seconds` | 주문 API 처리시간 |
| Publisher | `outbox_pending_events` | 발행 대기 이벤트 |
| Publisher | `outbox_failed_events` | 최종 발행 실패 이벤트 |
| Publisher | `outbox_publish_total` | Kinesis 발행 성공 |
| Publisher | `outbox_publish_errors_total` | Kinesis 발행 실패 |
| Worker | `inventory_processed_total` | 재고 처리 성공 |
| Worker | `inventory_out_of_stock_total` | 재고 부족 |
| Worker | `inventory_duplicate_events_total` | 중복 이벤트 |
| Worker | `inventory_failed_total` | 재고 처리 실패 |
| Worker | `inventory_processing_duration_seconds` | 재고 처리시간 |
| Worker | `inventory_kinesis_iterator_age_milliseconds` | Kinesis 소비 지연 |

각 서비스는 다음 포트와 경로로 Prometheus 메트릭을 제공합니다.

```text
Order API         : 8000/metrics
Outbox Publisher  : 8001/metrics
Inventory Worker  : 8002/metrics
```

ServiceMonitor를 사용하여 세 서비스의 메트릭을 15초 간격으로 수집합니다.

### Grafana 대시보드

`Ecommerce Order & Inventory Pipeline` 대시보드에서 다음 항목을 확인할 수 있습니다.

- Order TPS
- 주문 실패율
- Order API P95 응답시간
- Outbox 대기 이벤트
- Outbox 실패 이벤트
- Kinesis 발행 처리량
- Inventory Worker 처리량
- 재고 부족 이벤트
- 중복 이벤트
- 재고 처리 실패 이벤트
- Kinesis Iterator Age

Grafana에서는 애플리케이션의 처리량, 응답시간, 이벤트 상태와 장애 메트릭을 확인합니다.

Kubernetes 리소스의 배포 및 동기화 상태는 Argo CD에서 확인하고, Pod와 HPA의 실시간 변화는 `kubectl` 명령으로 확인합니다.

### 장애 감지 규칙

| 알림 | 감지 조건 |
|---|---|
| `OrderApiFailureDetected` | 최근 5분 동안 주문 처리 실패 발생 |
| `OutboxBacklogHigh` | Outbox 대기 이벤트가 2분 이상 100건 초과 |
| `OutboxPublishFailureDetected` | Kinesis 발행 실패 발생 |
| `InventoryProcessingFailureDetected` | 재고 이벤트 처리 실패 발생 |
| `KinesisConsumerLagHigh` | Kinesis 소비 지연이 2분 이상 60초 초과 |

현재는 Prometheus와 Grafana에서 장애를 감지하고 표시하는 범위까지 구현했습니다.

Slack과 이메일 같은 외부 알림 채널은 연결하지 않았습니다.

---

## 🧪 부하 및 장애 테스트

발표자료에서는 검증 목적에 따라 테스트를 6단계로 분류했으며, 저장소에서는 실행 스크립트와 관찰 절차를 분리하여 8개의 테스트 파일로 구성했습니다.

| 순서 | 테스트 파일 | 검증 목적 |
|---:|---|---|
| 1 | `01-order-test.js` | 일반 주문과 전체 파이프라인 정상 처리 확인 |
| 2 | `02-spike-test.js` | 순간 트래픽 증가와 HPA 확장 확인 |
| 3 | `03-hpa-watch.md` | Order API Pod 및 HPA 변화 확인 |
| 4 | `04-kinesis-lag.md` | Kinesis 처리 지연과 Worker 처리량 확인 |
| 5 | `05-stockout-test.js` | 동시 주문에서 재고 음수 방지 확인 |
| 6 | `06-worker-failure.md` | Worker 장애 중 이벤트 보존과 복구 확인 |
| 7 | `07-duplicate-test.ps1` | 중복 이벤트 멱등성 처리 확인 |
| 8 | `08-final-check.md` | 주문, Outbox, 재고 및 리소스 최종 상태 확인 |

### STEP 1. 준비 및 일반 부하 테스트

일반적인 동시 주문 요청을 발생시켜 다음 흐름을 확인합니다.

```text
주문 요청
→ orders 저장
→ outbox_events 저장
→ Kinesis 발행
→ Inventory Worker 소비
→ processed_events 기록
→ master_inventory 재고 차감
```

일반 부하 테스트에서는 902건의 요청이 모두 성공했으며, 20초 동안 451건의 주문을 처리했습니다. 초당 처리량은 22.35건, 평균 응답시간은 219ms였습니다.

### STEP 2. 확장성 검증

짧은 시간 동안 요청량을 단계적으로 증가시켜 타임세일과 유사한 트래픽 급증 상황을 재현합니다.

다음 항목을 함께 관찰합니다.

- Order API 요청량
- P95 응답시간
- HPA CPU 사용률
- Order API Pod 증가
- RDS 연결 상태
- Outbox 대기 이벤트
- Publisher 발행 처리량
- Worker 처리량
- Kinesis Iterator Age

Spike Test에서는 3,314건의 요청이 모두 성공했습니다. 약 55초 동안 초당 60.25건을 처리했으며, 평균 응답시간은 246.48ms, P95 응답시간은 403.77ms, 최대 응답시간은 977.89ms였습니다.

### STEP 3. 회복탄력성 검증

부하 테스트 실행 중 다음 명령을 통해 Pod와 HPA 상태를 실시간으로 확인합니다.

```bash
kubectl get pods -n ecommerce -w
```

```bash
kubectl get hpa -n ecommerce -w
```

Inventory Worker Pod를 강제로 삭제한 뒤 Kubernetes가 새로운 Pod를 자동 생성하고 Kinesis 이벤트 처리를 계속하는지 확인합니다.

Worker 장애 중에도 주문 API는 정상 동작하고, Kinesis에 보존된 이벤트가 Worker 복구 후 처리되는지 확인합니다.

### STEP 4. 데이터 정합성 검증

한정 재고 15개 상품에 재고 수량보다 많은 주문을 발생시킵니다.

재고가 존재하는 15건만 정상 차감되고 나머지 주문은 `OUT_OF_STOCK`으로 처리되는지 확인합니다.

- 재고가 충분한 경우에만 차감
- 재고 부족 이벤트 기록
- 최종 재고가 0보다 작아지지 않음
- 동시 요청에서도 재고 정합성 유지

### STEP 5. 멱등성 검증

동일한 `event_id`를 가진 이벤트를 2회 전달하여 Inventory Worker의 멱등성 처리를 검증합니다.

`processed_events`에서 처리 여부를 확인하므로 동일한 이벤트가 다시 전달되어도 재고는 한 번만 차감됩니다.

### STEP 6. 관측 가능성 및 최종 상태 확인

Prometheus, Grafana 및 데이터베이스 조회를 통해 모든 테스트가 끝난 후 다음 항목을 확인합니다.

- Order API Pod 정상 상태
- HPA 상태
- Outbox `PENDING` 이벤트 처리 완료
- Outbox 최종 실패 여부
- Kinesis 처리 지연 정상화
- Worker 처리 성공 여부
- 재고 음수 발생 여부
- 중복 이벤트 처리 여부
- Argo CD Application 상태
- Prometheus Target 상태
- Grafana 대시보드 메트릭

---

## ✅ 최종 검증 결과

### 인프라 상태

- EKS Worker Node 2개 `Ready`
- Order API Pod 2개 `Running`
- Outbox Publisher Pod 3개 `Running`
- Inventory Worker Pod 3개 `Running`
- AWS ALB 생성 및 `/health` 응답 정상
- Argo CD Application 2개 `Synced / Healthy`
- ServiceMonitor 3개 등록
- PrometheusRule 5개 등록

### End-to-End 테스트

테스트 주문을 전송하여 전체 파이프라인을 검증했습니다.

```text
ORDER     : CREATED
OUTBOX    : PUBLISHED
PROCESSED : SUCCESS
INVENTORY : 정상 차감
```

이를 통해 다음 처리가 정상적으로 이어지는 것을 확인했습니다.

```text
주문 요청
→ orders 저장
→ outbox_events 저장
→ Kinesis 발행
→ Inventory Worker 소비
→ processed_events 기록
→ master_inventory 재고 차감
```

### 부하 테스트

k6 부하 테스트를 통해 다음 항목을 확인했습니다.

- ALB를 통한 주문 요청 정상 처리
- 트래픽 증가에 따른 Order API HPA 자동 확장
- 주문 처리량과 P95 응답시간 수집
- Outbox Publisher의 Kinesis 발행 처리량 확인
- Inventory Worker 처리량 확인
- Outbox 처리 완료 후 `PENDING` 이벤트 정상 처리
- 주문, 이벤트, 재고 처리 전체 흐름 정상
- 재고 부족 상황에서 재고 음수 방지
- 중복 이벤트 발생 시 재고 중복 차감 방지
- Worker 장애 후 미처리 이벤트 복구
- 부하 테스트에서 확인된 RDS 연결 병목 개선

### 실제 측정 결과

| 구분 | 요청 결과 | 처리량 | 평균 응답시간 | P95 응답시간 | 최대 응답시간 |
|---|---:|---:|---:|---:|---:|
| 일반 부하 테스트 | 902/902 성공 | 22.35건/초 | 219ms | - | - |
| Spike Test | 3,314/3,314 성공 | 60.25건/초 | 246.48ms | 403.77ms | 977.89ms |

Spike Test에서도 전체 요청이 성공했으며, 트래픽 증가에 따른 HPA 동작과 Publisher·Worker의 비동기 이벤트 처리를 확인했습니다.

---

## 🔍 테스트를 통해 발견하고 개선한 문제

| 문제 | 원인 | 개선 내용 | 검증 결과 |
|---|---|---|---|
| RDS 연결 수 증가 | Node 확장 후 Order API, Publisher, Worker의 동시 DB 연결 증가 | RDS를 `db.t3.small`로 변경하고 컴포넌트별 연결 풀 조정 | 부하 테스트 및 전체 파이프라인 정상 |
| 순간 트래픽 증가 | Order API 처리량 급증 | HPA 최소 2개, 최대 4개, 목표 CPU 50% 적용 | HPA가 Replica를 2개에서 4개로 증가 |
| Pod 스케줄링 한계 | HPA 확장 시 Node의 Pod 수용 한도 도달 | Pod 분산 배치와 Cluster Autoscaler 도입 검토 | 운영 환경 확장 시 적용 검토 |
| 주문과 이벤트 이중 쓰기 | 주문 저장과 이벤트 발행 시점 분리 | Transactional Outbox Pattern 적용 | 주문과 Outbox 이벤트 함께 저장 |
| 중복 이벤트 재처리 | Kinesis 이벤트 재전달 가능성 | `processed_events` 기반 멱등성 처리 | 동일 이벤트 재고 1회 차감 |
| 동시 주문 재고 경쟁 | 여러 Worker의 동일 상품 재고 차감 | 조건부 재고 차감 적용 | 재고 음수 방지 |
| Worker 장애 | 이벤트 소비 일시 중단 | Kinesis 기반 비동기 처리 | Worker 복구 후 이벤트 처리 |
| 장기 AWS Key 노출 위험 | 정적 인증정보 사용 가능성 | EKS Pod Identity와 GitHub OIDC 적용 | 임시 자격 증명으로 AWS 접근 |

---

## 👥 역할 분담

| 담당 | 기능 책임 | 애플리케이션·데이터 | 인프라·운영 | 완료 기준 |
|---|---|---|---|---|
| 1번 반이연 | 주문 접수·트래픽 대응 | Order API, `orders`, 주문 검증, 주문 메트릭, k6 | Dockerfile, Deployment, Service, Ingress, HPA, Probe | ALB 주문 요청과 HPA 확장 확인 |
| 2번 김성철 | 주문 이벤트 안전 전달 | `outbox_events`, Publisher, Kinesis 발행, 재시도 | Dockerfile, Deployment, Kinesis 발행 권한 | Outbox 이벤트가 Kinesis까지 전달 |
| 3번 차현지 | 재고 처리·정합성 | Worker, `master_inventory`, `processed_events`, 멱등성 | StatefulSet, Kinesis 소비 권한, Worker 메트릭 | 중복 차감 방지와 재고 음수 방지 |
| 4번 이광훈 | 공통 플랫폼·통합 운영 | 전체 연결 검증, 공통 설정, 통합 대시보드 | VPC, EKS, RDS, ECR, GitHub Actions, Argo CD, Prometheus, Grafana | Git Push 자동 배포와 전체 흐름·메트릭 확인 |

---

## 📁 저장소 구조

```text
jaekkag/
├── apps/
│   ├── order-api/
│   ├── outbox-publisher/
│   └── inventory-worker/
├── database/
│   ├── schema.sql
│   └── sample-data.sql
├── terraform/
├── k8s/
│   ├── base/
│   ├── order-api/
│   ├── publisher/
│   ├── inventory-worker/
│   ├── ingress/
│   └── hpa/
├── argocd/
├── monitoring/
│   ├── prometheus/
│   └── grafana/
├── load-test/
│   ├── 01-order-test.js
│   ├── 02-spike-test.js
│   ├── 03-hpa-watch.md
│   ├── 04-kinesis-lag.md
│   ├── 05-stockout-test.js
│   ├── 06-worker-failure.md
│   ├── 07-duplicate-test.ps1
│   └── 08-final-check.md
├── scripts/
├── .github/
│   └── workflows/
└── README.md
```

---

## 🛠️ 기술 스택

### Infrastructure

- Terraform
- AWS VPC
- Amazon EKS
- Amazon RDS MySQL
- Amazon ECR
- Amazon Kinesis Data Streams
- AWS Application Load Balancer

### Container & Kubernetes

- Docker
- Kubernetes
- Helm
- AWS Load Balancer Controller
- EKS Pod Identity
- Horizontal Pod Autoscaler
- Metrics Server
- Deployment
- StatefulSet
- Service
- Ingress
- ConfigMap
- Secret

### CI/CD

- GitHub Actions
- GitHub OIDC
- Amazon ECR
- Argo CD
- Kustomize

### Monitoring

- Prometheus
- Grafana
- Alertmanager
- Prometheus Operator
- ServiceMonitor
- PrometheusRule
- kube-state-metrics
- Node Exporter

### Test

- k6
- PowerShell
- kubectl

---

## ⚠️ 현재 구현 범위

3일 프로젝트 범위에 맞춰 다음 항목까지 구현하고 검증했습니다.

- Terraform 기반 AWS 및 EKS 인프라 구성
- Private Subnet 기반 RDS MySQL 구성
- ALB와 Kubernetes Ingress 기반 외부 요청 처리
- 이벤트 기반 주문·재고 비동기 처리
- Transactional Outbox Pattern
- Kinesis 3개 Shard 기반 병렬 이벤트 처리
- Inventory Worker 멱등성 처리
- 조건부 재고 차감을 통한 재고 음수 방지
- EKS Pod Identity 기반 애플리케이션 AWS 권한 관리
- GitHub OIDC 기반 CI 인증
- GitHub Actions 기반 컨테이너 이미지 빌드 및 ECR Push
- Argo CD 기반 GitOps 자동 배포
- Order API HPA 오토스케일링
- Prometheus 및 Grafana 통합 모니터링
- Prometheus 장애 감지 규칙
- 일반 주문, Spike, 재고 부족, Worker 장애, 중복 이벤트 테스트
- RDS 인스턴스 및 애플리케이션 연결 풀 최적화
- 전체 End-to-End 처리 검증

---

## 🔭 후속 개선 범위

프로젝트 기간 이후 확장할 수 있는 항목입니다.

- Outbox Polling을 CDC 기반 이벤트 발행 구조로 개선
- 채널 및 시스템 간 재고 동기화 기능 확장
- Grafana Alerting과 Slack 및 Amazon SNS 알림 연동
- LLM 기반 장애 원인 및 테스트 결과 분석 대시보드 검토
- RDS Proxy 도입을 통한 DB Connection 관리 개선 검토
- DB Migration 자동화
- HTTPS와 사용자 도메인 적용
- AWS Secrets Manager 기반 운영용 Secret 관리
- 장기 메트릭 보관을 위한 외부 스토리지 구성
- Kinesis Checkpoint 영속화
- Kinesis Client Library 적용
- 운영 환경과 개발 환경의 Terraform 구성 분리
- 장기간 부하 테스트와 장애 복구 자동화
- 운영 환경을 고려한 비용 및 용량 산정 고도화

---

## 🏁 결론

이번 프로젝트에서는 단순한 주문 API 구현을 넘어, 트래픽 증가와 컴포넌트 장애 상황에서도 주문 이벤트를 안전하게 전달하고 재고 정합성을 유지하는 인프라와 DevOps 환경을 구성했습니다.

Terraform을 통한 인프라 자동화, Kubernetes 기반 애플리케이션 운영, GitHub Actions와 Argo CD를 통한 CI/CD, Prometheus와 Grafana를 통한 모니터링을 하나의 흐름으로 통합했습니다.

또한 실제 부하 및 장애 테스트를 통해 HPA 확장, RDS 연결 병목, 이벤트 중복 처리, 재고 부족, Worker 장애 복구를 검증하고 발견된 문제를 개선했습니다.

이를 통해 다음 핵심 목표를 달성했습니다.

- Terraform 기반 인프라 구성
- Kubernetes 기반 애플리케이션 운영
- CI/CD 및 GitOps 자동 배포
- 비동기 이벤트 기반 시스템 구성
- 데이터 정합성과 멱등성 보장
- 모니터링 및 장애 감지
- 부하 테스트 기반 병목 발견과 개선