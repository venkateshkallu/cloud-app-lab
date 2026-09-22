variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-1"
}

variable "vpc_id" {
  description = "Existing VPC ID"
  type        = string
}

variable "app_subnet_ids" {
  description = "Existing private application subnet IDs"
  type        = list(string)
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "cloud-app-lab"
}
