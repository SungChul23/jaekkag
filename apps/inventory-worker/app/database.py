import os

import pymysql
from pymysql.connections import Connection


def get_required_env(name: str) -> str:
    """필수 환경변수를 읽는다."""

    value = os.getenv(name)

    if value is None or value.strip() == "":
        raise RuntimeError(f"필수 환경변수가 없습니다: {name}")

    return value


def get_db_connection() -> Connection:
    """환경변수에 설정된 RDS MySQL에 연결한다."""

    return pymysql.connect(
        host=get_required_env("DB_HOST"),
        port=int(get_required_env("DB_PORT")),
        user=get_required_env("DB_USER"),
        password=get_required_env("DB_PASSWORD"),
        database=get_required_env("DB_NAME"),
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=False,
        connect_timeout=10,
        read_timeout=10,
        write_timeout=10,
    )