import time

from prometheus_client import start_http_server

from app.config import METRICS_PORT, POLL_INTERVAL_SEC, KINESIS_STREAM_NAME
from app.database import get_conn
from app.metrics import update_gauges
from app.publisher import process_batch


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