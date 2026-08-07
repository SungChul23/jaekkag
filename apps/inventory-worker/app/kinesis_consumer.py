import json
import logging
import os
import time
from typing import Any

import boto3

from app.metrics import (
    inventory_kinesis_iterator_age_milliseconds,
    inventory_kinesis_records_total,
)
from app.worker import process_order_event


logger = logging.getLogger("inventory-worker.kinesis")


def decode_kinesis_record(record: dict[str, Any]) -> dict[str, Any]:
    """Kinesis 레코드의 Data를 주문 이벤트 딕셔너리로 변환한다."""

    data_bytes = record["Data"]
    decoded_text = data_bytes.decode("utf-8")
    return json.loads(decoded_text)


def process_kinesis_record(record: dict[str, Any]) -> str:
    """Kinesis 레코드 1건을 Inventory Worker에 전달한다."""

    event = decode_kinesis_record(record)
    return process_order_event(event)


def create_kinesis_client() -> Any:
    """Pod Identity 자격 증명으로 Kinesis client를 생성한다."""

    region = os.getenv("AWS_REGION", "us-east-1")
    return boto3.client("kinesis", region_name=region)


def list_shard_ids(client: Any, stream_name: str) -> list[str]:
    """스트림의 모든 shard ID를 페이지 끝까지 조회한다."""

    shard_ids: list[str] = []
    request: dict[str, Any] = {"StreamName": stream_name}

    while True:
        response = client.list_shards(**request)
        shard_ids.extend(shard["ShardId"] for shard in response.get("Shards", []))

        next_token = response.get("NextToken")
        if not next_token:
            break

        request = {"NextToken": next_token}

    if not shard_ids:
        raise RuntimeError(f"Kinesis stream에 shard가 없습니다: {stream_name}")

    return shard_ids


def create_shard_iterators(
    client: Any,
    stream_name: str,
    shard_ids: list[str],
    iterator_type: str,
) -> dict[str, str]:
    """단일 Worker가 순회할 shard별 iterator를 생성한다."""

    iterators: dict[str, str] = {}

    for shard_id in shard_ids:
        response = client.get_shard_iterator(
            StreamName=stream_name,
            ShardId=shard_id,
            ShardIteratorType=iterator_type,
        )
        shard_iterator = response.get("ShardIterator")

        if shard_iterator:
            iterators[shard_id] = shard_iterator

    return iterators


def poll_shards_once(
    client: Any,
    shard_iterators: dict[str, str],
    records_limit: int,
) -> int:
    """현재 iterator를 이용해 모든 shard를 한 번씩 순회한다.

    레코드 처리가 실패하면 iterator를 다음 위치로 갱신하지 않고 예외를
    전달한다. 호출자가 Worker를 재시작하면 TRIM_HORIZON부터 다시 읽고,
    이미 처리한 이벤트는 processed_events가 중복 차감을 방지한다.
    """

    processed_count = 0

    for shard_id, shard_iterator in list(shard_iterators.items()):
        response = client.get_records(
            ShardIterator=shard_iterator,
            Limit=records_limit,
        )

        records = response.get("Records", [])
        iterator_age = response.get("MillisBehindLatest", 0)
        inventory_kinesis_iterator_age_milliseconds.labels(
            shard_id=shard_id
        ).set(iterator_age)

        for record in records:
            process_kinesis_record(record)
            inventory_kinesis_records_total.inc()
            processed_count += 1

        next_iterator = response.get("NextShardIterator")
        if next_iterator:
            shard_iterators[shard_id] = next_iterator
        else:
            del shard_iterators[shard_id]

    return processed_count


def consume_forever(client: Any | None = None) -> None:
    """단일 Worker에서 스트림의 모든 shard를 계속 polling한다."""

    stream_name = os.getenv("KINESIS_STREAM_NAME", "ecommerce-order-events")
    iterator_type = os.getenv("KINESIS_ITERATOR_TYPE", "TRIM_HORIZON")
    records_limit = int(os.getenv("KINESIS_RECORDS_LIMIT", "1000"))
    poll_interval = float(os.getenv("KINESIS_POLL_INTERVAL_SEC", "0.2"))

    if iterator_type not in {"TRIM_HORIZON", "LATEST"}:
        raise ValueError(
            "KINESIS_ITERATOR_TYPE은 TRIM_HORIZON 또는 LATEST여야 합니다."
        )

    if not 1 <= records_limit <= 10_000:
        raise ValueError("KINESIS_RECORDS_LIMIT은 1~10000이어야 합니다.")

    if poll_interval < 0:
        raise ValueError("KINESIS_POLL_INTERVAL_SEC은 0 이상이어야 합니다.")

    kinesis_client = client or create_kinesis_client()
    shard_ids = list_shard_ids(kinesis_client, stream_name)
    shard_iterators = create_shard_iterators(
        kinesis_client,
        stream_name,
        shard_ids,
        iterator_type,
    )

    logger.info(
        "Kinesis 소비 시작: stream=%s shards=%s iterator_type=%s",
        stream_name,
        len(shard_iterators),
        iterator_type,
    )

    while shard_iterators:
        processed_count = poll_shards_once(
            kinesis_client,
            shard_iterators,
            records_limit,
        )

        if processed_count == 0:
            time.sleep(poll_interval)
