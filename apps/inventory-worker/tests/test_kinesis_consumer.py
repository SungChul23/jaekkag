# Kinesis 형식의 데이터를 원래 주문 이벤트로 복원하는지 확인하는 테스트
import json
from unittest.mock import MagicMock, call, patch

import pytest

from app.kinesis_consumer import (
    create_shard_iterator,
    decode_kinesis_record,
    list_shard_ids,
    poll_once,
    resolve_shard_index,
    select_assigned_shard,
)


def test_decode_kinesis_record() -> None:
    # 가짜 주문 이벤트 원본
    original_event = {
        "event_id": "770e8400-e29b-41d4-a716-446655440002",
        "event_type": "ORDER_CREATED",
        "order_id": 1003,
        "product_id": 101,
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
        "product_id": 101,
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


def test_list_shard_ids_reads_all_pages_and_sorts() -> None:
    client = MagicMock()
    client.list_shards.side_effect = [
        {
            "Shards": [{"ShardId": "shard-001"}, {"ShardId": "shard-000"}],
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


@pytest.mark.parametrize(
    ("pod_name", "expected_index"),
    [
        ("inventory-worker-0", 0),
        ("inventory-worker-1", 1),
        ("inventory-worker-2", 2),
    ],
)
def test_resolve_shard_index_from_statefulset_pod(
    pod_name: str,
    expected_index: int,
) -> None:
    with patch.dict(
        "app.kinesis_consumer.os.environ",
        {"POD_NAME": pod_name},
        clear=True,
    ):
        assert resolve_shard_index() == expected_index


def test_explicit_shard_index_overrides_pod_name() -> None:
    with patch.dict(
        "app.kinesis_consumer.os.environ",
        {"POD_NAME": "inventory-worker-2", "SHARD_INDEX": "1"},
        clear=True,
    ):
        assert resolve_shard_index() == 1


@pytest.mark.parametrize("pod_name", ["inventory-worker", "worker-random-name"])
def test_resolve_shard_index_rejects_invalid_pod_name(pod_name: str) -> None:
    with patch.dict(
        "app.kinesis_consumer.os.environ",
        {"POD_NAME": pod_name},
        clear=True,
    ):
        with pytest.raises(RuntimeError, match="shard index"):
            resolve_shard_index()


def test_resolve_shard_index_requires_environment() -> None:
    with patch.dict("app.kinesis_consumer.os.environ", {}, clear=True):
        with pytest.raises(RuntimeError, match="POD_NAME 또는 SHARD_INDEX"):
            resolve_shard_index()


def test_each_pod_selects_one_distinct_shard() -> None:
    shard_ids = ["shard-000", "shard-001", "shard-002"]

    assert select_assigned_shard(shard_ids, 0) == "shard-000"
    assert select_assigned_shard(shard_ids, 1) == "shard-001"
    assert select_assigned_shard(shard_ids, 2) == "shard-002"


def test_select_assigned_shard_rejects_excess_pod_index() -> None:
    with pytest.raises(RuntimeError, match="shard_count=3"):
        select_assigned_shard(
            ["shard-000", "shard-001", "shard-002"],
            3,
        )


def test_create_shard_iterator() -> None:
    client = MagicMock()
    client.get_shard_iterator.return_value = {"ShardIterator": "iterator-0"}

    result = create_shard_iterator(
        client,
        "ecommerce-order-events",
        "shard-000",
        "TRIM_HORIZON",
    )

    assert result == "iterator-0"
    client.get_shard_iterator.assert_called_once_with(
        StreamName="ecommerce-order-events",
        ShardId="shard-000",
        ShardIteratorType="TRIM_HORIZON",
    )


def test_poll_once_processes_records_and_returns_next_iterator() -> None:
    client = MagicMock()
    client.get_records.return_value = {
        "Records": [{"Data": b"first"}, {"Data": b"second"}],
        "NextShardIterator": "next-iterator",
        "MillisBehindLatest": 120,
    }

    with (
        patch("app.kinesis_consumer.process_kinesis_record") as mock_process,
        patch("app.kinesis_consumer.inventory_kinesis_records_total") as records_metric,
        patch(
            "app.kinesis_consumer.inventory_kinesis_iterator_age_milliseconds"
        ) as age_metric,
    ):
        next_iterator, processed_count = poll_once(
            client,
            "shard-000",
            "iterator-0",
            1000,
        )

    assert next_iterator == "next-iterator"
    assert processed_count == 2
    assert mock_process.call_count == 2
    assert records_metric.inc.call_count == 2
    age_metric.labels.assert_called_once_with(shard_id="shard-000")
    age_metric.labels.return_value.set.assert_called_once_with(120)
