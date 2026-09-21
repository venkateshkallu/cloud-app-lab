# Credentialing Application – DevOps & CI/CD Documentation

## 1. Project Overview

The Credentialing application is a multi-service application consisting of a frontend, backend APIs, and supporting services.

The DevOps setup focuses on:

- Standardized development workflow
- CI automation using GitHub Actions
- Code quality and security checks
- Docker containerization
- Secret scanning
- SonarQube code analysis
- Preparing the application for container-based deployment

---

# 2. Application Components

The application currently contains the following major services:

| Component | Technology | Port |
|---|---|---:|
| Frontend | React / Node.js | 3000 |
| Excel API | Node.js | 8002 |
| Cockpit API | Python / Flask | 8004 |
| Pipeline API | Python / Flask | 5001 |
| Database | PostgreSQL | 5432 |

> Ports should always be verified against the application configuration before deployment.

---

# 3. High-Level Architecture

```text
                         GitHub Repository
                                |
                                |
                         Pull Request / Push
                                |
                                v
                     +----------------------+
                     |   GitHub Actions     |
                     |        CI            |
                     +----------+-----------+
                                |
             +------------------+------------------+
             |                  |                  |
             v                  v                  v
        Frontend CI        Node API CI        Python CI
             |                  |                  |
             +------------------+------------------+
                                |
                                v
                     Security & Quality Checks
                                |
          +---------------------+---------------------+
          |           |            |          |       |
          v           v            v          v       v
        Ruff       Bandit      pip-audit  Gitleaks SonarQube
                                |
                                v
                       Docker Image Build
                                |
                                v
                         Deployment Stage

```


# 4. Git Branching Strategy

The current development workflow follows:

