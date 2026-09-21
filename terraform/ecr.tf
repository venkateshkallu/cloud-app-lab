locals {
  ecr_repositories = [
    "credentialing/frontend",
    "credentialing/cockpit",
    "credentialing/pipeline",
    "credentialing/excel-api"
  ]
}

resource "aws_ecr_repository" "credentialing" {
  for_each = toset(local.ecr_repositories)

  name                 = each.value
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.common_tags
}

resource "aws_ecr_lifecycle_policy" "credentialing" {
  for_each = aws_ecr_repository.credentialing

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1

        description = "Expire untagged images after 14 days"

        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }

        action = {
          type = "expire"
        }
      }
    ]
  })
}