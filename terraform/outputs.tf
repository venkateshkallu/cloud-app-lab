output "ecr_repository_urls" {
  description = "CloudAppLab ECR repository URLs"

  value = {
    for name, repository in aws_ecr_repository.cloudapplab :
    name => repository.repository_url
  }
}

output "eks_cluster_name" {
  description = "CloudAppLab EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "CloudAppLab EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}