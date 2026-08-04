# ============================================================
# EKS Cluster IAM Role
# ============================================================

# EKS 서비스가 AWS 리소스를 관리할 때 사용할 IAM Role
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

# EKS Cluster 운영에 필요한 AWS 관리형 권한 연결
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

  # EKS에서 기본으로 지원되는 Kubernetes 버전을 사용한다.
  # 특정 버전을 고정하면 지원 종료 시 수정이 필요하므로 현재는 생략한다.
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    # EKS 네트워크 인터페이스를 Private Subnet에 연결
    subnet_ids = aws_subnet.private[*].id

    # 로컬 PC에서 kubectl을 사용할 수 있도록 Public Endpoint 활성화
    endpoint_public_access = true

    # VPC 내부에서도 EKS API에 접근할 수 있도록 Private Endpoint 활성화
    endpoint_private_access = true
  }

  # IAM 정책이 연결된 후 EKS Cluster를 생성
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

# Worker Node와 Pod에 VPC 네트워크를 구성하는 권한
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# ECR에 저장된 Order API, Publisher, Worker 이미지를 내려받는 권한
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

  # Worker Node를 외부에 직접 노출하지 않도록 Private Subnet에 배치
  subnet_ids = aws_subnet.private[*].id

  # 프로젝트 규모에서 사용할 Worker Node EC2 사양
  instance_types = ["t3.medium"]

  # 일반적인 On-Demand 인스턴스 사용
  # Spot보다 비용은 높지만 프로젝트 중 예고 없이 종료될 가능성이 낮다.
  capacity_type = "ON_DEMAND"

  # EKS에서 관리하는 기본 Linux 이미지 사용
  ami_type = "AL2023_x86_64_STANDARD"

  # Worker Node의 Root Volume 크기
  disk_size = 20

  scaling_config {
    # 평상시 Worker Node 2개 실행
    desired_size = 2

    # 장애 또는 비용 조절 시 최소 1개까지 축소
    min_size = 1

    # Pod 부하 증가 시 최대 3개까지 확장 가능
    max_size = 3
  }

  update_config {
    # Node Group 업데이트 시 동시에 중단할 수 있는 최대 Node 수
    max_unavailable = 1
  }

  # Worker Node 필수 IAM 정책이 연결된 후 Node Group 생성
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_read_policy
  ]

  tags = {
    Name = "${local.name_prefix}-node-group"
  }
}