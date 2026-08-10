import os

from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker


load_dotenv()

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "3306")
DB_NAME = os.getenv("DB_NAME", "ecommerce")
DB_USER = os.getenv("DB_USER", "root")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")

DATABASE_URL = (
    f"mysql+pymysql://{DB_USER}:{DB_PASSWORD}"
    f"@{DB_HOST}:{DB_PORT}/{DB_NAME}"
    "?charset=utf8mb4"
)

engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
    pool_size=10,       # RDS db.t3.small 기준 여유 반영 (기존 SQLAlchemy 기본값 5)
    max_overflow=15,    # 기존 기본값 10 -> pod당 최대 25개
    pool_timeout=30,
    pool_recycle=1800,
)

SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine,
)

Base = declarative_base()


def get_db():
    db = SessionLocal()

    try:
        yield db
    finally:
        db.close()