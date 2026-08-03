# Kinesis 이벤트 JSON 규격

## 이벤트 형식

```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "event_type": "ORDER_CREATED",
  "order_id": 1001,
  "product_id": 10,
  "quantity": 2,
  "created_at": "2026-08-05T09:00:00Z"
}
```

## 필드 규격

| 필드 | 형식 | 필수 | 설명 |
| --- | --- | --- | --- |
| `event_id` | UUID 문자열 | O | `outbox_events.event_id`와 동일한 값. 3번(Worker)이 이 값으로 중복 처리 방지 |
| `event_type` | 문자열 | O | 최초 구현값은 `"ORDER_CREATED"` 고정. 추후 이벤트 종류가 늘어나면 확장 |
| `order_id` | 정수 | O | 주문 고유번호. Kinesis Partition Key로도 사용 (partition_key_policy.md 참고) |
| `product_id` | 정수 | O | 상품 고유번호 |
| `quantity` | 정수 | O | 주문 수량 (양의 정수) |
| `created_at` | ISO 8601 UTC 문자열 | O | `outbox_events.created_at`을 ISO 형식으로 직렬화한 값 |

## 인코딩 규칙

- Kinesis `Data` 필드에 **UTF-8로 인코딩된 JSON 바이트열**로 담는다.
- 키 이름은 전부 snake_case로 통일 (팀 공통 규칙).
- 필드 순서는 규격에 영향 없음 (JSON 파싱은 키 기반).

## 이 규격을 지켜야 하는 이유

Worker(3번)는 이 JSON 구조를 그대로 파싱해서 재고 차감 로직에 쓴다. **필드명, 타입, event_type 값이 여기서 벗어나면 Worker 쪽 파싱이 깨진다.** 규격 변경이 필요하면 반드시 팀 공통 문서(1일차 계획)에 먼저 반영하고 3번과 합의 후 변경할 것.
