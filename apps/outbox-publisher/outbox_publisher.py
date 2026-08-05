import os
import time
import json

import boto3
import pymysql
from prometheus_client import Counter, Gauge, start_http_server

# ============================================================
# 환경변수 설정
# ============================================================
DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = int(os.environ.get("DB_PORT", "3306"))
DB_NAME = os.environ.get("DB_NAME", "ecommerce")
DB_USER = os.environ.get("DB_USER", "appuser")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")
KINESIS_STREAM_NAME = os.environ.get("KINESIS_STREAM_NAME", "ecommerce-order-events")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
METRICS_PORT = int(os.environ.get("METRICS_PORT", "8001"))
POLL_INTERVAL_SEC = float(os.environ.get("POLL_INTERVAL_SEC", "1"))
BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "50"))  # 한 폴링 주기에 최대 몇 건 처리할지 (조절하면서 수정)

kinesis = boto3.client("kinesis", region_name=AWS_REGION)

outbox_pending_events = Gauge("outbox_pending_events", "발행 대기 중인 이벤트 수")
outbox_publish_total = Counter("outbox_publish_total", "발행 성공 건수")
outbox_publish_errors_total = Counter("outbox_publish_errors_total", "발행 실패 건수")


def get_conn():
    return pymysql.connect(
        host=DB_HOST, port=DB_PORT, db=DB_NAME,
        user=DB_USER, password=DB_PASSWORD, autocommit=False,
    )


def fetch_and_lock_one(conn):
    """PENDING 이벤트 1건을 잠그고 가져온다.
    여러 파드가 동시에 폴링해도 SKIP LOCKED 덕분에 이미 잠긴 row는
    자동으로 건너뛰고 서로 다른 row를 가져가게 된다.
    (한 번에 여러 건을 잠그면 첫 건 커밋 시 나머지 잠금까지 풀려버려서
     반드시 1건 단위로 잠그고, 처리하고, 커밋한다.)"""
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT event_id, order_id, product_id, quantity, created_at
            FROM outbox_events
            WHERE status = 'PENDING'
            ORDER BY created_at
            LIMIT 1
            FOR UPDATE SKIP LOCKED
            """
        )
        return cur.fetchone()


def mark_published(conn, event_id):
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE outbox_events SET status = 'PUBLISHED', published_at = NOW() WHERE event_id = %s",
            (event_id,),
        )
    conn.commit()  # 이 시점에 해당 row의 잠금이 해제됨


def mark_failed(conn, event_id, error_message):
    with conn.cursor() as cur:
        cur.execute(
            """
            UPDATE outbox_events
            SET retry_count = retry_count + 1,
                last_error = %s
            WHERE event_id = %s
            """,
            (str(error_message)[:1000], event_id),
        )
    conn.commit()  # 실패해도 status는 PENDING 유지 -> 다음 폴링에서 자동 재시도


def publish_one(row):
    event_id, order_id, product_id, quantity, created_at = row
    payload = {
        "event_id": event_id,
        "event_type": "ORDER_CREATED",
        "order_id": order_id,
        "product_id": product_id,
        "quantity": quantity,
        "created_at": created_at.isoformat() + "Z",
    }
    kinesis.put_record(
        StreamName=KINESIS_STREAM_NAME,
        Data=json.dumps(payload).encode("utf-8"),
        PartitionKey=str(order_id),  # order_id 기준으로 샤드 분배
    )


def update_pending_gauge(conn):
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM outbox_events WHERE status = 'PENDING'")
        (count,) = cur.fetchone()
    outbox_pending_events.set(count)


def process_batch(conn):
    """한 폴링 주기에 최대 BATCH_SIZE건까지, 1건씩 잠그고 처리한다.
    다른 파드가 이미 다 가져가서 더 이상 잠글 게 없으면 자연스럽게 멈춘다."""
    processed = 0
    for _ in range(BATCH_SIZE):
        row = fetch_and_lock_one(conn)
        if row is None:
            # 더 이상 PENDING(잠글 수 있는) 이벤트가 없음 -> 이번 배치 종료
            conn.commit()  # 트랜잭션 정리 (조회만 했어도 커밋으로 마무리)
            break

        event_id = row[0]
        try:
            publish_one(row)
            mark_published(conn, event_id)
            outbox_publish_total.inc()
        except Exception as e:
            outbox_publish_errors_total.inc()
            mark_failed(conn, event_id, e)
            print(f"[outbox-publisher] publish failed event_id={event_id}: {e}", flush=True)

        processed += 1
    return processed


def main():
    start_http_server(METRICS_PORT)
    print(f"[outbox-publisher] metrics on :{METRICS_PORT}, stream={KINESIS_STREAM_NAME}", flush=True)

    while True:
        conn = get_conn()
        try:
            update_pending_gauge(conn)
            process_batch(conn)
        finally:
            conn.close()
        time.sleep(POLL_INTERVAL_SEC)


if __name__ == "__main__":
    main()