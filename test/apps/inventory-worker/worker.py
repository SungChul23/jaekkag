import os
import time
import json

import boto3
import pymysql
from prometheus_client import Counter, Histogram, start_http_server

DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = int(os.environ.get("DB_PORT", "3306"))
DB_NAME = os.environ.get("DB_NAME", "ecommerce")
DB_USER = os.environ.get("DB_USER", "appuser")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")
KINESIS_STREAM_NAME = os.environ.get("KINESIS_STREAM_NAME", "test-ecommerce-order-events")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
METRICS_PORT = int(os.environ.get("METRICS_PORT", "8002"))

kinesis = boto3.client("kinesis", region_name=AWS_REGION)

inventory_processed_total = Counter("inventory_processed_total", "성공적으로 재고 차감된 건수")
inventory_duplicate_events_total = Counter("inventory_duplicate_events_total", "중복으로 무시된 이벤트 수")
inventory_failed_total = Counter("inventory_failed_total", "재고 부족 등으로 실패한 건수")
inventory_processing_duration_seconds = Histogram("inventory_processing_duration_seconds", "이벤트 처리 시간")


def get_conn():
    return pymysql.connect(
        host=DB_HOST, port=DB_PORT, db=DB_NAME,
        user=DB_USER, password=DB_PASSWORD, autocommit=False,
    )


def already_processed(conn, event_id):
    with conn.cursor() as cur:
        cur.execute("SELECT 1 FROM processed_events WHERE event_id = %s", (event_id,))
        return cur.fetchone() is not None


def handle_event(conn, event):
    event_id = event["event_id"]
    product_id = event["product_id"]
    quantity = event["quantity"]

    if already_processed(conn, event_id):
        inventory_duplicate_events_total.inc()
        return

    with conn.cursor() as cur:
        # 재고가 충분할 때만 차감 (조건부 UPDATE로 동시성 처리)
        cur.execute(
            "UPDATE master_inventory SET stock = stock - %s WHERE product_id = %s AND stock >= %s",
            (quantity, product_id, quantity),
        )
        if cur.rowcount == 1:
            result = "SUCCESS"
            inventory_processed_total.inc()
        else:
            result = "OUT_OF_STOCK"
            inventory_failed_total.inc()

        cur.execute(
            "INSERT INTO processed_events (event_id, result) VALUES (%s, %s)",
            (event_id, result),
        )
    conn.commit()
    print(f"[inventory-worker] event_id={event_id} product_id={product_id} qty={quantity} result={result}")


def get_stream_iterator():
    stream = kinesis.describe_stream(StreamName=KINESIS_STREAM_NAME)
    shard_id = stream["StreamDescription"]["Shards"][0]["ShardId"]
    resp = kinesis.get_shard_iterator(
        StreamName=KINESIS_STREAM_NAME,
        ShardId=shard_id,
        ShardIteratorType="LATEST",
    )
    return resp["ShardIterator"]


def main():
    start_http_server(METRICS_PORT)
    print(f"[inventory-worker] metrics on :{METRICS_PORT}, stream={KINESIS_STREAM_NAME}")

    shard_iterator = get_stream_iterator()
    while True:
        resp = kinesis.get_records(ShardIterator=shard_iterator, Limit=50)
        shard_iterator = resp["NextShardIterator"]

        for record in resp["Records"]:
            start = time.time()
            event = json.loads(record["Data"])
            conn = get_conn()
            try:
                handle_event(conn, event)
            except Exception as e:
                conn.rollback()
                print(f"[inventory-worker] error processing event: {e}")
            finally:
                conn.close()
                inventory_processing_duration_seconds.observe(time.time() - start)

        if not resp["Records"]:
            time.sleep(1)  # 새 레코드 없으면 잠깐 대기


if __name__ == "__main__":
    main()
