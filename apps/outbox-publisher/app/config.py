import os

DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = int(os.environ.get("DB_PORT", "3306"))
DB_NAME = os.environ.get("DB_NAME", "ecommerce")
DB_USER = os.environ.get("DB_USER", "appuser")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")

KINESIS_STREAM_NAME = os.environ.get("KINESIS_STREAM_NAME", "ecommerce-order-events")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

METRICS_PORT = int(os.environ.get("METRICS_PORT", "8001"))
POLL_INTERVAL_SEC = float(os.environ.get("POLL_INTERVAL_SEC", "1"))
BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "500"))
MAX_RETRY_COUNT = int(os.environ.get("MAX_RETRY_COUNT", "5"))