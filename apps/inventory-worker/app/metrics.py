from prometheus_client import Counter, Histogram


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

inventory_processing_duration_seconds = Histogram(
    "inventory_processing_duration_seconds",
    "Time spent processing one inventory event",
)
