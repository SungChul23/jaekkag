# ============================================================
# EKS Pod Identity Agent
# ============================================================

# Kubernetes Pod가 EC2 Node 전체 권한을 사용하지 않고,
# Pod별 IAM Role을 사용할 수 있도록 EKS Pod Identity Agent를 설치한다.
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "eks-pod-identity-agent"

  # EKS Cluster와 Worker Node가 준비된 후 Add-on 설치
  depends_on = [
    aws_eks_node_group.main
  ]

  tags = {
    Name = "${local.name_prefix}-pod-identity-agent"
  }
}


# ============================================================
# Pod Identity 공통 신뢰 정책
# ============================================================

# EKS Pod Identity 서비스가 Publisher와 Worker의 IAM Role을
# 사용할 수 있도록 공통 신뢰 정책을 정의한다.
data "aws_iam_policy_document" "pod_identity_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
  }
}


# ============================================================
# Outbox Publisher IAM
# ============================================================

# Outbox Publisher Pod가 사용할 IAM Role
resource "aws_iam_role" "publisher" {
  name               = "${local.name_prefix}-publisher-role"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json

  tags = {
    Name = "${local.name_prefix}-publisher-role"
  }
}

# Publisher가 주문 이벤트를 Kinesis에 발행하는 데 필요한 최소 권한
data "aws_iam_policy_document" "publisher_kinesis" {
  statement {
    sid    = "PublishOrderEvents"
    effect = "Allow"

    actions = [
      "kinesis:PutRecord",
      "kinesis:PutRecords",
      "kinesis:DescribeStreamSummary"
    ]

    # 프로젝트의 주문 이벤트 Stream에만 접근 허용
    resources = [
      aws_kinesis_stream.order_events.arn
    ]
  }
}

# Publisher용 Kinesis 발행 정책 생성
resource "aws_iam_policy" "publisher_kinesis" {
  name        = "${local.name_prefix}-publisher-kinesis-policy"
  description = "Allow Outbox Publisher to publish order events to Kinesis"
  policy      = data.aws_iam_policy_document.publisher_kinesis.json
}

# Publisher IAM Role에 Kinesis 발행 정책 연결
resource "aws_iam_role_policy_attachment" "publisher_kinesis" {
  role       = aws_iam_role.publisher.name
  policy_arn = aws_iam_policy.publisher_kinesis.arn
}


# ============================================================
# Inventory Worker IAM
# ============================================================

# Inventory Worker Pod가 사용할 IAM Role
resource "aws_iam_role" "worker" {
  name               = "${local.name_prefix}-worker-role"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json

  tags = {
    Name = "${local.name_prefix}-worker-role"
  }
}

# Worker가 Kinesis 주문 이벤트를 읽는 데 필요한 최소 권한
data "aws_iam_policy_document" "worker_kinesis" {
  statement {
    sid    = "ConsumeOrderEvents"
    effect = "Allow"

    actions = [
      "kinesis:GetRecords",
      "kinesis:GetShardIterator",
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
      "kinesis:ListShards",
      # "kinesis:SubscribeToShard" ->  팬-아웃 권한 삭제
    ]

    # 프로젝트의 주문 이벤트 Stream에만 접근 허용
    resources = [
      aws_kinesis_stream.order_events.arn
    ]
  }
}

# Worker용 Kinesis 소비 정책 생성
resource "aws_iam_policy" "worker_kinesis" {
  name        = "${local.name_prefix}-worker-kinesis-policy"
  description = "Allow Inventory Worker to consume order events from Kinesis"
  policy      = data.aws_iam_policy_document.worker_kinesis.json
}

# Worker IAM Role에 Kinesis 소비 정책 연결
resource "aws_iam_role_policy_attachment" "worker_kinesis" {
  role       = aws_iam_role.worker.name
  policy_arn = aws_iam_policy.worker_kinesis.arn
}


# ============================================================
# EKS Pod Identity 연결
# ============================================================

# ecommerce Namespace의 outbox-publisher ServiceAccount와
# Publisher IAM Role을 연결한다.
resource "aws_eks_pod_identity_association" "publisher" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "ecommerce"
  service_account = "outbox-publisher"
  role_arn        = aws_iam_role.publisher.arn

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.publisher_kinesis
  ]
}

# ecommerce Namespace의 inventory-worker ServiceAccount와
# Worker IAM Role을 연결한다.
resource "aws_eks_pod_identity_association" "worker" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "ecommerce"
  service_account = "inventory-worker"
  role_arn        = aws_iam_role.worker.arn

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.worker_kinesis
  ]
}