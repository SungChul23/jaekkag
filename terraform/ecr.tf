locals {
  # 각 애플리케이션의 Docker 이미지를 저장할 ECR Repository 목록
  ecr_repositories = toset([
    "order-api",
    "outbox-publisher",
    "inventory-worker"
  ])
}

# 애플리케이션별 ECR Repository 생성
# 하나의 리소스 정의에서 for_each를 사용해 Repository 3개를 만든다.
resource "aws_ecr_repository" "app" {
  for_each = local.ecr_repositories

  name = each.value

  # 동일한 이미지 태그를 새 이미지로 갱신할 수 있도록 설정
  image_tag_mutability = "MUTABLE"

  # 프로젝트 종료 후 이미지가 남아 있어도 Repository를 삭제할 수 있도록 설정
  force_delete = true

  # 이미지가 Push될 때 취약점을 자동 검사
  image_scanning_configuration {
    scan_on_push = true
  }

  # ECR 기본 AES256 암호화 사용
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = each.value
  }
}