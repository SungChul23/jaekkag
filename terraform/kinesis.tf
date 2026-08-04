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

  # Shard 수를 직접 관리하지 않고 AWS가 트래픽에 따라 용량을 관리
  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

  # AWS 관리형 KMS Key로 Stream 데이터를 암호화
  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"

  tags = {
    Name = "ecommerce-order-events"
  }
}