terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-east-1"
}

# 팀 공통 규격 문서(1일차)에서 확정한 스트림 이름 그대로 사용
variable "stream_name" {
  default = "ecommerce-order-events"
}

resource "aws_kinesis_stream" "order_events" {
  name             = var.stream_name
  shard_count      = 1
  retention_period = 24

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = {
    project     = "test-ecommerce"
    environment = "dev"
    owner       = "role-2"
  }
}

output "stream_name" {
  value = aws_kinesis_stream.order_events.name
}
output "stream_arn" {
  value = aws_kinesis_stream.order_events.arn
}
