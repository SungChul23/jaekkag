from prometheus_client import Counter, Gauge, Histogram


inventory_processed_total = Counter(
    "inventory_processed_total",
    "Number of inventory events committed with a SUCCESS result",
)

inventory_out_of_stock_total = Counter(
    "inventory_out_of_stock_total",
    "Number of inventory events committed with an OUT_OF_STOCK result",
)

inventory_duplicate_events_total = Counter(
    "inventory_duplicate_events_total",
    "Number of inventory events identified as duplicates",
)

inventory_failed_total = Counter(
    "inventory_failed_total",
    "Number of inventory events committed with a FAILED result",
)

# Worker가 Kinesis 레코드를 몇 건 처리했는지 누적해서 세는 Counter
inventory_kinesis_records_total = Counter(
    "inventory_kinesis_records_total",
    "Number of Kinesis records delivered to the inventory processor",
)

# Kinesis 처리 지연을 보는 메트릭
inventory_kinesis_iterator_age_milliseconds = Gauge(
    "inventory_kinesis_iterator_age_milliseconds",
    "Kinesis consumer delay behind the latest record for each shard",
    ["shard_id"],
)

inventory_processing_duration_seconds = Histogram(
    "inventory_processing_duration_seconds",
    "Time spent processing one inventory event",
)
