import pymysql
from pymysql.connections import Connection

from app.config import DB_HOST, DB_NAME, DB_PASSWORD, DB_PORT, DB_USER


def get_required_config(name: str, value: str) -> str:
    """필수 설정값을 확인하고, 없으면 오류를 발생시킨다."""

    if value is None or value.strip() == "":
        raise RuntimeError(f"필수 환경변수가 없습니다: {name}")

    return value


def get_db_connection() -> Connection:
    """환경변수에 설정된 RDS MySQL에 연결한다."""

    return pymysql.connect(
        host=get_required_config("DB_HOST", DB_HOST),
        port=DB_PORT,
        user=get_required_config("DB_USER", DB_USER),
        password=get_required_config("DB_PASSWORD", DB_PASSWORD),
        database=get_required_config("DB_NAME", DB_NAME),
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=False,
        connect_timeout=10,
        read_timeout=10,
        write_timeout=10,
    )
