# Kinesis 연결 전 대기 상태, 주문처리 X 상태
import logging
import os
import time

from prometheus_client import start_http_server

from app.database import get_db_connection


logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s - %(message)s",
)

logger = logging.getLogger("inventory-worker")


def check_database() -> None:
    """
    RDS에 접속한 뒤 간단한 SELECT 문으로
    연결이 정상인지 확인한다.
    """
    connection = get_db_connection()

    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1 AS result")
            result = cursor.fetchone()

        logger.info("RDS 연결 확인 성공: %s", result)

    finally:
        connection.close()


def wait_for_database() -> None:
    """
    RDS 연결에 실패하면 Worker를 바로 종료하지 않고
    10초마다 다시 연결을 시도한다.
    """
    while True:
        try:
            check_database()
            return

        except Exception:
            logger.exception("RDS 연결 실패, 10초 후 재시도")
            time.sleep(10)


def main() -> None:
    logger.info("Inventory Worker 시작")

    metrics_port = int(os.getenv("METRICS_PORT", "8002"))
    start_http_server(metrics_port)
    logger.info("Prometheus metrics server started on port %s", metrics_port)

    wait_for_database()

    while True:
        logger.info("Kinesis 연결 전 대기 상태")
        time.sleep(30)


if __name__ == "__main__":
    main()
