# Kinesis Partition Key 규칙

## 결정: `order_id`를 Partition Key로 사용한다

```python
kinesis.put_record(
    StreamName=STREAM_NAME,
    Data=json.dumps(payload).encode("utf-8"),
    PartitionKey=str(order_id),   # ← order_id를 문자열로 변환해서 사용
)
```

## 왜 order_id인가

Kinesis는 Partition Key를 해시해서 어느 샤드로 보낼지 결정한다. 이 선택에는 두 가지 요구사항이 걸려있다.

1. **같은 주문에 대한 이벤트는 항상 같은 샤드로 가야 순서가 보장된다.** (지금은 주문당 이벤트가 1개뿐이라 순서 문제가 당장 드러나진 않지만, 나중에 한 주문에 여러 이벤트가 생기는 확장을 하더라도 순서가 깨지지 않도록 미리 설계)
2. **특정 값에 트래픽이 쏠리지 않고 여러 샤드에 고르게 분산되어야 한다.** `order_id`는 계속 증가하는 유니크한 값이라, 여러 샤드에 걸쳐 고르게 분산된다.

## product_id를 쓰지 않은 이유

인기 상품 하나에 주문이 몰리면, `product_id`를 파티션 키로 썼을 경우 **그 상품의 모든 이벤트가 샤드 하나에 몰려서 핫샤드(hot shard) 문제**가 생긴다. `order_id`는 이 문제를 피할 수 있다.

## 참고 — 샤드 확장 시 재검토 필요

샤드를 여러 개로 늘리는 시점(트래픽 증가로 `IteratorAge`가 계속 오르는 경우)이 오면, 실제로 `order_id` 기반 분산이 고르게 되고 있는지 CloudWatch `IncomingRecords` 지표를 샤드별로 비교해서 재검증할 것.
