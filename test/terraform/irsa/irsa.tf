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
variable "namespace" {
  default = "ecommerce"
}

data "terraform_remote_state" "eks" {
  backend = "local"
  config = {
    path = "../eks/terraform.tfstate"
  }
}

data "terraform_remote_state" "kinesis" {
  backend = "local"
  config = {
    path = "../kinesis/terraform.tfstate"
  }
}

data "aws_caller_identity" "current" {}

locals {
  oidc_provider_arn = data.terraform_remote_state.eks.outputs.oidc_provider_arn
  # oidc_provider_arn 형식: arn:aws:iam::<acct>:oidc-provider/oidc.eks.<region>.amazonaws.com/id/<id>
  oidc_provider_url = replace(local.oidc_provider_arn, "/^.*oidc-provider//", "")
}

# --- Outbox Publisher: Kinesis 발행 권한만 ---
resource "aws_iam_role" "outbox_publisher" {
  name = "ecommerce-dev-outbox-publisher-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:${var.namespace}:outbox-publisher"
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "outbox_publisher" {
  name = "kinesis-publish"
  role = aws_iam_role.outbox_publisher.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kinesis:PutRecord", "kinesis:PutRecords", "kinesis:DescribeStream"]
      Resource = data.terraform_remote_state.kinesis.outputs.stream_arn
    }]
  })
}

# --- Inventory Worker: Kinesis 소비 권한만 ---
resource "aws_iam_role" "inventory_worker" {
  name = "ecommerce-dev-inventory-worker-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:${var.namespace}:inventory-worker"
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "inventory_worker" {
  name = "kinesis-consume"
  role = aws_iam_role.inventory_worker.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "kinesis:GetRecords",
        "kinesis:GetShardIterator",
        "kinesis:DescribeStream",
        "kinesis:ListShards"
      ]
      Resource = data.terraform_remote_state.kinesis.outputs.stream_arn
    }]
  })
}

output "outbox_publisher_role_arn" {
  value = aws_iam_role.outbox_publisher.arn
}
output "inventory_worker_role_arn" {
  value = aws_iam_role.inventory_worker.arn
}
