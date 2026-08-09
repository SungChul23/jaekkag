# 다른 Terraform 리소스와 Kubernetes 설정에 사용할 VPC ID
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

# 외부 ALB와 NAT Gateway를 배치할 Public Subnet ID 목록
output "public_subnet_ids" {
  description = "Public Subnet ID 목록"
  value       = aws_subnet.public[*].id
}

# EKS Worker Node와 RDS를 배치할 Private Subnet ID 목록
output "private_subnet_ids" {
  description = "Private Subnet ID 목록"
  value       = aws_subnet.private[*].id
}

# Private Subnet의 외부 통신에 사용되는 NAT Gateway ID
output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = aws_nat_gateway.main.id
}

# GitHub Actions가 Docker 이미지를 Push할 때 사용할 ECR URL
output "ecr_repository_urls" {
  description = "ECR Repository URL 목록"

  value = {
    for name, repository in aws_ecr_repository.app :
    name => repository.repository_url
  }
}

# Kubernetes ConfigMap의 DB_HOST에 사용할 RDS Endpoint
output "rds_endpoint" {
  description = "RDS 접속 Endpoint"
  value       = aws_db_instance.main.address
}

# 애플리케이션의 DB_PORT에 사용할 RDS 접속 포트
output "rds_port" {
  description = "RDS 접속 Port"
  value       = aws_db_instance.main.port
}

# Publisher와 Worker의 환경변수에 사용할 Kinesis Stream 이름
output "kinesis_stream_name" {
  description = "Kinesis Stream 이름"
  value       = aws_kinesis_stream.order_events.name
}

# Publisher와 Worker의 IAM 권한 설정에 사용할 Kinesis Stream ARN
output "kinesis_stream_arn" {
  description = "Kinesis Stream ARN"
  value       = aws_kinesis_stream.order_events.arn
}

# kubectl 설정과 GitHub Actions 배포에서 사용할 EKS Cluster 이름
output "eks_cluster_name" {
  description = "EKS Cluster 이름"
  value       = aws_eks_cluster.main.name
}

# EKS API Server 접속 주소
output "eks_cluster_endpoint" {
  description = "EKS Cluster Endpoint"
  value       = aws_eks_cluster.main.endpoint
}

# EKS Managed Node Group 이름
output "eks_node_group_name" {
  description = "EKS Managed Node Group 이름"
  value       = aws_eks_node_group.main.node_group_name
}

# kubectl이 EKS 인증서 검증에 사용할 Cluster CA 데이터
output "eks_cluster_certificate_authority" {
  description = "EKS Cluster Certificate Authority"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

# Outbox Publisher Pod에 연결되는 IAM Role ARN
output "publisher_iam_role_arn" {
  description = "Outbox Publisher IAM Role ARN"
  value       = aws_iam_role.publisher.arn
}

# Inventory Worker Pod에 연결되는 IAM Role ARN
output "worker_iam_role_arn" {
  description = "Inventory Worker IAM Role ARN"
  value       = aws_iam_role.worker.arn
}

# GitHub Actions workflow의 role-to-assume에 사용할 IAM Role ARN
output "github_actions_role_arn" {
  description = "GitHub Actions OIDC IAM Role ARN"
  value       = aws_iam_role.github_actions.arn
}