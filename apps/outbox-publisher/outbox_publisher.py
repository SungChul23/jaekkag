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
BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "50"))       # 한 폴링 주기에 최대 몇 건 처리할지
MAX_RETRY_COUNT = int(os.environ.get("MAX_RETRY_COUNT", "5"))  # 이 횟수 넘으면 FAILED로 전환

kinesis = boto3.client("kinesis", region_name=AWS_REGION)

outbox_pending_events = Gauge("outbox_pending_events", "발행 대기 중인 이벤트 수")
outbox_failed_events = Gauge("outbox_failed_events", "최대 재시도 초과로 실패 처리된 이벤트 수")
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
     반드시 1건 단위로 잠그고, 처리하고, 커밋한다.)
    retry_count도 같이 가져와서 재시도 한도 판단에 사용한다."""
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT event_id, order_id, product_id, quantity, created_at, retry_count
            FROM outbox_events
            WHERE publish_status = 'PENDING'
            ORDER BY created_at
            LIMIT 1
            FOR UPDATE SKIP LOCKED
            """
        )
        return cur.fetchone()


def mark_published(conn, event_id):
    """발행 성공 -> PUBLISHED 전환 + 발행 완료 시각 기록"""
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE outbox_events SET publish_status = 'PUBLISHED', published_at = NOW() WHERE event_id = %s",
            (event_id,),
        )
    conn.commit()  # 이 시점에 해당 row의 잠금이 해제됨


def mark_failed(conn, event_id, error_message, current_retry_count):
    """발행 실패 처리.
    - MAX_RETRY_COUNT 미만이면: PENDING 유지 (다음 폴링에서 자동 재시도)
    - MAX_RETRY_COUNT 이상이면: FAILED로 전환해서 더 이상 폴링 대상에서 제외
      (무한 재시도로 인한 자원 낭비/정상 이벤트 처리 지연 방지)"""
    next_retry_count = current_retry_count + 1
    with conn.cursor() as cur:
        if next_retry_count >= MAX_RETRY_COUNT:
            cur.execute(
                """
                UPDATE outbox_events
                SET publish_status = 'FAILED',
                    retry_count = %s,
                    last_error = %s
                WHERE event_id = %s
                """,
                (next_retry_count, str(error_message)[:1000], event_id),
            )
        else:
            cur.execute(
                """
                UPDATE outbox_events
                SET retry_count = %s,
                    last_error = %s
                WHERE event_id = %s
                """,
                (next_retry_count, str(error_message)[:1000], event_id),
            )
    conn.commit()
    return next_retry_count >= MAX_RETRY_COUNT


def publish_one(event_id, order_id, product_id, quantity, created_at):
    """이벤트를 Kinesis 규격(JSON)에 맞게 변환해서 발행한다.
    PartitionKey를 order_id로 지정 - 같은 주문의 이벤트는 항상
    같은 샤드로 가서 순서가 보장된다 (팀 공통 규격)."""
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
        PartitionKey=str(order_id),
    )


def update_gauges(conn):
    """현재 PENDING / FAILED 상태 이벤트 수를 세어 Gauge에 반영.
    Grafana에서 '미발행 이벤트 적체'와 '영구 실패 이벤트 누적'을
    실시간으로 볼 수 있게 해준다."""
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM outbox_events WHERE publish_status = 'PENDING'")
        (pending_count,) = cur.fetchone()
    outbox_pending_events.set(pending_count)

    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM outbox_events WHERE publish_status = 'FAILED'")
        (failed_count,) = cur.fetchone()
    outbox_failed_events.set(failed_count)


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

        event_id, order_id, product_id, quantity, created_at, retry_count = row
        try:
            publish_one(event_id, order_id, product_id, quantity, created_at)
            mark_published(conn, event_id)
            outbox_publish_total.inc()
        except Exception as e:
            outbox_publish_errors_total.inc()
            gave_up = mark_failed(conn, event_id, e, retry_count)
            if gave_up:
                print(f"[outbox-publisher] event_id={event_id} FAILED (max retry {MAX_RETRY_COUNT} exceeded): {e}", flush=True)
            else:
                print(f"[outbox-publisher] publish failed event_id={event_id} retry={retry_count + 1}/{MAX_RETRY_COUNT}: {e}", flush=True)

        processed += 1
    return processed


def main():
    start_http_server(METRICS_PORT)
    print(f"[outbox-publisher] metrics on :{METRICS_PORT}, stream={KINESIS_STREAM_NAME}", flush=True)

    while True:
        conn = get_conn()
        try:
            update_gauges(conn)
            process_batch(conn)
        finally:
            conn.close()
        time.sleep(POLL_INTERVAL_SEC)


if __name__ == "__main__":
    main()