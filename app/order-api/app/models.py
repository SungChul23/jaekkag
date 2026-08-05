import enum

from sqlalchemy import (
    BigInteger,
    Column,
    DateTime,
    Enum,
    Integer,
    JSON,
    String,
)
from sqlalchemy.sql import func

from app.database import Base


class OrderStatus(str, enum.Enum):
    CREATED = "CREATED"
    CONFIRMED = "CONFIRMED"
    CANCELLED = "CANCELLED"


class Order(Base):
    __tablename__ = "orders"

    order_id = Column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
    )

    product_id = Column(
        String(10),
        nullable=False,
    )

    quantity = Column(
        Integer,
        nullable=False,
    )

    status = Column(
        Enum(
            OrderStatus,
            name="order_status",
        ),
        nullable=False,
        default=OrderStatus.CREATED,
        server_default=OrderStatus.CREATED.value,
    )

    created_at = Column(
        DateTime,
        nullable=False,
        server_default=func.now(),
    )

    updated_at = Column(
        DateTime,
        nullable=False,
        server_default=func.now(),
        server_onupdate=func.now(),
        onupdate=func.now(),
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
        server_default="PENDING",
    )

    created_at = Column(
        DateTime,
        nullable=False,
        server_default=func.now(),
    )