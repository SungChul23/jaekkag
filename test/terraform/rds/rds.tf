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
variable "project" {
  default = "test-ecommerce-dev"
}
variable "db_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

data "terraform_remote_state" "vpc" {
  backend = "local"
  config = {
    path = "../vpc/terraform.tfstate"
  }
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-rds-subnet-group"
  subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnets
}

resource "aws_security_group" "rds" {
  name   = "${var.project}-rds-sg"
  vpc_id = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [data.terraform_remote_state.vpc.outputs.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "this" {
  identifier             = "${var.project}-rds"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = "ecommerce"
  username               = "appuser"
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  multi_az               = false # 비용 절감용. 운영에서는 true 권장
}

output "rds_endpoint" {
  value = aws_db_instance.this.address
}
