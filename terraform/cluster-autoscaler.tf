# ============================================================
# Cluster Autoscaler Pod Identity 신뢰 정책
# ============================================================

# Cluster Autoscaler Pod가 EKS Pod Identity를 통해
# IAM Role을 사용할 수 있도록 신뢰 관계를 설정한다.
data "aws_iam_policy_document" "cluster_autoscaler_assume_role" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]

    principals {
      type = "Service"

      identifiers = [
        "pods.eks.amazonaws.com"
      ]
    }
  }
}


# ============================================================
# Cluster Autoscaler IAM Role
# ============================================================

# Cluster Autoscaler가 EKS Managed Node Group의
# Auto Scaling Group을 조절할 때 사용할 IAM Role
resource "aws_iam_role" "cluster_autoscaler" {
  name = "${local.name_prefix}-cluster-autoscaler-role"

  assume_role_policy = data.aws_iam_policy_document.cluster_autoscaler_assume_role.json

  tags = {
    Name = "${local.name_prefix}-cluster-autoscaler-role"
  }
}


# ============================================================
# Cluster Autoscaler IAM 권한
# ============================================================

data "aws_iam_policy_document" "cluster_autoscaler" {
  # 현재 EKS Cluster에 속한 Auto Scaling Group만
  # 증설하거나 축소할 수 있도록 제한한다.
  statement {
    sid    = "ScaleProjectNodeGroups"
    effect = "Allow"

    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup"
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/k8s.io/cluster-autoscaler/enabled"

      values = [
        "true"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/k8s.io/cluster-autoscaler/${aws_eks_cluster.main.name}"

      values = [
        "owned"
      ]
    }
  }

  # Cluster Autoscaler가 Auto Scaling Group, EC2 Instance,
  # EKS Managed Node Group 정보를 조회할 수 있도록 허용한다.
  statement {
    sid    = "ReadAutoScalingInformation"
    effect = "Allow"

    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:GetInstanceTypesFromInstanceRequirements",
      "eks:DescribeNodegroup"
    ]

    resources = ["*"]
  }
}


# ============================================================
# Cluster Autoscaler IAM Policy
# ============================================================

# Cluster Autoscaler에 필요한 AWS 권한을
# 별도의 IAM Policy로 생성한다.
resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "${local.name_prefix}-cluster-autoscaler-policy"
  description = "Allow Cluster Autoscaler to scale the project EKS managed node group"

  policy = data.aws_iam_policy_document.cluster_autoscaler.json

  tags = {
    Name = "${local.name_prefix}-cluster-autoscaler-policy"
  }
}


# Cluster Autoscaler IAM Role에 위에서 생성한 정책을 연결한다.
resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
}


# ============================================================
# EKS Pod Identity Association
# ============================================================

# kube-system Namespace의 cluster-autoscaler ServiceAccount와
# Cluster Autoscaler IAM Role을 연결한다.
#
# Cluster Autoscaler Pod는 AWS Access Key를 저장하지 않고
# Pod Identity를 통해 임시 AWS 자격 증명을 발급받는다.
resource "aws_eks_pod_identity_association" "cluster_autoscaler" {
  cluster_name = aws_eks_cluster.main.name

  namespace       = "kube-system"
  service_account = "cluster-autoscaler"

  role_arn = aws_iam_role.cluster_autoscaler.arn

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.cluster_autoscaler
  ]
}