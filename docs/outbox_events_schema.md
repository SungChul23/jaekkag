# outbox_events 테이블 설계

## 목적
Order API가 주문(`orders`) 저장과 동시에, "재고 시스템에 나중에 알려줘야 할 이벤트"를 같은 트랜잭션으로 기록해두는 테이블. Outbox 패턴의 핵심 저장소.

## 스키마

| 컬럼 | 타입 | 설명 |
| --- | --- | --- |
| `event_id` | CHAR(36) PK | UUID. 중복 처리 방지용 이벤트 고유값 |
| `order_id` | BIGINT | 주문 고유번호, Kinesis Partition Key로도 사용 |
| `product_id` | INT | 상품 고유번호 |
| `quantity` | INT | 주문 수량 |
| `status` | VARCHAR(20) | `PENDING` / `PUBLISHED` / `FAILED` (상세는 outbox_status_values.md 참고) |
| `retry_count` | INT | 발행 실패 재시도 횟수. 임계값 초과 시 FAILED로 전환 |
| `created_at` | TIMESTAMP | 이벤트 생성 시각 |
| `published_at` | TIMESTAMP NULL | 발행 성공 시각 |
| `last_failed_at` | TIMESTAMP NULL | 마지막 발행 실패 시각 |

## 설계 원칙

- **Order API와 같은 트랜잭션으로 저장된다.** `orders` INSERT와 `outbox_events` INSERT가 하나의 트랜잭션 안에서 함께 COMMIT되거나 함께 ROLLBACK되어야 함. Order API(1번) 구현 시 반드시 지켜야 할 제약.
- **Outbox Publisher(2번)는 이 테이블을 오직 폴링(SELECT)과 상태 갱신(UPDATE)만 한다.** INSERT는 절대 하지 않음 — 이벤트 생성은 Order API의 책임.
- **인덱스**: `(status, created_at)` 복합 인덱스 필수. Publisher가 `WHERE status='PENDING' ORDER BY created_at`으로 폴링하므로, 이 인덱스 없이는 테이블이 커질수록 폴링 쿼리가 느려짐.

## 왜 이 컬럼들이 필요한가

- `retry_count`, `last_failed_at`: 팀 1일차 계획의 상태값 정의(PENDING/PUBLISHED/**FAILED**)를 실제로 동작시키려면, "몇 번 실패했는지"와 "언제 마지막으로 실패했는지"를 추적할 컬럼이 있어야 FAILED 전환 로직을 구현할 수 있음. (단순 폴링 재시도만으로는 FAILED 상태 자체가 의미가 없어짐 — 영원히 PENDING으로 재시도만 반복하게 됨)
