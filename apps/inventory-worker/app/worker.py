##############################################
# 잘못된 이벤트 검열(재고처리 단계로 들어가지 않도록)
##############################################
from datetime import datetime
from typing import Any
from uuid import UUID


REQUIRED_FIELDS = {
    "event_id",
    "event_type",
    "order_id",
    "product_id",
    "quantity",
    "created_at",
}


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