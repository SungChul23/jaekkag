variable "project_name" {
  description = "프로젝트 이름"
  type        = string
  default     = "ecommerce"
}

variable "environment" {
  description = "배포 환경"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "us-east-1"
}