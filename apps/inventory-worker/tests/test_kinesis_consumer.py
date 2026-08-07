# Kinesis 형식의 데이터를 원래 주문 이벤트로 복원하는지 확인하는 테스트
import json

from app.kinesis_consumer import decode_kinesis_record


def test_decode_kinesis_record() -> None:
    # 가짜 주문 이벤트 원본
    original_event = {
        "event_id": "770e8400-e29b-41d4-a716-446655440002",
        "event_type": "ORDER_CREATED",
        "order_id": 1003,
        "product_id": "101",
        "quantity": 2,
        "created_at": "2026-08-04T09:30:00",
    }

    # 실제 Kinesis에서 받았다고 가정한 가짜 레코드
    fake_kinesis_record = {
        # dict → JSON, 문자열 → bytes
        "Data": json.dumps(original_event).encode("utf-8"),
        "PartitionKey": "1003",
        "SequenceNumber": "123456789",
    }
    # 변환 함수 실행
    decoded_event = decode_kinesis_record(fake_kinesis_record)
    # 원본과 같은지 비교
    assert decoded_event == original_event


# Mocking) RDS의 원본 재고를 건드리지 않고 테스트 진행
"""
1. 가짜 Kinesis 레코드가 주문 이벤트로 정상 변환되는지 확인
2. 변환된 이벤트가 process_order_event()에 정확히 전달되는지 확인
"""

from unittest.mock import patch
from app.kinesis_consumer import process_kinesis_record


def test_process_kinesis_record() -> None:
    original_event = {
        "event_id": "880e8400-e29b-41d4-a716-446655440003",
        "event_type": "ORDER_CREATED",
        "order_id": 1004,
        "product_id": "101",
        "quantity": 1,
        "created_at": "2026-08-04T10:30:00",
    }

    fake_kinesis_record = {
        "Data": json.dumps(original_event).encode("utf-8"),
        "PartitionKey": "1004",
        "SequenceNumber": "987654321",
    }

    with patch(
        "app.kinesis_consumer.process_order_event",
        return_value="SUCCESS",
    ) as mock_process_order_event:

        result = process_kinesis_record(fake_kinesis_record)

    assert result == "SUCCESS"
    mock_process_order_event.assert_called_once_with(original_event)
