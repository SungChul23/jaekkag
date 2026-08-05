"""
Outbox Publisher (2번 담당 - 주문 이벤트 안전 전달)

역할: outbox_events 테이블을 폴링하며 PENDING 이벤트를 Kinesis로 발행하고,
      성공하면 PUBLISHED, 재시도 임계값을 넘기면 FAILED로 상태를 전이시킨다.

의존: MySQL(RDS 또는 로컬 docker-compose), AWS Kinesis
"""
import os
import time
import json

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
MAX_RETRY_COUNT = int(os.environ.get("MAX_RETRY_COUNT", "5"))  # 이 횟수 초과 시 FAILED 전환

kinesis = boto3.client("kinesis", region_name=AWS_REGION)

# 팀 공통 메트릭 규격 그대로 사용
outbox_pending_events = Gauge("outbox_pending_events", "발행 대기 중인 이벤트 수")
outbox_publish_total = Counter("outbox_publish_total", "발행 성공 건수")
outbox_publish_errors_total = Counter("outbox_publish_errors_total", "발행 실패 건수")
outbox_failed_total = Counter("outbox_failed_total", "재시도 임계값 초과로 FAILED 처리된 건수")


def get_conn():
    return pymysql.connect(
        host=DB_HOST, port=DB_PORT, db=DB_NAME,
        user=DB_USER, password=DB_PASSWORD, autocommit=False,
    )


def fetch_pending(conn, limit):
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT event_id, order_id, product_id, quantity, created_at, retry_count
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


def mark_retry_or_failed(conn, event_id, retry_count):
    new_retry_count = retry_count + 1
    if new_retry_count > MAX_RETRY_COUNT:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE outbox_events
                SET status = 'FAILED', retry_count = %s, last_failed_at = NOW()
                WHERE event_id = %s
                """,
                (new_retry_count, event_id),
            )
        outbox_failed_total.inc()
        print(f"[outbox-publisher] event_id={event_id} FAILED (retry_count={new_retry_count})")
    else:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE outbox_events
                SET retry_count = %s, last_failed_at = NOW()
                WHERE event_id = %s
                """,
                (new_retry_count, event_id),
            )
        print(f"[outbox-publisher] event_id={event_id} retry {new_retry_count}/{MAX_RETRY_COUNT}")
    conn.commit()


def build_payload(row):
    event_id, order_id, product_id, quantity, created_at, _retry_count = row
    return {
        "event_id": event_id,
        "event_type": "ORDER_CREATED",
        "order_id": order_id,
        "product_id": product_id,
        "quantity": quantity,
        "created_at": created_at.isoformat(),
    }


def publish_one(row):
    payload = build_payload(row)
    order_id = row[1]
    kinesis.put_record(
        StreamName=KINESIS_STREAM_NAME,
        Data=json.dumps(payload).encode("utf-8"),
        PartitionKey=str(order_id),  # partition_key_policy.md 참고
    )


def update_pending_gauge(conn):
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM outbox_events WHERE status = 'PENDING'")
        (count,) = cur.fetchone()
    outbox_pending_events.set(count)


def main():
    start_http_server(METRICS_PORT)
    print(f"[outbox-publisher] metrics on :{METRICS_PORT}, stream={KINESIS_STREAM_NAME}, "
          f"max_retry={MAX_RETRY_COUNT}")

    while True:
        conn = get_conn()
        try:
            update_pending_gauge(conn)
            rows = fetch_pending(conn, BATCH_SIZE)
            for row in rows:
                event_id, _order_id, _product_id, _quantity, _created_at, retry_count = row
                try:
                    publish_one(row)
                    mark_published(conn, event_id)
                    outbox_publish_total.inc()
                    print(f"[outbox-publisher] published event_id={event_id}")
                except Exception as e:
                    outbox_publish_errors_total.inc()
                    print(f"[outbox-publisher] publish failed event_id={event_id}: {e}")
                    mark_retry_or_failed(conn, event_id, retry_count)
        finally:
            conn.close()
        time.sleep(POLL_INTERVAL_SEC)


if __name__ == "__main__":
    main()
