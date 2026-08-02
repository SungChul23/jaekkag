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

# 초기화 함수 추가
def initialize_database() -> None:
    """Inventory Worker에서 사용할 테이블과 샘플 재고를 생성한다."""

    schema_path = BASE_DIR / "app" / "schema.sql"
    sql_text = schema_path.read_text(encoding="utf-8")

    statements = [
        statement.strip()
        for statement in sql_text.split(";")
        if statement.strip()
    ]

    connection = get_db_connection()

    try:
        with connection.cursor() as cursor:
            for statement in statements:
                cursor.execute(statement)

        connection.commit()

    except Exception:
        connection.rollback()
        raise

    finally:
        connection.close()