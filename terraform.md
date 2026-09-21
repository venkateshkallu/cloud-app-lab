
                         GitHub
                           │
                           │ CI/CD
                           ▼
                    GitHub Actions
                           │
                           ▼
                         AWS
                           │
        ┌──────────────────┴──────────────────┐
        │                                     │
       ECR                              AWS Foundation
        │                                     │
        │                              ┌──────┴──────┐
        │                              │             │
        │                             VPC           IAM
        │                              │
        │                       ┌──────┴──────┐
        │                       │             │
        │                  Public Subnet   Private Subnets
        │                                     │
        │                                     ▼
        │                                   EKS
        │                                     │
        │                         ┌───────────┼───────────┐
        │                         │           │           │
        ▼                         ▼           ▼           ▼
 Docker Images               Frontend    Cockpit    Pipeline
                                                   │
                                                   ▼
                                                Excel API
                                                    │
                                                    ▼
                                             PostgreSQL/RDS





terraform/
│
├── providers.tf
├── versions.tf
├── variables.tf
├── outputs.tf
├── main.tf
│
├── modules/
│   ├── networking/
│   ├── iam/
│   ├── ecr/
│   ├── database/
│   ├── secrets/
│   └── monitoring/
│
└── environments/
    ├── dev/
    ├── staging/
    └── prod/




A. Networking

Terraform should eventually manage:

VPC
├── Internet Gateway
├── Public Subnets
├── Private Subnets
├── Route Tables
├── NAT Gateway(s)
└── Security Groups

The plan explicitly calls for AWS networking and security controls to be managed through Terraform.

B. ECR

One repository for each containerized service is a reasonable starting design:

ECR
├── credentialing-frontend
├── credentialing-cockpit
├── credentialing-pipeline
└── credentialing-excel-api

The implementation plan specifically says container images should be pushed to Amazon ECR and tagged immutably.

C. IAM

We'll eventually need IAM for:

GitHub Actions → AWS
EKS → AWS resources
Application workloads → required AWS services

The plan specifically recommends GitHub Actions OIDC rather than long-lived AWS credentials and least-privilege IAM.

D. Database

The plan recommends managed PostgreSQL such as RDS for production, with the database private and backups enabled.

But we should not create the RDS Terraform module yet because the developer still needs to confirm the application's actual database/environment requirements.

E. Secrets

Eventually:

AWS Secrets Manager
├── DB credentials
├── OpenAI credentials
├── Bullhorn credentials
├── SendGrid credentials
└── application tokens

The plan explicitly says secrets must not be stored in source code or container images.
