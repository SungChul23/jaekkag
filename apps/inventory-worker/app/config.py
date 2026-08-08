import os
from pathlib import Path

from dotenv import load_dotenv


# 로컬 실행에서는 inventory-worker/.env를 사용한다.
# EKS에서는 파일이 없으므로 ConfigMap과 Secret이 주입한 환경변수를 사용한다.
BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(dotenv_path=BASE_DIR / ".env")


DB_HOST = os.environ.get("DB_HOST", "")
DB_PORT = int(os.environ.get("DB_PORT", "3306"))
DB_NAME = os.environ.get("DB_NAME", "ecommerce")
DB_USER = os.environ.get("DB_USER", "")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")

AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
KINESIS_STREAM_NAME = os.environ.get(
    "KINESIS_STREAM_NAME",
    "ecommerce-order-events",
)
KINESIS_ITERATOR_TYPE = os.environ.get("KINESIS_ITERATOR_TYPE", "TRIM_HORIZON")
KINESIS_RECORDS_LIMIT = int(os.environ.get("KINESIS_RECORDS_LIMIT", "1000"))
KINESIS_POLL_INTERVAL_SEC = float(
    os.environ.get("KINESIS_POLL_INTERVAL_SEC", "0.2")
)
KINESIS_MAX_RETRY_ATTEMPTS = int(
    os.environ.get("KINESIS_MAX_RETRY_ATTEMPTS", "5")
)
KINESIS_RETRY_BASE_SEC = float(os.environ.get("KINESIS_RETRY_BASE_SEC", "1"))
KINESIS_RETRY_MAX_SEC = float(os.environ.get("KINESIS_RETRY_MAX_SEC", "10"))

# 로컬에서는 SHARD_INDEX를 사용하고 EKS에서는 StatefulSet Pod 이름을 사용한다.
SHARD_INDEX = os.environ.get("SHARD_INDEX")
POD_NAME = os.environ.get("POD_NAME")

LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")
METRICS_PORT = int(os.environ.get("METRICS_PORT", "8002"))
