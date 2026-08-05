from prometheus_client import Counter, Histogram


inventory_processed_total = Counter(
    "inventory_processed_total",
    "정상적으로 재고 처리가 완료된 이벤트 수",
)

inventory_duplicate_events_total = Counter(
    "inventory_duplicate_events_total",
    "중복으로 판단된 주문 이벤트 수",
)

inventory_failed_total = Counter(
    "inventory_failed_total",
    "재고 처리 중 실패한 이벤트 수",
)

inventory_processing_duration_seconds = Histogram(
    "inventory_processing_duration_seconds",
    "주문 이벤트 한 건을 처리하는 데 걸린 시간",
)