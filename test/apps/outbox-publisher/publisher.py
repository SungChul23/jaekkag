import os
import time
import json
import threading

import boto3
import pymysql
from prometheus_client import Counter, Gauge, start_http_server

DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = int(os.environ.get("DB_PORT", "3306"))
DB_NAME = os.environ.get("DB_NAME", "ecommerce")
DB_USER = os.environ.get("DB_USER", "appuser")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")
KINESIS_STREAM_NAME = os.environ.get("KINESIS_STREAM_NAME", "ecommerce-order-events")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
METRICS_PORT = int(os.environ.get("METRICS_PORT", "8001"))
POLL_INTERVAL_SEC = float(os.environ.get("POLL_INTERVAL_SEC", "1"))
BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "20"))

kinesis = boto3.client("kinesis", region_name=AWS_REGION)

outbox_pending_events = Gauge("outbox_pending_events", "발행 대기 중인 이벤트 수")
outbox_publish_total = Counter("outbox_publish_total", "발행 성공 건수")
outbox_publish_errors_total = Counter("outbox_publish_errors_total", "발행 실패 건수")


def get_conn():
    return pymysql.connect(
        host=DB_HOST, port=DB_PORT, db=DB_NAME,
        user=DB_USER, password=DB_PASSWORD, autocommit=False,
    )


def fetch_pending(conn, limit):
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT event_id, order_id, product_id, quantity, created_at
            FROM outbox_events
            WHERE status = 'PENDING'
            ORDER BY created_at
            LIMIT %s
            """,
            (limit,),
        )
        return cur.fetchall()


def mark_published(conn, event_id):
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE outbox_events SET status = 'PUBLISHED', published_at = NOW() WHERE event_id = %s",
            (event_id,),
        )
    conn.commit()


def publish_one(row):
    event_id, order_id, product_id, quantity, created_at = row
    payload = {
        "event_id": event_id,
        "event_type": "ORDER_CREATED",
        "order_id": order_id,
        "product_id": product_id,
        "quantity": quantity,
        "created_at": created_at.isoformat(),
    }
    kinesis.put_record(
        StreamName=KINESIS_STREAM_NAME,
        Data=json.dumps(payload).encode("utf-8"),
        PartitionKey=str(order_id),
    )


def update_pending_gauge(conn):
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM outbox_events WHERE status = 'PENDING'")
        (count,) = cur.fetchone()
    outbox_pending_events.set(count)


def main():
    start_http_server(METRICS_PORT)
    print(f"[outbox-publisher] metrics on :{METRICS_PORT}, stream={KINESIS_STREAM_NAME}")

    while True:
        conn = get_conn()
        try:
            update_pending_gauge(conn)
            rows = fetch_pending(conn, BATCH_SIZE)
            for row in rows:
                event_id = row[0]
                try:
                    publish_one(row)
                    mark_published(conn, event_id)
                    outbox_publish_total.inc()
                except Exception as e:
                    outbox_publish_errors_total.inc()
                    print(f"[outbox-publisher] publish failed event_id={event_id}: {e}")
        finally:
            conn.close()
        time.sleep(POLL_INTERVAL_SEC)


if __name__ == "__main__":
    main()
