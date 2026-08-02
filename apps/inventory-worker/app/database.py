import os
from pathlib import Path

import pymysql
from dotenv import load_dotenv
from pymysql.connections import Connection


# database.py의 상위 폴더인 inventory-worker/.env를 명시적으로 읽는다.
BASE_DIR = Path(__file__).resolve().parent.parent
ENV_PATH = BASE_DIR / ".env"

load_dotenv(dotenv_path=ENV_PATH)


def get_required_env(name: str) -> str:
    """필수 환경변수를 읽고, 없으면 오류를 발생시킨다."""

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