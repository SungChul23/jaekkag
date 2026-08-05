import os
import uuid
import time

import pymysql
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from fastapi.responses import Response

DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = int(os.environ.get("DB_PORT", "3306"))
DB_NAME = os.environ.get("DB_NAME", "ecommerce")
DB_USER = os.environ.get("DB_USER", "appuser")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")

app = FastAPI()

order_requests_total = Counter("order_requests_total", "총 주문 요청 수")
order_request_errors_total = Counter("order_request_errors_total", "주문 요청 오류 수")
order_request_duration_seconds = Histogram("order_request_duration_seconds", "주문 요청 처리 시간")


class OrderRequest(BaseModel):
    product_id: int
    quantity: int


def get_conn():
    return pymysql.connect(
        host=DB_HOST, port=DB_PORT, db=DB_NAME,
        user=DB_USER, password=DB_PASSWORD, autocommit=False,
    )


@app.get("/health")
def health():
    return {"status": "UP"}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.post("/orders")
def create_order(req: OrderRequest):
    start = time.time()
    order_requests_total.inc()

    if req.quantity <= 0:
        order_request_errors_total.inc()
        raise HTTPException(status_code=400, detail="quantity must be positive")

    event_id = str(uuid.uuid4())
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO orders (product_id, quantity) VALUES (%s, %s)",
                (req.product_id, req.quantity),
            )
            order_id = cur.lastrowid
            cur.execute(
                """
                INSERT INTO outbox_events (event_id, order_id, product_id, quantity, status)
                VALUES (%s, %s, %s, %s, 'PENDING')
                """,
                (event_id, order_id, req.product_id, req.quantity),
            )
        conn.commit()
    except Exception:
        conn.rollback()
        order_request_errors_total.inc()
        raise HTTPException(status_code=500, detail="order creation failed")
    finally:
        conn.close()
        order_request_duration_seconds.observe(time.time() - start)

    return {"order_id": order_id, "status": "RECEIVED"}
