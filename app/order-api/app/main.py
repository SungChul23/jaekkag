from itertools import count
from time import perf_counter

from fastapi import FastAPI, HTTPException, Request, status
from prometheus_client import Counter, Histogram, make_asgi_app
from pydantic import BaseModel, Field


app = FastAPI(
    title="Ecommerce Timesale Order API",
    version="0.1.0",
)

order_id_generator = count(start=1001)


# Prometheus metrics
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


class OrderCreateRequest(BaseModel):
    product_id: int = Field(
        ...,
        gt=0,
        description="상품 ID",
        examples=[10],
    )
    quantity: int = Field(
        ...,
        gt=0,
        le=100,
        description="주문 수량",
        examples=[2],
    )


class OrderCreateResponse(BaseModel):
    order_id: int
    status: str


@app.get("/health")
def health_check():
    return {"status": "UP"}


@app.get("/ready")
def readiness_check():
    return {"status": "READY"}


@app.post(
    "/orders",
    response_model=OrderCreateResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_order(order: OrderCreateRequest):
    ORDER_REQUESTS_TOTAL.inc()

    started_at = perf_counter()

    try:
        # 临时模拟商品不存在，连接数据库后会删除
        if order.product_id == 999:
            ORDER_FAILURE_TOTAL.inc()
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Product not found",
            )

        order_id = next(order_id_generator)
        ORDER_SUCCESS_TOTAL.inc()

        return OrderCreateResponse(
            order_id=order_id,
            status="RECEIVED",
        )

    finally:
        duration = perf_counter() - started_at
        ORDER_REQUEST_DURATION_SECONDS.observe(duration)


metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)