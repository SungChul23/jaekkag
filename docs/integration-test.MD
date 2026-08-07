# 통합 테스트 체크리스트

## 1. 담당자 결과물 확인

### Order API

- [ ] 로컬 실행 성공
- [ ] Docker 이미지 빌드 성공
- [ ] `POST /orders` 정상
- [ ] `/health` 정상
- [ ] `/metrics` 정상
- [ ] `orders`, `outbox_events` DDL 제공
- [ ] 필요한 환경변수 공유

### Outbox Publisher

- [ ] 로컬 실행 성공
- [ ] Docker 이미지 빌드 성공
- [ ] Outbox 조회 성공
- [ ] Kinesis 발행 코드 작성
- [ ] `/metrics` 또는 8001 포트 정상
- [ ] 필요한 환경변수 공유

### Inventory Worker

- [ ] 로컬 실행 성공
- [ ] Docker 이미지 빌드 성공
- [ ] Kinesis 소비 코드 작성
- [ ] 중복 이벤트 방지 구현
- [ ] 조건부 재고 차감 구현
- [ ] `/metrics` 또는 8002 포트 정상
- [ ] `master_inventory`, `processed_events` DDL 제공

## 2. 공통 규격 확인

- [ ] `product_id` 자료형 통일
- [ ] `order_id` 자료형 통일
- [ ] `event_id` 자료형 통일
- [ ] Kinesis 이벤트 JSON 통일
- [ ] 환경변수명 통일
- [ ] 이미지명 통일
- [ ] 서비스 포트 통일
- [ ] 메트릭명 통일

## 3. AWS 인프라 확인

- [ ] Terraform 검증 성공
- [ ] VPC 생성
- [ ] EKS 생성
- [ ] RDS 생성
- [ ] Kinesis 생성
- [ ] ECR 생성
- [ ] IAM Role 생성
- [ ] kubectl 연결

## 4. 전체 흐름 확인

- [ ] ALB로 주문 요청
- [ ] `orders` 저장
- [ ] `outbox_events` 저장
- [ ] Kinesis 발행
- [ ] Worker 이벤트 소비
- [ ] 재고 차감
- [ ] `processed_events` 기록
- [ ] 중복 이벤트 재고 중복 차감 없음
- [ ] 재고 음수 방지

## 5. 운영 기능 확인

- [ ] Prometheus Target 전체 UP
- [ ] Grafana 대시보드 표시
- [ ] HPA Pod 확장
- [ ] GitHub Actions 성공
- [ ] Argo CD Synced
- [ ] Argo CD Healthy
- [ ] Git Push 후 신규 이미지 자동 배포