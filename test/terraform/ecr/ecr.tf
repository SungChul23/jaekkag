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

resource "aws_ecr_repository" "order_api" {
  name                 = "order-api"
  image_tag_mutability = "IMMUTABLE"
}

resource "aws_ecr_repository" "outbox_publisher" {
  name                 = "test-outbox-publisher"
  image_tag_mutability = "IMMUTABLE"
}

resource "aws_ecr_repository" "inventory_worker" {
  name                 = "test-inventory-worker"
  image_tag_mutability = "IMMUTABLE"
}

output "order_api_repo_url" {
  value = aws_ecr_repository.order_api.repository_url
}
output "outbox_publisher_repo_url" {
  value = aws_ecr_repository.outbox_publisher.repository_url
}
output "inventory_worker_repo_url" {
  value = aws_ecr_repository.inventory_worker.repository_url
}
