# AWS 리소스 이름과 공통 태그에 사용할 프로젝트명
variable "project_name" {
  description = "프로젝트 이름"
  type        = string
  default     = "ecommerce"
}

# 개발·운영 환경을 구분하기 위한 값
# 현재 프로젝트는 개발 환경이므로 dev 사용
variable "environment" {
  description = "배포 환경"
  type        = string
  default     = "dev"
}

# AWS 리소스를 생성할 Region
# us-east-1은 버지니아 북부 Region
variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "us-east-1"
}

# RDS가 최초 생성할 데이터베이스 이름
variable "db_name" {
  description = "RDS 데이터베이스 이름"
  type        = string
  default     = "ecommerce"
}

# Order API, Publisher, Worker가 RDS에 접속할 때 사용할 관리자 계정
variable "db_username" {
  description = "RDS 관리자 사용자"
  type        = string
  default     = "ecommerce_admin"
}

# RDS 관리자 비밀번호
# 코드에 직접 작성하지 않고 TF_VAR_db_password 환경변수로 전달한다.
# sensitive 설정으로 Terraform 출력 화면에 비밀번호가 표시되는 것을 방지한다.
variable "db_password" {
  description = "RDS 관리자 비밀번호"
  type        = string
  sensitive   = true
}