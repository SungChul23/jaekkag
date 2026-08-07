# Kinesis 형식의 데이터를 원래 주문 이벤트로 복원하는지 확인하는 테스트
import json
from unittest.mock import MagicMock, call, patch

from app.kinesis_consumer import (
    create_shard_iterators,
    decode_kinesis_record,
    list_shard_ids,
    poll_shards_once,
)


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


def test_list_shard_ids_reads_all_pages() -> None:
    client = MagicMock()
    client.list_shards.side_effect = [
        {
            "Shards": [{"ShardId": "shard-000"}, {"ShardId": "shard-001"}],
            "NextToken": "next-page",
        },
        {"Shards": [{"ShardId": "shard-002"}]},
    ]

    result = list_shard_ids(client, "ecommerce-order-events")

    assert result == ["shard-000", "shard-001", "shard-002"]
    assert client.list_shards.call_args_list == [
        call(StreamName="ecommerce-order-events"),
        call(NextToken="next-page"),
    ]


def test_list_shard_ids_rejects_empty_stream() -> None:
    client = MagicMock()
    client.list_shards.return_value = {"Shards": []}

    try:
        list_shard_ids(client, "empty-stream")
    except RuntimeError as error:
        assert "empty-stream" in str(error)
    else:
        raise AssertionError("RuntimeError가 발생해야 합니다.")


def test_create_shard_iterators_for_every_shard() -> None:
    client = MagicMock()
    client.get_shard_iterator.side_effect = [
        {"ShardIterator": "iterator-0"},
        {"ShardIterator": "iterator-1"},
        {"ShardIterator": "iterator-2"},
    ]

    result = create_shard_iterators(
        client,
        "ecommerce-order-events",
        ["shard-000", "shard-001", "shard-002"],
        "TRIM_HORIZON",
    )

    assert result == {
        "shard-000": "iterator-0",
        "shard-001": "iterator-1",
        "shard-002": "iterator-2",
    }
    assert client.get_shard_iterator.call_count == 3


def test_poll_shards_once_processes_records_and_updates_iterators() -> None:
    client = MagicMock()
    client.get_records.side_effect = [
        {
            "Records": [{"Data": b"first"}],
            "NextShardIterator": "next-0",
            "MillisBehindLatest": 120,
        },
        {
            "Records": [{"Data": b"second"}, {"Data": b"third"}],
            "NextShardIterator": "next-1",
            "MillisBehindLatest": 0,
        },
    ]
    iterators = {"shard-000": "iterator-0", "shard-001": "iterator-1"}

    with (
        patch("app.kinesis_consumer.process_kinesis_record") as mock_process,
        patch("app.kinesis_consumer.inventory_kinesis_records_total") as records_metric,
        patch(
            "app.kinesis_consumer.inventory_kinesis_iterator_age_milliseconds"
        ) as age_metric,
    ):
        processed = poll_shards_once(client, iterators, records_limit=1000)

    assert processed == 3
    assert iterators == {"shard-000": "next-0", "shard-001": "next-1"}
    assert mock_process.call_count == 3
    assert records_metric.inc.call_count == 3
    assert age_metric.labels.call_args_list == [
        call(shard_id="shard-000"),
        call(shard_id="shard-001"),
    ]


def test_poll_shards_once_removes_closed_shard() -> None:
    client = MagicMock()
    client.get_records.return_value = {
        "Records": [],
        "NextShardIterator": None,
        "MillisBehindLatest": 0,
    }
    iterators = {"shard-000": "iterator-0"}

    with patch(
        "app.kinesis_consumer.inventory_kinesis_iterator_age_milliseconds"
    ):
        processed = poll_shards_once(client, iterators, records_limit=1000)

    assert processed == 0
    assert iterators == {}
