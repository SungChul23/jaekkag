import time

from prometheus_client import start_http_server

from app.config import METRICS_PORT, POLL_INTERVAL_SEC, KINESIS_STREAM_NAME
from app.database import get_connection
from app.metrics import update_gauges
from app.publisher import process_batch


def main():
    start_http_server(METRICS_PORT)
    print(f"[outbox-publisher] metrics on :{METRICS_PORT}, stream={KINESIS_STREAM_NAME}", flush=True)

    while True:
        conn = get_connection()
        try:
            update_gauges(conn)
            process_batch(conn)
        except Exception as e:
            # update_gauges는 커밋을 하지 않으므로, 여기서 롤백하지 않으면
            # 커넥션을 재사용하는 다음 루프까지 트랜잭션이 열린 채로 남는다.
            conn.rollback()
            print(f"[outbox-publisher] loop error, rolled back: {e}", flush=True)
        time.sleep(POLL_INTERVAL_SEC)


if __name__ == "__main__":
    main()