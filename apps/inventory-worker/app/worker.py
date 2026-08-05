from datetime import datetime
from typing import Any
from uuid import UUID
from app.database import get_db_connection


REQUIRED_FIELDS = {
    "event_id",
    "event_type",
    "order_id",
    "product_id",
    "model_name",
    "color_name",
    "quantity",
    "created_at",
}

VALID_MODEL_NAMES = {"FOLD", "FLIP", "ULTRA"}
VALID_COLOR_NAMES = {"BLACK", "WHITE", "LAVENDER", "GRAY"}

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

    if type(event["product_id"]) is not int:
        raise ValueError("product_id는 정수여야 합니다.")

    if (
        not isinstance(event["model_name"], str)
        or event["model_name"] not in VALID_MODEL_NAMES
    ):
        raise ValueError("지원하지 않는 model_name입니다.")

    if (
        not isinstance(event["color_name"], str)
        or event["color_name"] not in VALID_COLOR_NAMES
    ):
        raise ValueError("지원하지 않는 color_name입니다.")

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

    validate_order_event(event)

    event_id = event["event_id"]
    order_id = event["order_id"]
    product_id = event["product_id"]
    model_name = event["model_name"]
    color_name = event["color_name"]
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

            # 2. 상품 존재 여부와 모델·색상 조합 확인
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
                result = "FAILED"
                error_message = "존재하지 않는 상품입니다."
            elif (
                inventory["model_name"] != model_name
                or inventory["color_name"] != color_name
            ):
                result = "FAILED"
                error_message = "상품의 모델 또는 색상 정보가 일치하지 않습니다."
            else:
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
        return result

    except Exception:
        connection.rollback()
        raise

    finally:
        connection.close()