feature/*
    |
    v
Pull Request
    |
    v
develop
    |
    v
CI/CD
    |
    v
Deployment Environment
Branches
main → Production
develop → Development integration
staging → Staging environment
feature/* → Developer feature work

Example:

feature/credentialing-ci
        |
        | Pull Request
        v
     develop

# 5. CI/CD Workflow

The GitHub Actions workflow is located at:

.github/workflows/ci.yml

Workflow name:

Credentialing CI

The workflow runs for:

Pull Requests
main
develop
staging
Pushes
main
develop
staging
feature/**

# 6. CI Pipeline Stages

The current CI pipeline contains the following checks:

Frontend CI
     |
Excel API CI
     |
Python CI
     |
Ruff
     |
Bandit
     |
pip-audit
     |
Gitleaks
     |
SonarQube

Each stage validates a different part of the application.

7. Frontend CI

The frontend job runs inside:

cred_frontend/
Steps
Checkout code
      |
Setup Node.js 20
      |
Install dependencies
      |
npm run lint
      |
npm test
      |
npm run build

The build confirms that the frontend can be successfully compiled.

# 8. Excel API CI

The Excel API is located at:

cred_frontend/excel-api/
Steps
Checkout code
      |
Setup Node.js 20
      |
npm ci
      |
npm test
      |
node --check index.js

The JavaScript syntax check ensures that the application entry point is valid.

# 9. Python CI

Python services are located under:

cred_deploy/

The CI environment uses:

Python 3.12
Steps
Checkout code
      |
Setup Python 3.12
      |
Install dependencies
      |
Install pytest
      |
Run pytest

Command:

python -m pytest -v

# 10. Ruff – Python Code Quality

Ruff is used for Python linting and code quality checks.

Version:

ruff 0.16.5

Command:

ruff check . --exclude "presync*" --output-format=concise

Ruff helps identify:

Unused imports
Code quality issues
Formatting-related issues
Python best-practice violations

# 11. Bandit – Python Security Scan

Bandit performs static security analysis of Python code.

The project uses:

bandit[toml]

Configuration:

pyproject.toml

Command:

bandit -c pyproject.toml -r .

Bandit helps identify potentially unsafe Python coding patterns.


# 12. pip-audit – Dependency Security

pip-audit checks Python dependencies for known security vulnerabilities.

Command:

pip-audit -r requirements.txt

This provides a dependency-level security check in CI.


# 13. Gitleaks – Secret Scanning

Gitleaks has been integrated into the CI pipeline to detect accidentally committed secrets.

The pipeline uses:

- name: Run Gitleaks
  uses: gitleaks/gitleaks-action@v2
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

Gitleaks checks the repository for potential:

API keys
Passwords
Access tokens
Private keys
Other accidentally committed credentials
Important Security Rule

No real credentials should be committed to Git.

No API keys, passwords, or credentials should be copied into or baked into a Docker image.

# 14. SonarQube

SonarQube is integrated with GitHub Actions for source-code analysis.

SonarQube server:

https://sonarqube.acap.aequor.com

The workflow analyzes:

cred_deploy
cred_frontend

Generated and dependency directories are excluded from analysis.

Purpose

SonarQube provides:

Code quality analysis
Security analysis
Maintainability checks
Code issue detection
Quality Gate evaluation

# 15. Docker Architecture

The application contains separate Dockerfiles for the different services.

Credentialing/
│
├── cred_deploy/
│   ├── Dockerfile
│   └── Dockerfile.pipeline
│
└── cred_frontend/
    ├── Dockerfile
    │
    └── excel-api/
        └── Dockerfile

# 16. Frontend Docker Image

The frontend uses a multi-stage Docker build.

Node.js
   |
   v
Install dependencies
   |
   v
Build React application
   |
   v
/dist
   |
   v
Nginx
   |
   v
Production container

The final image uses Nginx to serve the built frontend.

# 17. Pipeline API Docker Image

The Pipeline API uses:

Python 3.12

The image installs:

poppler-utils

and the application dependencies.

The container runs the Pipeline API using:

Gunicorn

The configured application port is:

5001

Health endpoint:

/health

Example:

curl http://localhost:5001/health

Expected response:

{
  "api": "pipeline",
  "status": "ok"
}

# 18. Cockpit API Docker Image

The Cockpit API is a Python/Flask service.

Current configured application port:

8004

The service also uses Poppler for document processing.

The Linux Docker environment installs:

poppler-utils

The bundled Windows Poppler path should not be relied upon when the application is running inside the Linux container.

# 19. Excel API Docker Image

The Excel API is a Node.js service.

Configured port:

8002

The service connects to PostgreSQL.

Expected database configuration includes:

DB_HOST
DB_USER
DB_PASSWORD
DB_NAME
DB_PORT

PostgreSQL uses:

5432

# 20. Secrets and Environment Configuration

Sensitive configuration must never be committed to Git or baked into Docker images.

Examples:

OPENAI_API_KEY
DB_PASSWORD
API tokens
Service credentials
Correct approach
Docker Image
     |
     | Application + Dependencies only
     v
Container Runtime
     |
     | Inject secrets
     v
Environment Variables / Secret Manager

The Docker image should not contain:

.env
API keys
Passwords
Private keys
Database credentials

.env.example can be used as a configuration reference without real credentials.

# 21. OPENAI_API_KEY in CI

The application currently initializes the OpenAI client during import.

Because of this, the CI test environment requires an OPENAI_API_KEY value during test collection.

A CI-only placeholder can be provided for tests that do not actually make an OpenAI API request.

Example:

env:
  OPENAI_API_KEY: "ci-placeholder"

No production API key should be committed to the repository.

# 22. Database

The application uses:

PostgreSQL

Expected PostgreSQL port:

5432

Database credentials should be provided through environment variables or an approved secret-management mechanism.

The database should not be packaged inside the application Docker image.

# 23. Container Security Principles

The Docker images follow these principles:

Use official base images
Install only required packages
Do not copy secrets into images
Run application processes as a non-root user where practical
Keep images minimal
Use .dockerignore
Scan images before deployment

Example:

Source Code
     |
     v
Docker Build
     |
     v
Docker Image
     |
     v
Security Scan
     |
     v
Container Registry
     |
     v
Deployment

# 24. Local Docker Validation

Each service can be built and tested independently.

Pipeline API
docker build --no-cache `
  -f .\cred_deploy\Dockerfile.pipeline `
  -t credentialing-pipeline `
  .\cred_deploy

Run:

docker run --rm -p 5001:5001 credentialing-pipeline

Health check:

curl.exe http://localhost:5001/health
Excel API

Build:

docker build `
  -f .\cred_frontend\excel-api\Dockerfile `
  -t credentialing-excel-api `
  .\cred_frontend\excel-api

Run:

docker run --rm -p 8002:8002 credentialing-excel-api

# 25. Current DevOps Status
Area	Status
Git branching workflow	Completed
GitHub Actions CI	Implemented
Frontend CI	Implemented
Excel API CI	Implemented
Python CI	Implemented
Ruff	Integrated
Bandit	Integrated
pip-audit	Integrated
Gitleaks	Integrated
SonarQube	Integrated
Frontend Dockerfile	Created / validated
Pipeline Dockerfile	Created / validated
Cockpit Dockerfile	Created / validated
Excel API Dockerfile	Created / validated
Local Docker health checks	Partially validated
Full application integration	Pending
Production deployment	Pending application/infrastructure confirmation
AWS infrastructure	Pending final infrastructure design
Kubernetes/EKS deployment	Future deployment phase
Production CD	Pending

# 26. Important Pending Items

The following items require confirmation before production deployment:

Final service-to-service configuration
Production environment variables
Database connection details
Final service port mapping
Production secrets management
Container registry configuration
AWS infrastructure configuration
Deployment environment
Production health checks
Rollback procedure

These should be confirmed with the development and infrastructure teams before production deployment.

# 27. Recommended Production Flow

The target production flow is:

Developer
   |
   v
Feature Branch
   |
   v
Pull Request
   |
   v
GitHub Actions
   |
   +--> Tests
   |
   +--> Ruff
   |
   +--> Bandit
   |
   +--> pip-audit
   |
   +--> Gitleaks
   |
   +--> SonarQube
   |
   v
Docker Build
   |
   v
Container Security Scan
   |
   v
Container Registry
   |
   v
Kubernetes / AWS
   |
   v
Health Check
   |
   v
Production

# 28. Demo Flow

During the demo, the CI/CD implementation can be demonstrated practically using the following flow:

Step 1 – Developer creates a feature branch
git checkout -b feature/example-change
Step 2 – Developer pushes the branch
git push origin feature/example-change
Step 3 – Create Pull Request
feature/example-change
          |
          v
       develop
Step 4 – GitHub Actions starts

The workflow automatically executes:

Frontend CI
Excel API CI
Python CI
Ruff
Bandit
pip-audit
Gitleaks
SonarQube
Step 5 – Review Results

The team can inspect:

Test results
Lint results
Security scan results
Gitleaks results
SonarQube analysis
Step 6 – Merge

After the required checks and review are successful:

Pull Request
     |
     v
develop

# 29. Key Security Principles

The project follows these basic DevSecOps principles:

Code
  ↓
Test
  ↓
Lint
  ↓
Security Scan
  ↓
Secret Scan
  ↓
Code Quality
  ↓
Build
  ↓
Container Security
  ↓
Deploy

The main principle is:

Secrets belong in runtime configuration or approved secret management, never inside source code or Docker images.

# 30. Summary

The Credentialing project now has a standardized CI foundation using GitHub Actions.

The pipeline performs application validation, Python quality checks, dependency security scanning, secret scanning, and SonarQube analysis.

Dockerization has also been started and the individual application services have been validated locally.

The remaining work is primarily around final application configuration, production infrastructure, container registry, deployment configuration, and the complete production CD flow.


### For her demo

I would **not make her read the whole document**. Use it as the demo reference, and have her demonstrate this practical flow:

**GitHub PR → Actions → Tests → Ruff → Bandit → pip-audit → Gitleaks → SonarQube → Docker → deployment architecture.**

That will make the demo look like an actual **DevOps implementation**, rather than just explaining what each tool does.