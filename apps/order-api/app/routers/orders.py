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
from app.models import (
    Order,
    OrderStatus,
    OutboxEvent,
    PublishStatus,
)
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

        # 1. 주문 생성
        order = Order(
            product_id=product_id,
            quantity=order_request.quantity,
            order_status=OrderStatus.CREATED,
        )

        db.add(order)

        # order_id를 먼저 생성하기 위해 flush
        # 아직 commit은 하지 않음
        db.flush()

        # 2. Outbox Event 생성
        outbox_event = OutboxEvent(
            event_id=str(uuid4()),
            event_type="ORDER_CREATED",
            order_id=order.order_id,
            product_id=product_id,
            quantity=order_request.quantity,
            publish_status=PublishStatus.PENDING,
        )

        db.add(outbox_event)

        # 3. Order + Outbox Event를 하나의 Transaction으로 저장
        db.commit()
        db.refresh(order)

        ORDER_SUCCESS_TOTAL.inc()

        return OrderCreateResponse(
            order_id=order.order_id,
            status=order.order_status.value,
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