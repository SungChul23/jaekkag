# ============================================================
# AWS Load Balancer Controller IAM Policy
# ============================================================

# AWS Load Balancer Controller가 ALB, Target Group,
# Listener, Security Group 등을 생성하고 관리할 때 사용할 권한
resource "aws_iam_policy" "alb_controller" {
  name = "${local.name_prefix}-alb-controller-policy"

  # AWS 공식 Load Balancer Controller v2.14.1 IAM Policy 파일 사용
  policy = file(
    "${path.module}/policies/aws-load-balancer-controller-policy.json"
  )

  tags = {
    Name = "${local.name_prefix}-alb-controller-policy"
  }
}


# ============================================================
# AWS Load Balancer Controller IAM Role 신뢰 정책
# ============================================================

# EKS Pod Identity를 통해 Controller Pod가 IAM Role을
# 사용할 수 있도록 pods.eks.amazonaws.com을 신뢰 대상으로 설정
data "aws_iam_policy_document" "alb_controller_assume_role" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}


# ============================================================
# AWS Load Balancer Controller IAM Role
# ============================================================

# kube-system Namespace에서 실행되는 Controller Pod가
# AWS ALB 관련 API를 호출할 때 사용할 IAM Role
resource "aws_iam_role" "alb_controller" {
  name = "${local.name_prefix}-alb-controller-role"

  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume_role.json

  tags = {
    Name = "${local.name_prefix}-alb-controller-role"
  }
}


# ============================================================
# IAM Policy와 IAM Role 연결
# ============================================================

# ALB 관리 권한이 담긴 IAM Policy를 Controller IAM Role에 연결
resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}


# ============================================================
# EKS Pod Identity Association
# ============================================================

# kube-system Namespace의 aws-load-balancer-controller
# ServiceAccount와 Controller IAM Role을 연결한다.
#
# 이후 Helm으로 설치되는 Controller Pod는 해당 ServiceAccount를
# 사용하여 별도의 AWS Access Key 없이 ALB를 생성할 수 있다.
resource "aws_eks_pod_identity_association" "alb_controller" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.alb_controller.arn

  # Pod Identity Agent와 IAM Policy 연결이 완료된 후 생성
  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.alb_controller
  ]
}