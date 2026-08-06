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
# 왜 ON_DEMAND 모드인가:
#   사전예약 트래픽 폭주처럼 미리 예측하기 어려운 상황에서
#   샤드 처리량을 수동으로 계산/조정할 필요 없이
#   AWS가 트래픽에 따라 자동으로 용량을 늘려주도록 하기 위함.
#   (Provisioned로 하면 shard_count를 직접 계산해서 미리
#    정해둬야 하는데, "예측 불가능한 폭주 대응"이라는
#    프로젝트 목표와는 방향이 맞지 않아 On-Demand를 채택함)
resource "aws_kinesis_stream" "order_events" {
  # Publisher와 Worker가 공통 규격으로 참조하는 Stream 이름
  # (1일차 공통 규격 문서에서 확정된 값, 임의로 바꾸면 안 됨)
  name = "ecommerce-order-events"

  # 이벤트 보관 기간(시간 단위).
  # Worker가 일시적으로 죽어도, 재시작 후 24시간 이내에는
  # 놓친 이벤트를 다시 읽어서 처리할 수 있도록 여유를 둠.
  retention_period = 24

  # ON_DEMAND: 샤드 수를 AWS가 트래픽에 따라 자동으로 조정.
  # shard_count를 명시할 필요 없음(On-Demand에서는 설정 자체가 불필요).
  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

  # 참고(향후 확장 시): 지금은 KMS 암호화를 적용하지 않음.
  # 나중에 추가하려면 아래 두 줄만 넣으면 되고,
  # 이 경우 Worker의 IAM 정책에 kms:Decrypt 권한도 같이 추가해야 함.
  #
  # encryption_type = "KMS"
  # kms_key_id      = "alias/aws/kinesis"

  tags = {
    project     = "ecommerce"
    environment = "dev"
    owner       = "role-2"
    Name        = "ecommerce-order-events"
  }
}

# 다른 모듈(IAM, ECS/EKS 등)에서 이 스트림을 참조할 수 있도록 출력

# # 나중에 아웃풋으로 따로 관리 가능
# output "stream_name" {
#   description = "Publisher/Worker의 KINESIS_STREAM_NAME 환경변수로 주입되는 값"
#   value       = aws_kinesis_stream.order_events.name
# }

# output "stream_arn" {
#   description = "IAM 정책의 resources 필드에서 참조하는 값 (최소 권한 스코핑용)"
#   value       = aws_kinesis_stream.order_events.arn
# }