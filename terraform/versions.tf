# Terraform 실행 버전과 사용할 Provider를 정의한다.
# 팀원마다 다른 버전을 사용해 생기는 호환성 문제를 방지한다.
terraform {
  # 현재 프로젝트에서 사용할 최소 Terraform 버전
  required_version = ">= 1.10.0"

  required_providers {
    # Terraform이 AWS 리소스를 생성할 수 있도록 AWS Provider 사용
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}