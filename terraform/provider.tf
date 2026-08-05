# 모든 AWS 리소스를 생성할 기본 Region과 공통 태그를 설정한다.
provider "aws" {
  # variables.tf의 aws_region 값을 사용
  # 현재 프로젝트 Region은 버지니아 북부(us-east-1)
  region = var.aws_region

  # Terraform이 생성하는 모든 AWS 리소스에 자동으로 적용되는 태그
  # 프로젝트 리소스 식별과 비용 확인에 사용한다.
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}