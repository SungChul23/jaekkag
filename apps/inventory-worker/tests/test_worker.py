import unittest
from unittest.mock import MagicMock, patch

from app.worker import process_order_event, validate_order_event


class TestValidateOrderEvent(unittest.TestCase):

    def setUp(self) -> None:
        """각 테스트에서 사용할 정상 주문 이벤트."""

        self.valid_event = {
            "event_id": "550e8400-e29b-41d4-a716-446655440000",
            "event_type": "ORDER_CREATED",
            "order_id": 1001,
            "product_id": 101,
            "model_name": "FOLD",
            "color_name": "BLACK",
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

    def test_invalid_model_name(self) -> None:
        self.valid_event["model_name"] = "INVALID"

        with self.assertRaises(ValueError):
            validate_order_event(self.valid_event)

    def test_invalid_color_name(self) -> None:
        self.valid_event["color_name"] = "INVALID"

        with self.assertRaises(ValueError):
            validate_order_event(self.valid_event)

    def test_invalid_type_is_rejected_before_db_access(self) -> None:
        self.valid_event["quantity"] = True

        with patch("app.worker.get_db_connection") as mock_connection:
            with self.assertRaises(ValueError):
                process_order_event(self.valid_event)

        mock_connection.assert_not_called()


class TestProcessOrderEvent(unittest.TestCase):

    def setUp(self) -> None:
        self.valid_event = {
            "event_id": "550e8400-e29b-41d4-a716-446655440000",
            "event_type": "ORDER_CREATED",
            "order_id": 1001,
            "product_id": 101,
            "model_name": "FOLD",
            "color_name": "BLACK",
            "quantity": 2,
            "created_at": "2026-08-05T09:00:00Z",
        }

        self.connection = MagicMock()
        self.cursor = self.connection.cursor.return_value.__enter__.return_value

    def process_event(self) -> str:
        with patch(
            "app.worker.get_db_connection",
            return_value=self.connection,
        ):
            return process_order_event(self.valid_event)

    def test_success(self) -> None:
        self.cursor.fetchone.side_effect = [
            None,
            {"model_name": "FOLD", "color_name": "BLACK"},
        ]
        self.cursor.rowcount = 1

        result = self.process_event()

        self.assertEqual(result, "SUCCESS")
        self.connection.commit.assert_called_once_with()
        self.connection.rollback.assert_not_called()
        self.connection.close.assert_called_once_with()

    def test_duplicate_event(self) -> None:
        self.cursor.fetchone.return_value = {"event_id": self.valid_event["event_id"]}

        result = self.process_event()

        self.assertEqual(result, "DUPLICATE")
        self.connection.rollback.assert_called_once_with()
        self.connection.commit.assert_not_called()
        self.connection.close.assert_called_once_with()

    def test_out_of_stock(self) -> None:
        self.cursor.fetchone.side_effect = [
            None,
            {"model_name": "FOLD", "color_name": "BLACK"},
        ]
        self.cursor.rowcount = 0

        result = self.process_event()

        self.assertEqual(result, "OUT_OF_STOCK")
        self.assertEqual(
            self.cursor.execute.call_args_list[-1].args[1][-2:],
            ("OUT_OF_STOCK", "재고가 부족합니다."),
        )
        self.connection.commit.assert_called_once_with()

    def test_missing_product_is_recorded_as_failed(self) -> None:
        self.cursor.fetchone.side_effect = [None, None]

        result = self.process_event()

        self.assertEqual(result, "FAILED")
        self.assertEqual(
            self.cursor.execute.call_args_list[-1].args[1][-2:],
            ("FAILED", "존재하지 않는 상품입니다."),
        )
        self.connection.commit.assert_called_once_with()

    def test_product_details_mismatch_is_recorded_as_failed(self) -> None:
        self.cursor.fetchone.side_effect = [
            None,
            {"model_name": "FLIP", "color_name": "WHITE"},
        ]

        result = self.process_event()

        self.assertEqual(result, "FAILED")
        self.assertEqual(
            self.cursor.execute.call_args_list[-1].args[1][-2:],
            ("FAILED", "상품의 모델 또는 색상 정보가 일치하지 않습니다."),
        )
        self.connection.commit.assert_called_once_with()

    def test_database_error_is_rolled_back_and_raised(self) -> None:
        self.cursor.execute.side_effect = RuntimeError("database error")

        with self.assertRaises(RuntimeError):
            self.process_event()

        self.connection.rollback.assert_called_once_with()
        self.connection.commit.assert_not_called()
        self.connection.close.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
