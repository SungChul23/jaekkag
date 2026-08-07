# ============================================================
# EKS Cluster IAM Role
# ============================================================

# EKS Control Plane이 AWS 리소스를 관리할 때 사용할 IAM Role
resource "aws_iam_role" "eks_cluster" {
  name = "${local.name_prefix}-eks-cluster-role"

  # EKS 서비스가 이 IAM Role을 사용할 수 있도록 신뢰 관계 설정
  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "eks.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-eks-cluster-role"
  }
}

# EKS Control Plane 운영에 필요한 AWS 관리형 정책 연결
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}


# ============================================================
# EKS Cluster
# ============================================================

# Order API, Outbox Publisher, Inventory Worker를 실행할
# Kubernetes Control Plane을 생성한다.
resource "aws_eks_cluster" "main" {
  name = "${local.name_prefix}-eks"

  # EKS Control Plane이 사용할 IAM Role
  role_arn = aws_iam_role.eks_cluster.arn

  # ----------------------------------------------------------
  # EKS 접근 권한 관리
  # ----------------------------------------------------------

  # IAM User 또는 IAM Role의 Kubernetes 접근 권한을
  # EKS Access Entry API 방식으로 관리한다.
  access_config {
    # 기존 aws-auth ConfigMap을 사용하지 않고
    # EKS Access Entry API만 사용한다.
    authentication_mode = "API"

    # Terraform으로 Cluster를 생성한 IAM User 또는 Role에
    # 최초 Kubernetes 관리자 권한을 자동으로 부여한다.
    bootstrap_cluster_creator_admin_permissions = true
  }

  # ----------------------------------------------------------
  # EKS 네트워크 설정
  # ----------------------------------------------------------

  vpc_config {
    # EKS 네트워크 인터페이스를 Private Subnet에 연결
    subnet_ids = aws_subnet.private[*].id

    # 로컬 PC에서 kubectl을 사용할 수 있도록
    # EKS API Public Endpoint 활성화
    endpoint_public_access = true

    # VPC 내부에서도 EKS API에 접근할 수 있도록
    # Private Endpoint도 함께 활성화
    endpoint_private_access = true
  }

  # Cluster IAM 정책이 연결된 후 EKS Cluster 생성
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  tags = {
    Name = "${local.name_prefix}-eks"
  }
}


# ============================================================
# EKS Worker Node IAM Role
# ============================================================

# EC2 Worker Node가 EKS Cluster에 참여하고
# AWS 서비스에 접근할 때 사용할 IAM Role
resource "aws_iam_role" "eks_node" {
  name = "${local.name_prefix}-eks-node-role"

  # EC2가 이 IAM Role을 사용할 수 있도록 신뢰 관계 설정
  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-eks-node-role"
  }
}

# Worker Node가 EKS Cluster에 등록되고 통신할 수 있는 권한
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# Worker Node와 Pod에 VPC 네트워크 인터페이스와
# IP 주소를 할당하는 데 필요한 권한
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# ECR의 애플리케이션 이미지를 Worker Node가
# 내려받을 수 있도록 읽기 권한 연결
resource "aws_iam_role_policy_attachment" "eks_ecr_read_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}


# ============================================================
# EKS Managed Node Group
# ============================================================

# 실제 애플리케이션 Pod가 실행될 EC2 Worker Node 그룹
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.name_prefix}-node-group"
  node_role_arn   = aws_iam_role.eks_node.arn

  # Worker Node를 외부에 직접 노출하지 않도록
  # Private Subnet에 배치
  subnet_ids = aws_subnet.private[*].id

  # 프로젝트에서 사용할 Worker Node EC2 사양
  instance_types = ["t3.medium"]

  # Spot 대신 On-Demand 인스턴스 사용
  capacity_type = "ON_DEMAND"

  # EKS에서 관리하는 Amazon Linux 2023 이미지 사용
  ami_type = "AL2023_x86_64_STANDARD"

  # Worker Node의 Root Volume 크기
  disk_size = 20

  scaling_config {
    # 기본 Worker Node 수
    desired_size = 2

    # 최소 Worker Node 수
    min_size = 1

    # 최대 Worker Node 수
    max_size = 3
  }

  update_config {
    # Node Group 업데이트 중 동시에 사용할 수 없게 되는
    # 최대 Worker Node 수
    max_unavailable = 1
  }

  # Worker Node에 필요한 IAM 정책이 연결된 후 생성
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_read_policy
  ]

  tags = {
    Name = "${local.name_prefix}-node-group"
  }
}
# ============================================================
# EKS 추가 관리자 Access Entry
# ============================================================

# additional_admin_role_arns에 입력된 IAM Role마다
# EKS Access Entry를 생성한다.
#
# Access Entry는 IAM Role을 EKS에 접근 가능한
# Principal로 등록하는 리소스다.
resource "aws_eks_access_entry" "additional_admin" {
  for_each = var.additional_admin_role_arns

  # 접근할 EKS Cluster
  cluster_name = aws_eks_cluster.main.name

  # 관리자 권한을 받을 팀원 IAM Role ARN
  principal_arn = each.value

  # 일반 IAM Role용 Access Entry 타입
  type = "STANDARD"

  tags = {
    Name = "${local.name_prefix}-additional-admin"
  }
}


# ============================================================
# EKS 추가 관리자 정책 연결
# ============================================================

# 등록된 IAM Role에 EKS Cluster 전체 관리자 권한을 부여한다.
resource "aws_eks_access_policy_association" "additional_admin" {
  for_each = var.additional_admin_role_arns

  # 권한을 적용할 EKS Cluster
  cluster_name = aws_eks_cluster.main.name

  # 관리자 권한을 받을 팀원 IAM Role ARN
  principal_arn = each.value

  # 모든 Namespace와 Cluster 리소스를 관리할 수 있는 정책
  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  # Cluster 전체 범위에 권한 적용
  access_scope {
    type = "cluster"
  }

  # Access Entry가 먼저 생성된 후 정책 연결
  depends_on = [
    aws_eks_access_entry.additional_admin
  ]
}