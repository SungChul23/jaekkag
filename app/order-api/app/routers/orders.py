from datetime import datetime, timezone
from time import perf_counter
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.database import get_db
from app.metrics import (
    ORDER_FAILURE_TOTAL,
    ORDER_REQUEST_DURATION_SECONDS,
    ORDER_REQUESTS_TOTAL,
    ORDER_SUCCESS_TOTAL,
)
from app.models import Order, OrderStatus, OutboxEvent
from app.schemas import OrderCreateRequest, OrderCreateResponse


router = APIRouter()


@router.post(
    "/orders",
    response_model=OrderCreateResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_order(
    order_request: OrderCreateRequest,
    db: Session = Depends(get_db),
):
    ORDER_REQUESTS_TOTAL.inc()
    started_at = perf_counter()

    try:
        product_id = order_request.product_id.value

        order = Order(
            product_id=product_id,
            quantity=order_request.quantity,
            status=OrderStatus.CREATED,
        )

        db.add(order)
        db.flush()

        created_at = datetime.now(timezone.utc)
        event_id = str(uuid4())

        event_payload = {
            "event_id": event_id,
            "event_type": "ORDER_CREATED",
            "order_id": order.order_id,
            "product_id": product_id,
            "quantity": order_request.quantity,
            "created_at": created_at.isoformat().replace("+00:00", "Z"),
        }

        outbox_event = OutboxEvent(
            event_id=event_id,
            aggregate_id=order.order_id,
            event_type="ORDER_CREATED",
            payload=event_payload,
            status="PENDING",
        )

        db.add(outbox_event)
        db.commit()
        db.refresh(order)

        ORDER_SUCCESS_TOTAL.inc()

        return OrderCreateResponse(
            order_id=order.order_id,
            status=order.status.value,
        )

    except SQLAlchemyError as exc:
        db.rollback()
        ORDER_FAILURE_TOTAL.inc()

        print(f"Database error: {exc}")

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create order",
        ) from exc

    finally:
        ORDER_REQUEST_DURATION_SECONDS.observe(
            perf_counter() - started_at
        )