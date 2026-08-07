import json
import logging
import os
import time
from typing import Any

import boto3
from botocore.config import Config
from botocore.exceptions import (
    ClientError,
    ConnectionClosedError,
    EndpointConnectionError,
    ReadTimeoutError,
)

from app.metrics import (
    inventory_failed_total,
    inventory_kinesis_errors_total,
    inventory_kinesis_iterator_age_milliseconds,
    inventory_kinesis_records_total,
    inventory_kinesis_retries_total,
)
from app.worker import process_order_event


logger = logging.getLogger("inventory-worker.kinesis")

RETRYABLE_KINESIS_ERROR_CODES = {
    "InternalFailure",
    "LimitExceededException",
    "ProvisionedThroughputExceededException",
    "RequestTimeout",
    "RequestTimeoutException",
    "ServiceUnavailable",
    "ServiceUnavailableException",
    "Throttling",
    "ThrottlingException",
}

RETRYABLE_CONNECTION_ERRORS = (
    ConnectionClosedError,
    EndpointConnectionError,
    ReadTimeoutError,
)


def decode_kinesis_record(record: dict[str, Any]) -> dict[str, Any]:
    """Kinesis 레코드의 Data를 주문 이벤트 딕셔너리로 변환한다."""

    return json.loads(record["Data"].decode("utf-8"))


def process_kinesis_record(record: dict[str, Any]) -> str:
    """Kinesis 레코드 한 건을 재고 처리 함수에 전달한다."""

    return process_order_event(decode_kinesis_record(record))


def create_kinesis_client() -> Any:
    """EKS Pod Identity 자격 증명으로 Kinesis client를 생성한다."""

    return boto3.client(
        "kinesis",
        region_name=os.getenv("AWS_REGION", "us-east-1"),
        config=Config(
            retries={
                "max_attempts": 3,
                "mode": "standard",
            }
        ),
    )


def get_kinesis_error_type(error: Exception) -> str:
    """메트릭과 재시도 판단에 사용할 안정적인 오류 이름을 반환한다."""

    if isinstance(error, ClientError):
        return str(error.response.get("Error", {}).get("Code", "ClientError"))

    return type(error).__name__


def calculate_retry_delay(
    attempt: int,
    base_delay: float,
    max_delay: float,
) -> float:
    """재시도 횟수에 따라 지수 백오프 시간을 계산한다."""

    return min(max_delay, base_delay * (2 ** (attempt - 1)))


def list_shard_ids(client: Any, stream_name: str) -> list[str]:
    """스트림의 모든 shard ID를 정렬해서 반환한다."""

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

    return sorted(shard_ids)


def resolve_shard_index() -> int:
    """명시적 설정 또는 StatefulSet Pod 이름에서 shard index를 구한다."""

    configured_index = os.getenv("SHARD_INDEX")
    if configured_index is not None:
        try:
            shard_index = int(configured_index)
        except ValueError as error:
            raise RuntimeError("SHARD_INDEX는 0 이상의 정수여야 합니다.") from error
    else:
        pod_name = os.getenv("POD_NAME")
        if not pod_name:
            raise RuntimeError("POD_NAME 또는 SHARD_INDEX 환경변수가 필요합니다.")

        try:
            shard_index = int(pod_name.rsplit("-", 1)[1])
        except (IndexError, ValueError) as error:
            raise RuntimeError(
                f"StatefulSet Pod 이름에서 shard index를 찾을 수 없습니다: {pod_name}"
            ) from error

    if shard_index < 0:
        raise RuntimeError("shard index는 0 이상이어야 합니다.")

    return shard_index


def select_assigned_shard(shard_ids: list[str], shard_index: int) -> str:
    """Pod ordinal과 동일한 위치의 shard 하나를 선택한다."""

    if shard_index >= len(shard_ids):
        raise RuntimeError(
            f"Pod index에 대응하는 shard가 없습니다: "
            f"index={shard_index}, shard_count={len(shard_ids)}"
        )

    return shard_ids[shard_index]


def create_shard_iterator(
    client: Any,
    stream_name: str,
    shard_id: str,
    iterator_type: str,
) -> str:
    """이 Worker에 할당된 shard의 iterator를 생성한다."""

    response = client.get_shard_iterator(
        StreamName=stream_name,
        ShardId=shard_id,
        ShardIteratorType=iterator_type,
    )
    shard_iterator = response.get("ShardIterator")

    if not shard_iterator:
        raise RuntimeError(f"shard iterator를 생성하지 못했습니다: {shard_id}")

    return shard_iterator


def poll_once(
    client: Any,
    shard_id: str,
    shard_iterator: str,
    records_limit: int,
) -> tuple[str | None, int]:
    """할당된 shard를 한 번 polling하고 다음 iterator와 처리 건수를 반환한다."""

    response = client.get_records(
        ShardIterator=shard_iterator,
        Limit=records_limit,
    )

    inventory_kinesis_iterator_age_milliseconds.labels(
        shard_id=shard_id
    ).set(response.get("MillisBehindLatest", 0))

    processed_count = 0
    for record in response.get("Records", []):
        try:
            process_kinesis_record(record)
        except Exception:
            inventory_failed_total.inc()
            logger.exception(
                "Kinesis 이벤트 처리 실패: shard=%s sequence_number=%s",
                shard_id,
                record.get("SequenceNumber", "unknown"),
            )
            raise

        inventory_kinesis_records_total.inc()
        processed_count += 1

    return response.get("NextShardIterator"), processed_count


