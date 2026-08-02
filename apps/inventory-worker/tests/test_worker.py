import unittest

from app.worker import validate_order_event


class TestValidateOrderEvent(unittest.TestCase):

    def setUp(self) -> None:
        """각 테스트에서 사용할 정상 주문 이벤트."""

        self.valid_event = {
            "event_id": "550e8400-e29b-41d4-a716-446655440000",
            "event_type": "ORDER_CREATED",
            "order_id": 1001,
            "product_id": 10,
            "quantity": 2,
            "created_at": "2026-08-05T09:00:00Z",
        }

    def test_valid_event(self) -> None:
        """정상 이벤트는 오류 없이 검증을 통과한다."""

        validate_order_event(self.valid_event)

    def test_missing_field(self) -> None:
        """필수 필드가 없으면 오류가 발생한다."""

        del self.valid_event["product_id"]

        with self.assertRaises(ValueError):
            validate_order_event(self.valid_event)

    def test_invalid_event_id(self) -> None:
        """event_id가 UUID 형식이 아니면 오류가 발생한다."""

        self.valid_event["event_id"] = "invalid-id"

        with self.assertRaises(ValueError):
            validate_order_event(self.valid_event)

    def test_invalid_event_type(self) -> None:
        """ORDER_CREATED가 아닌 이벤트는 거절한다."""

        self.valid_event["event_type"] = "ORDER_CANCELLED"

        with self.assertRaises(ValueError):
            validate_order_event(self.valid_event)

    def test_invalid_quantity(self) -> None:
        """주문 수량이 0 이하면 오류가 발생한다."""

        self.valid_event["quantity"] = 0

        with self.assertRaises(ValueError):
            validate_order_event(self.valid_event)


if __name__ == "__main__":
    unittest.main()