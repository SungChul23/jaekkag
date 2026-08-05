# Outbox 상태값 정의

## 상태 종류

| 상태 | 의미 | 진입 조건 |
| --- | --- | --- |
| `PENDING` | 아직 Kinesis로 발행 안 됨 (초기값, 또는 발행 실패 후 재시도 대기) | Order API가 INSERT할 때 기본값 |
| `PUBLISHED` | Kinesis로 발행 성공 | Publisher가 `put_record` 성공 직후 |
| `FAILED` | 재시도 임계값을 초과해서 발행을 포기한 상태 | `retry_count`가 임계값(기본 5회) 초과 시 |

## 상태 전이 규칙

```
PENDING ──(발행 성공)──────────────→ PUBLISHED
PENDING ──(발행 실패, retry_count+1)─→ PENDING (재시도 대기 유지)
PENDING ──(retry_count > 임계값)────→ FAILED
```

- **PUBLISHED와 FAILED는 종결 상태(terminal state)**다. 한 번 PUBLISHED가 되면 다시 PENDING으로 돌아가지 않는다. FAILED도 마찬가지로, 자동으로는 재시도하지 않는다 (수동 재발행은 팀 문서상 "시간 여유 시 2순위" 범위).
- Publisher는 폴링 시 `WHERE status = 'PENDING'`만 조회한다. `FAILED` 이벤트는 자동으로는 다시 안 걸린다 — 무한 재시도로 인한 자원 낭비를 막기 위함.

## 재시도 임계값

기본값 **5회**. `outbox-publisher`의 환경변수 `MAX_RETRY_COUNT`로 조정 가능하게 구현 (코드 참고).

## 완료 기준과의 연결

팀 문서의 담당님(2번) 완료 기준: **"주문 이벤트가 Outbox에서 Kinesis까지 유실 없이 전달됨"**

- `PUBLISHED`로 전이된 이벤트 = 유실 없이 전달 성공
- `FAILED`로 전이된 이벤트 = "유실"이 아니라 "명시적으로 실패를 기록한 것" — 나중에 원인 파악과 수동 재처리가 가능한 상태로 남겨두는 것이 핵심. 조용히 사라지는 이벤트가 없도록 하는 것이 이 상태값 설계의 목적.
