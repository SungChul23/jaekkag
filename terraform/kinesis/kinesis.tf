# 주문 이벤트를 비동기로 전달하는 Kinesis Data Stream
#
# 처리 흐름:
# Outbox Publisher → Kinesis → Inventory Worker
#
# 서비스를 직접 연결하지 않아 장애를 분리하고
# Publisher와 Worker를 독립적으로 확장할 수 있도록 한다.
resource "aws_kinesis_stream" "order_events" {
  # Publisher와 Worker가 공통으로 사용할 Stream 이름
  name = "ecommerce-order-events"

  # Worker 장애 시에도 처리되지 않은 이벤트를 24시간 보관
  retention_period = 24

  # 샤드 1개로 시작 (초당 쓰기 1MB / 1,000 레코드 처리 가능)
  # 부하 테스트에서 처리량 초과 시 shard_count를 늘려 재배포
  shard_count = 1

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

    # # AWS 관리형 KMS Key로 Stream 데이터를 암호화 (추후 진행)
    # encryption_type = "KMS"
    # kms_key_id      = "alias/aws/kinesis"

  tags = {
    Name = "ecommerce-order-events"
  }
}