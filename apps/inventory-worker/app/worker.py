from datetime import datetime
from typing import Any
from uuid import UUID
from app.database import get_db_connection


REQUIRED_FIELDS = {
    "event_id",
    "event_type",
    "order_id",
    "product_id",
    "quantity",
    "created_at",
}

##############################################
# 잘못된 이벤트 검열(재고처리 단계로 들어가지 않도록)
##############################################
def validate_order_event(event: dict[str, Any]) -> None:
    """주문 이벤트가 팀 공통 규격을 따르는지 검사한다."""

    missing_fields = REQUIRED_FIELDS - event.keys()

    if missing_fields:
        missing = ", ".join(sorted(missing_fields))
        raise ValueError(f"필수 필드가 없습니다: {missing}")

    try:
        UUID(str(event["event_id"]))
    except (ValueError, TypeError, AttributeError) as error:
        raise ValueError("event_id는 UUID 문자열이어야 합니다.") from error

    if event["event_type"] != "ORDER_CREATED":
        raise ValueError("지원하지 않는 event_type입니다.")

    if not isinstance(event["order_id"], int):
        raise ValueError("order_id는 정수여야 합니다.")

    if not isinstance(event["product_id"], int):
        raise ValueError("product_id는 정수여야 합니다.")

    if not isinstance(event["quantity"], int) or event["quantity"] <= 0:
        raise ValueError("quantity는 1 이상의 정수여야 합니다.")

    try:
        datetime.fromisoformat(
            str(event["created_at"]).replace("Z", "+00:00")
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
                return "DUPLICATE"

            # 2. 재고가 충분한 경우에만 차감
            cursor.execute(
                """
                UPDATE master_inventory
                SET quantity = quantity - %s,
                    updated_at = CURRENT_TIMESTAMP
                WHERE product_id = %s
                  AND quantity >= %s
                """,
                (
                    order_quantity,
                    product_id,
                    order_quantity,
                ),
            )

            # UPDATE된 행 개수 확인
            if cursor.rowcount == 1:
                result = "SUCCESS"
            else:
                result = "OUT_OF_STOCK"

            # 3. 처리 결과 저장
            cursor.execute(
                """
                INSERT INTO processed_events (
                    event_id,
                    order_id,
                    result,
                    processed_at
                )
                VALUES (%s, %s, %s, CURRENT_TIMESTAMP)
                """,
                (
                    event_id,
                    order_id,
                    result,
                ),
            )

        connection.commit()
        return result

    except Exception:
        connection.rollback()
        raise

    finally:
        connection.close()