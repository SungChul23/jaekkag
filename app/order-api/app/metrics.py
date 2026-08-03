from prometheus_client import Counter, Histogram

# Order API Metrics
ORDER_REQUESTS_TOTAL = Counter(
    "order_requests_total",
    "Total number of order requests",
)

ORDER_SUCCESS_TOTAL = Counter(
    "order_success_total",
    "Total number of successfully received orders",
)

ORDER_FAILURE_TOTAL = Counter(
    "order_failure_total",
    "Total number of failed order requests",
)

ORDER_REQUEST_DURATION_SECONDS = Histogram(
    "order_request_duration_seconds",
    "Order API request duration in seconds",
)