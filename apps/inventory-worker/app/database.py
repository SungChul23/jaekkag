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


_conn: Connection | None = None


def get_connection() -> Connection:
    """Pod당 커넥션 1개를 계속 재사용한다.
    Kinesis shard 하나를 순차 소비하는 구조라 동시성이 없으므로
    풀이 아니라 커넥션 1개 재사용으로 충분하다.
    죽은 커넥션이면 ping(reconnect=True)이 자동으로 다시 연결한다."""
    global _conn
    if _conn is None:
        _conn = get_db_connection()
        return _conn

    try:
        _conn.ping(reconnect=True)
    except pymysql.MySQLError:
        _conn = get_db_connection()

    return _conn
