from datetime import datetime
from typing import Any
from uuid import UUID
from app.database import get_db_connection
from app.metrics import (
    inventory_duplicate_events_total,
    inventory_out_of_stock_total,
    inventory_processed_total,
    inventory_processing_duration_seconds,
)


REQUIRED_FIELDS = {
    "event_id",
    "event_type",
    "order_id",
    "product_id",
    "quantity",
    "created_at",
}

##############################################
# 잘못된 이벤트 검증(재고 처리 단계로 들어가지 않도록)
##############################################
def validate_order_event(event: dict[str, Any]) -> None:
    """주문 이벤트가 팀 공통 규격을 따르는지 검사한다."""

    missing_fields = REQUIRED_FIELDS - event.keys()

    if missing_fields:
        missing = ", ".join(sorted(missing_fields))
        raise ValueError(f"필수 필드가 없습니다: {missing}")

    if not isinstance(event["event_id"], str):
        raise ValueError("event_id는 UUID 문자열이어야 합니다.")

    try:
        UUID(event["event_id"])
    except (ValueError, TypeError, AttributeError) as error:
        raise ValueError("event_id는 UUID 문자열이어야 합니다.") from error

    if event["event_type"] != "ORDER_CREATED":
        raise ValueError("지원하지 않는 event_type입니다.")

    if type(event["order_id"]) is not int:
        raise ValueError("order_id는 정수여야 합니다.")

    if (
        not isinstance(event["product_id"], str)
        or not event["product_id"]
        or len(event["product_id"]) > 10
    ):
        raise ValueError("product_id는 1~10자의 문자열이어야 합니다.")

    if type(event["quantity"]) is not int or event["quantity"] <= 0:
        raise ValueError("quantity는 1 이상의 정수여야 합니다.")

    if not isinstance(event["created_at"], str):
        raise ValueError("created_at은 ISO 8601 문자열이어야 합니다.")

    try:
        datetime.fromisoformat(
            event["created_at"].replace("Z", "+00:00")
        )
    except ValueError as error:
        raise ValueError(
            "created_at은 ISO 8601 형식이어야 합니다."
        ) from error

##############################################
# 중복 확인 및 조건부 재고 차감
##############################################
def process_order_event(event: dict[str, Any]) -> str:
    """주문 이벤트를 처리하고 재고를 차감한다."""

    with inventory_processing_duration_seconds.time():
        return _process_order_event(event)


def _process_order_event(event: dict[str, Any]) -> str:
    validate_order_event(event)

    event_id = event["event_id"]
    order_id = event["order_id"]
    product_id = event["product_id"]
    order_quantity = event["quantity"]

    connection = get_db_connection()

    try:
        with connection.cursor() as cursor:
            # 1. 이미 처리한 이벤트인지 확인
            cursor.execute(
                """
                SELECT event_id
                FROM processed_events
                WHERE event_id = %s
                """,
                (event_id,),
            )

            existing_event = cursor.fetchone()

            if existing_event:
                connection.rollback()
                inventory_duplicate_events_total.inc()
                return "DUPLICATE"

            # 2. product_id를 기준으로 상품 정보 조회
            cursor.execute(
                """
                SELECT model_name, color_name
                FROM master_inventory
                WHERE product_id = %s
                """,
                (product_id,),
            )

            inventory = cursor.fetchone()

            if inventory is None:
                raise ValueError(
                    f"존재하지 않는 product_id입니다: {product_id}"
                )

            model_name = inventory["model_name"]
            color_name = inventory["color_name"]

            # 3. 재고가 충분한 경우에만 차감
            cursor.execute(
                """
                UPDATE master_inventory
                SET
                    stock_quantity = stock_quantity - %s,
                    updated_at = CURRENT_TIMESTAMP(6)
                WHERE product_id = %s
                  AND stock_quantity >= %s
                """,
                (
                    order_quantity,
                    product_id,
                    order_quantity,
                ),
            )

            if cursor.rowcount == 1:
                result = "SUCCESS"
                error_message = None
            else:
                result = "OUT_OF_STOCK"
                error_message = "재고가 부족합니다."

            # 4. 처리 결과 저장
            cursor.execute(
                """
                INSERT INTO processed_events (
                    event_id,
                    order_id,
                    product_id,
                    model_name,
                    color_name,
                    quantity,
                    process_status,
                    error_message
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    event_id,
                    order_id,
                    product_id,
                    model_name,
                    color_name,
                    order_quantity,
                    result,
                    error_message,
                ),
            )

        connection.commit()

        if result == "SUCCESS":
            inventory_processed_total.inc()
        elif result == "OUT_OF_STOCK":
            inventory_out_of_stock_total.inc()

        return result

    except Exception:
        connection.rollback()
        raise

    finally:
        connection.close()
