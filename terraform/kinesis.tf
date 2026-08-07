# ============================================================
# Kinesis Data Stream - 주문 이벤트 전달 통로
# ============================================================
#
# 처리 흐름:
#   Outbox Publisher(다수 파드) → Kinesis → Inventory Worker
#
# 왜 필요한가:
#   Outbox Publisher와 Inventory Worker를 직접 연결하지 않고
#   Kinesis라는 중간 통로를 두어, 한쪽이 느려지거나 죽어도
#   다른 쪽이 영향받지 않게 하고 각자 독립적으로 확장할 수 있게 한다.
#
# 왜 PROVISIONED 모드로 변경했는가:
#   On-Demand는 예측 불가능한 폭주 대응에는 유리하지만
#   짧은 프로젝트 기간 + 비용 효율을 우선하여 샤드 3개로 고정.
#   Worker 파드 3개와 샤드 3개를 1:1로 매칭시켜 병렬 처리하며,
#   측정 결과 목표 트래픽(수백~1000 RPS)에 샤드 3개(최대 3000 RPS)면
#   충분한 여유가 있다고 판단함.
resource "aws_kinesis_stream" "order_events" {
  name = "ecommerce-order-events"

  retention_period = 24

  # PROVISIONED: 샤드 수를 직접 고정하여 비용 예측 가능하게 함
  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  # 샤드 3개 = Worker 파드 3개와 1:1 매칭 (SHARD_INDEX 환경변수로 전담)
  shard_count = 3

  # encryption_type = "KMS"
  # kms_key_id      = "alias/aws/kinesis"

  tags = {
    project     = "ecommerce"
    environment = "dev"
    owner       = "role-2"
    Name        = "ecommerce-order-events"
  }
}

# output "stream_name" {
#   description = "Publisher/Worker의 KINESIS_STREAM_NAME 환경변수로 주입되는 값"
#   value       = aws_kinesis_stream.order_events.name
# }

# output "stream_arn" {
#   description = "IAM 정책의 resources 필드에서 참조하는 값 (최소 권한 스코핑용)"
#   value       = aws_kinesis_stream.order_events.arn
# }