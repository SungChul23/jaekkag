# Kinesis 연결 전이므로 우선 DB 환경변수와 실행 구조만 확인하도록
# RDS가 실제로 생성되지 않았거나 보안그룹이 열리지 않았으면 시작할떄 종료됨
import logging
import os
import time
import json
from pathlib import Path

from app.database import get_db_connection
from app.worker import process_order_event

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s - %(message)s",
)

logger = logging.getLogger("inventory-worker")


def check_database() -> None:
    connection = get_db_connection()

    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1 AS result")
            result = cursor.fetchone()

        logger.info("RDS 연결 확인 성공: %s", result)

    finally:
        connection.close()


def wait_for_database() -> None:
    while True:
        try:
            check_database()
            return

        except Exception:
            logger.exception("RDS 연결 실패, 10초 후 재시도")
            time.sleep(10)

def load_sample_event() -> dict:
    project_root = Path(__file__).resolve().parent.parent
    event_path = project_root / "tests" / "sample_event.json"

    with event_path.open("r", encoding="utf-8") as file:
        return json.load(file)


def main() -> None:
    logger.info("Inventory Worker 시작")

    wait_for_database()

    while True:
        logger.info("Kinesis 이벤트 대기 중")
        time.sleep(30)
        
def main() -> None:
    event = load_sample_event()

    result = process_order_event(event)

    print(f"이벤트 처리 결과: {result}")

if __name__ == "__main__":
    main()