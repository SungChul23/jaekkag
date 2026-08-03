from sqlalchemy import BigInteger, Column, DateTime, Integer, JSON, String
from sqlalchemy.sql import func

from app.database import Base


class Order(Base):
    __tablename__ = "orders"

    order_id = Column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
    )
    product_id = Column(
        BigInteger,
        nullable=False,
    )
    quantity = Column(
        Integer,
        nullable=False,
    )
    status = Column(
        String(20),
        nullable=False,
        default="RECEIVED",
    )
    created_at = Column(
        DateTime,
        nullable=False,
        server_default=func.now(),
    )


class OutboxEvent(Base):
    __tablename__ = "outbox_events"

    event_id = Column(
        String(36),
        primary_key=True,
    )
    aggregate_id = Column(
        BigInteger,
        nullable=False,
    )
    event_type = Column(
        String(50),
        nullable=False,
    )
    payload = Column(
        JSON,
        nullable=False,
    )
    status = Column(
        String(20),
        nullable=False,
        default="PENDING",
    )
    created_at = Column(
        DateTime,
        nullable=False,
        server_default=func.now(),
    )