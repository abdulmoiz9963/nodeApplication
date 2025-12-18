# Terraform-based ECS Deployment

## Prerequisites

1. **AWS CLI configured** with appropriate permissions
2. **Terraform installed** (v1.6.0+)
3. **GitHub repository** with the following secrets:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`

## GitHub Secrets Configuration

Add these secrets to your GitHub repository:

1. Go to your GitHub repository
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Add the following secrets:

```
AWS_ACCESS_KEY_ID: Your AWS Access Key ID
AWS_SECRET_ACCESS_KEY: Your AWS Secret Access Key
```

## Manual Deployment Steps

### 1. Build and Push Images to ECR

```bash
# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com

# Build and push images
docker build -t <account-id>.dkr.ecr.us-east-1.amazonaws.com/microservice-gateway:latest ./gateway
docker build -t <account-id>.dkr.ecr.us-east-1.amazonaws.com/microservice-worker:latest ./worker

docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/microservice-gateway:latest
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/microservice-worker:latest
```

### 2. Deploy Everything with Terraform

```bash
# Navigate to terraform directory
cd terraform

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the infrastructure and services
terraform apply
```

### 3. Verify Deployment

```bash
# Get ALB DNS name
terraform output alb_dns_name

# Test the application
curl http://<ALB-DNS-NAME>/
curl http://<ALB-DNS-NAME>/api/data
```

## Automated Deployment (GitHub Actions)

Once you push to the `main` branch, GitHub Actions will:

1. Build and push Docker images to ECR
2. Run `terraform plan` and `terraform apply`
3. Deploy complete infrastructure and services

## What Terraform Manages

- **VPC**: Private/public subnets with NAT gateways
- **ECR**: Container image repositories
- **ALB**: Application Load Balancer with target groups
- **ECS**: Cluster, task definitions, and services
- **IAM**: Least-privilege roles
- **CloudWatch**: Logging and monitoring

## Cleanup

```bash
# Destroy all resources
cd terraform
terraform destroy
```
