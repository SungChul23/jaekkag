import json

import boto3

from app.config import KINESIS_STREAM_NAME, AWS_REGION

kinesis = boto3.client("kinesis", region_name=AWS_REGION)


def publish_one(event_id, order_id, product_id, quantity, created_at):
    """이벤트를 Kinesis 규격(JSON)에 맞게 변환해서 발행한다.
    PartitionKey를 order_id로 지정 - 같은 주문의 이벤트는 항상
    같은 샤드로 가서 순서가 보장된다 (팀 공통 규격)."""
    payload = {
        "event_id": event_id,
        "event_type": "ORDER_CREATED",
        "order_id": order_id,
        "product_id": product_id,
        "quantity": quantity,
        "created_at": created_at.isoformat() + "Z",
    }
    kinesis.put_record(
        StreamName=KINESIS_STREAM_NAME,
        Data=json.dumps(payload).encode("utf-8"),
        PartitionKey=str(order_id),
    )