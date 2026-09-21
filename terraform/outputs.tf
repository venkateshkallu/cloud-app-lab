output "ecr_repository_urls" {
  description = "Credentialing ECR repository URLs"

  value = {
    for name, repository in aws_ecr_repository.credentialing :
    name => repository.repository_url
  }
}