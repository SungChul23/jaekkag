# ============================================================
# 기존 GitHub Actions OIDC Provider 조회
# ============================================================

# AWS 계정에 이미 GitHub Actions OIDC Provider가 존재한다.
# 다른 프로젝트에서도 사용하는 공용 리소스이므로
# 여기서는 새로 생성하거나 삭제하지 않고 조회해서 사용한다.
data "aws_iam_openid_connect_provider" "github_actions" {
  arn = "arn:aws:iam::827913617635:oidc-provider/token.actions.githubusercontent.com"
}


# ============================================================
# GitHub Actions IAM Role 신뢰 정책
# ============================================================

# SungChul23/jaekkag 저장소의 main 브랜치에서 실행되는
# GitHub Actions만 이 IAM Role을 사용할 수 있도록 제한한다.
data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type = "Federated"

      identifiers = [
        data.aws_iam_openid_connect_provider.github_actions.arn
      ]
    }

    # GitHub OIDC Token의 대상이 AWS STS인지 확인
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }

    # 지정한 GitHub 저장소의 main 브랜치에서만 Role 사용 허용
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"

      values = [
        "repo:SungChul23/jaekkag:ref:refs/heads/main"
      ]
    }
  }
}


# ============================================================
# GitHub Actions IAM Role
# ============================================================

# GitHub Actions가 OIDC 인증을 통해 임시 자격 증명을
# 발급받을 때 사용할 IAM Role
resource "aws_iam_role" "github_actions" {
  name = "${local.name_prefix}-github-actions-role"

  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  tags = {
    Name = "${local.name_prefix}-github-actions-role"
  }
}


# ============================================================
# GitHub Actions ECR Push 권한
# ============================================================

# GitHub Actions가 프로젝트 ECR Repository에
# Docker 이미지를 Push할 수 있도록 최소 권한을 정의한다.
data "aws_iam_policy_document" "github_actions_ecr" {
  # Docker가 ECR에 로그인하기 위한 인증 토큰 발급 권한
  statement {
    sid    = "ECRLogin"
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken"
    ]

    resources = ["*"]
  }

  # 프로젝트에서 생성한 ECR Repository에만
  # 이미지 레이어와 매니페스트를 Push할 수 있도록 제한
  statement {
    sid    = "ECRPushImages"
    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart"
    ]

    resources = [
      for repository in aws_ecr_repository.app :
      repository.arn
    ]
  }
}


# GitHub Actions 전용 ECR Push IAM Policy
resource "aws_iam_policy" "github_actions_ecr" {
  name        = "${local.name_prefix}-github-actions-ecr-policy"
  description = "Allow GitHub Actions to build and push application images to ECR"

  policy = data.aws_iam_policy_document.github_actions_ecr.json

  tags = {
    Name = "${local.name_prefix}-github-actions-ecr-policy"
  }
}


# GitHub Actions IAM Role에 ECR Push 정책 연결
resource "aws_iam_role_policy_attachment" "github_actions_ecr" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_ecr.arn
}