# RDS를 배치할 Private Subnet 묶음
# 서로 다른 2개 가용영역의 Private Subnet을 사용한다.
resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${local.name_prefix}-db-subnet-group"
  }
}

# RDS MySQL 접속을 제어하는 Security Group
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "Allow MySQL access from inside the VPC"
  vpc_id      = aws_vpc.main.id

  # 현재는 VPC 내부에서 MySQL 접속을 허용한다.
  # EKS Security Group 생성 후 해당 Security Group만 허용하도록 축소할 수 있다.
  ingress {
    description = "MySQL from VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  # RDS에서 필요한 외부 통신 허용
  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-rds-sg"
  }
}

# 주문과 재고 데이터를 저장할 Amazon RDS MySQL
resource "aws_db_instance" "main" {
  identifier = "${local.name_prefix}-rds"

  # 스파이크 테스트에서 db.t3.micro의 DB 연결 한도가
  # 병목으로 확인되어 메모리와 연결 여유 확보를 위해 상향
  instance_class = "db.t3.small"

  # 프로젝트 테스트를 위해 다음 유지보수 시간까지 기다리지 않고
  # 변경사항을 즉시 적용한다. 적용 과정에서 RDS가 재부팅될 수 있다.
  apply_immediately = true

  # 프로젝트용 최소 스토리지로 시작하고 최대 30GB까지 자동 확장
  allocated_storage     = 20
  max_allocated_storage = 30
  storage_type          = "gp3"
  storage_encrypted     = true

  # variables.tf에서 DB 이름과 계정정보를 전달받는다.
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 3306

  # RDS를 Private Subnet에 배치하고 RDS Security Group 연결
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # 인터넷에서 RDS로 직접 접속할 수 없도록 설정
  publicly_accessible = false

  # 3일 프로젝트 비용 절감을 위해 단일 가용영역 사용
  multi_az = false

  # 프로젝트 종료 시 최종 Snapshot 없이 삭제 가능
  skip_final_snapshot = true

  # 프로젝트 종료 후 Terraform으로 삭제할 수 있도록 보호 기능 비활성화
  deletion_protection = false

  # 장애 복구와 데이터 확인을 위해 자동 백업을 1일간 보관
  backup_retention_period = 1

  tags = {
    Name = "${local.name_prefix}-rds"
  }
}