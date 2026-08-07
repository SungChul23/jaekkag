import enum

from sqlalchemy import (
    BigInteger,
    Column,
    DateTime,
    Enum,
    Index,
    Integer,
    String,
    Text,
)
from sqlalchemy.sql import func

from app.database import Base


# =====================================================
# Order
# =====================================================

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

    order_status = Column(
        Enum(
            OrderStatus,
            name="order_status_enum",
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
        onupdate=func.now(),
    )

    __table_args__ = (
        Index("idx_product_id", "product_id"),
        Index("idx_created_at", "created_at"),
    )


# =====================================================
# Outbox Event
# =====================================================

class PublishStatus(str, enum.Enum):
    PENDING = "PENDING"
    PUBLISHED = "PUBLISHED"
    FAILED = "FAILED"


class OutboxEvent(Base):
    __tablename__ = "outbox_events"

    id = Column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
    )

    event_id = Column(
        String(36),
        nullable=False,
        unique=True,
    )

    event_type = Column(
        String(50),
        nullable=False,
    )

    order_id = Column(
        BigInteger,
        nullable=False,
    )

    product_id = Column(
        String(10),
        nullable=False,
    )

    quantity = Column(
        Integer,
        nullable=False,
    )

    publish_status = Column(
        Enum(
            PublishStatus,
            name="publish_status_enum",
        ),
        nullable=False,
        default=PublishStatus.PENDING,
        server_default=PublishStatus.PENDING.value,
    )

    retry_count = Column(
        Integer,
        nullable=False,
        default=0,
        server_default="0",
    )

    last_error = Column(
        Text,
        nullable=True,
    )

    created_at = Column(
        DateTime,
        nullable=False,
        server_default=func.now(),
    )

    published_at = Column(
        DateTime,
        nullable=True,
    )

    __table_args__ = (
        Index(
            "idx_status_created",
            "publish_status",
            "created_at",
        ),
    )