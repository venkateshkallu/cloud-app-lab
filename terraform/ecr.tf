locals {
  ecr_repositories = [
    "cloudapplab/frontend",
    "cloudapplab/cockpit",
    "cloudapplab/pipeline",
    "cloudapplab/excel-api"
  ]
}

resource "aws_ecr_repository" "cloudapplab" {
  for_each = toset(local.ecr_repositories)

  name                 = each.value
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.common_tags
}

resource "aws_ecr_lifecycle_policy" "cloudapplab" {
  for_each = aws_ecr_repository.cloudapplab

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 14 days"

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