def consume_forever(client: Any | None = None) -> None:
    """StatefulSet Pod에 고정 할당된 shard 하나를 계속 소비한다."""

    stream_name = os.getenv("KINESIS_STREAM_NAME", "ecommerce-order-events")
    iterator_type = os.getenv("KINESIS_ITERATOR_TYPE", "TRIM_HORIZON")
    records_limit = int(os.getenv("KINESIS_RECORDS_LIMIT", "1000"))
    poll_interval = float(os.getenv("KINESIS_POLL_INTERVAL_SEC", "0.2"))
    max_retry_attempts = int(os.getenv("KINESIS_MAX_RETRY_ATTEMPTS", "5"))
    retry_base_delay = float(os.getenv("KINESIS_RETRY_BASE_SEC", "1"))
    retry_max_delay = float(os.getenv("KINESIS_RETRY_MAX_SEC", "10"))

    if iterator_type not in {"TRIM_HORIZON", "LATEST"}:
        raise ValueError(
            "KINESIS_ITERATOR_TYPE은 TRIM_HORIZON 또는 LATEST여야 합니다."
        )
    if not 1 <= records_limit <= 10_000:
        raise ValueError("KINESIS_RECORDS_LIMIT은 1~10000이어야 합니다.")
    if poll_interval < 0:
        raise ValueError("KINESIS_POLL_INTERVAL_SEC은 0 이상이어야 합니다.")
    if max_retry_attempts < 0:
        raise ValueError("KINESIS_MAX_RETRY_ATTEMPTS는 0 이상이어야 합니다.")
    if retry_base_delay < 0 or retry_max_delay < retry_base_delay:
        raise ValueError(
            "Kinesis retry 시간은 0 이상이고 max가 base 이상이어야 합니다."
        )

    kinesis_client = client or create_kinesis_client()
    shard_ids = list_shard_ids(kinesis_client, stream_name)
    shard_index = resolve_shard_index()
    shard_id = select_assigned_shard(shard_ids, shard_index)
    shard_iterator = create_shard_iterator(
        kinesis_client,
        stream_name,
        shard_id,
        iterator_type,
    )

    logger.info(
        "Kinesis 소비 시작: stream=%s shard=%s pod_index=%s iterator_type=%s",
        stream_name,
        shard_id,
        shard_index,
        iterator_type,
    )

    retry_attempt = 0

    while shard_iterator:
        try:
            shard_iterator, processed_count = poll_once(
                kinesis_client,
                shard_id,
                shard_iterator,
                records_limit,
            )
            retry_attempt = 0

            if processed_count == 0:
                time.sleep(poll_interval)

        except ClientError as error:
            error_type = get_kinesis_error_type(error)
            inventory_kinesis_errors_total.labels(error_type=error_type).inc()

            if error_type == "ExpiredIteratorException":
                inventory_kinesis_retries_total.labels(
                    error_type=error_type
                ).inc()
                logger.warning(
                    "Kinesis iterator 만료로 재생성: shard=%s",
                    shard_id,
                )
                shard_iterator = create_shard_iterator(
                    kinesis_client,
                    stream_name,
                    shard_id,
                    iterator_type,
                )
                retry_attempt = 0
                continue

            if error_type not in RETRYABLE_KINESIS_ERROR_CODES:
                logger.exception(
                    "재시도할 수 없는 Kinesis 오류: shard=%s error=%s",
                    shard_id,
                    error_type,
                )
                raise

            retry_attempt += 1
            if retry_attempt > max_retry_attempts:
                logger.exception(
                    "Kinesis 최대 재시도 횟수 초과: shard=%s error=%s attempts=%s",
                    shard_id,
                    error_type,
                    max_retry_attempts,
                )
                raise

            delay = calculate_retry_delay(
                retry_attempt,
                retry_base_delay,
                retry_max_delay,
            )
            inventory_kinesis_retries_total.labels(error_type=error_type).inc()
            logger.warning(
                "Kinesis polling 재시도: shard=%s error=%s retry=%s/%s delay=%ss",
                shard_id,
                error_type,
                retry_attempt,
                max_retry_attempts,
                delay,
            )
            time.sleep(delay)

        except RETRYABLE_CONNECTION_ERRORS as error:
            error_type = get_kinesis_error_type(error)
            inventory_kinesis_errors_total.labels(error_type=error_type).inc()
            retry_attempt += 1

            if retry_attempt > max_retry_attempts:
                logger.exception(
                    "Kinesis 연결 최대 재시도 횟수 초과: "
                    "shard=%s error=%s attempts=%s",
                    shard_id,
                    error_type,
                    max_retry_attempts,
                )
                raise

            delay = calculate_retry_delay(
                retry_attempt,
                retry_base_delay,
                retry_max_delay,
            )
            inventory_kinesis_retries_total.labels(error_type=error_type).inc()
            logger.warning(
                "Kinesis 연결 재시도: shard=%s error=%s retry=%s/%s delay=%ss",
                shard_id,
                error_type,
                retry_attempt,
                max_retry_attempts,
                delay,
            )
            time.sleep(delay)
