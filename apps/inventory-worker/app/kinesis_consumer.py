# boto3 get_records()로 받은 Kinesis 레코드의 Data는 bytes 형태이다.
# bytes를 UTF-8 문자열로 변환한 뒤 JSON을 Python 딕셔너리로 복원한다.
import json
from typing import Any

from app.worker import process_order_event

def decode_kinesis_record(record: dict[str, Any]) -> dict[str, Any]:
    """
    boto3 get_records()로 받은 Kinesis 레코드의 Data를
    원래 주문 이벤트 딕셔너리로 변환한다.
    """
    # inesis 레코드에서 주문 데이터를 꺼내기
    data_bytes = record["Data"]

    decoded_text = data_bytes.decode("utf-8")

    event = json.loads(decoded_text)

    return event

def process_kinesis_record(record: dict[str, Any]) -> str:
    """
    Kinesis 레코드 1건을 주문 이벤트로 변환하고
    Inventory Worker의 재고 처리 함수에 전달한다.
    주문 딕셔너리 → 중복 확인 → 재고 차감 → 결과 저장
    
    """

    event = decode_kinesis_record(record)
    result = process_order_event(event)

    return result