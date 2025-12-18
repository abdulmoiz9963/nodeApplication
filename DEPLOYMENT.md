# Node.js Microservice ECS Deployment

## Architecture Overview

This solution deploys a Node.js microservice-based application on AWS ECS using:

- **AWS ECS Fargate**: Serverless container orchestration
- **Application Load Balancer (ALB)**: Routes traffic to containers
- **Amazon ECR**: Container image registry
- **GitHub Actions**: CI/CD pipeline
- **CloudWatch**: Logging and monitoring

### Architecture Components

```
Internet → ALB (Port 80) → ECS Tasks (Port 80) → Containers
```

- **Gateway Service**: Main API gateway (exposed via ALB)
- **Worker Service**: Backend processing service
- **MongoDB**: Database (can be added as separate service)

## Security Implementation

1. **Network Security**:
   - Containers run in private subnets with NAT Gateway
   - Security groups restrict access (ALB → ECS only)
   - No direct port 80 exposure on containers

2. **IAM Roles**:
   - `ecsTaskExecutionRole`: Minimal permissions for ECS task execution
   - `ecsTaskRole`: Application-specific permissions

3. **Container Security**:
   - Non-root user in containers
   - Minimal base images (Alpine Linux)

## Deployment Steps

### 1. Prerequisites

- AWS CLI configured with appropriate permissions
- GitHub repository with secrets configured:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`

### 2. Initial Infrastructure Setup

```bash
# Run the infrastructure setup script
./setup-aws-infrastructure.sh
```

This creates:
- VPC with public subnets
- Security groups
- Application Load Balancer
- Target groups
- ECS cluster
- ECR repositories
- IAM roles
- CloudWatch log groups

### 3. Deploy ECS Services

```bash
# Create and deploy ECS services
./create-ecs-services.sh
```

### 4. Configure Auto-scaling (Optional)

```bash
# Setup auto-scaling policies
./setup-autoscaling.sh
```

### 5. GitHub Actions Setup

1. Push code to `main` branch
2. GitHub Actions will automatically:
   - Build Docker images
   - Push to ECR
   - Update ECS task definitions
   - Deploy new versions

## CI/CD Pipeline

The GitHub Actions workflow (`.github/workflows/deploy.yml`) performs:

1. **Build Phase**:
   - Checkout code
   - Configure AWS credentials
   - Login to ECR
   - Build Docker images for both services

2. **Deploy Phase**:
   - Push images to ECR
   - Update ECS task definitions
   - Deploy to ECS services
   - Wait for deployment stability

## Verification

### Check Application Status

```bash
# Get ALB DNS name
aws elbv2 describe-load-balancers --names microservice-alb --query 'LoadBalancers[0].DNSName' --output text

# Test gateway service
curl http://<ALB-DNS-NAME>/

# Test worker service (via gateway)
curl http://<ALB-DNS-NAME>/api/data
```

### Monitor Services

```bash
# Check ECS service status
aws ecs describe-services --cluster microservice-cluster --services gateway-service worker-service

# View logs
aws logs tail /ecs/gateway-task --follow
aws logs tail /ecs/worker-task --follow
```

## Rollback Strategy

Use the rollback script for failed deployments:

```bash
# Rollback to previous revision
./rollback-deployment.sh gateway-service 5
./rollback-deployment.sh worker-service 3
```

## Auto-scaling Configuration

- **Target**: 70% CPU utilization
- **Min Capacity**: 1 task
- **Max Capacity**: 10 tasks
- **Scale-out Cooldown**: 5 minutes
- **Scale-in Cooldown**: 5 minutes

## Cost Optimization

- Uses Fargate Spot for non-production environments
- Auto-scaling prevents over-provisioning
- CloudWatch logs retention set to 7 days

## Troubleshooting

### Common Issues

1. **Task fails to start**:
   - Check CloudWatch logs
   - Verify IAM permissions
   - Check security group rules

2. **ALB health checks failing**:
   - Verify container port mapping
   - Check application health endpoint
   - Review target group configuration

3. **GitHub Actions failing**:
   - Verify AWS credentials in secrets
   - Check ECR repository permissions
   - Validate task definition syntax

### Useful Commands

```bash
# Check running tasks
aws ecs list-tasks --cluster microservice-cluster

# Describe task details
aws ecs describe-tasks --cluster microservice-cluster --tasks <task-arn>

# View service events
aws ecs describe-services --cluster microservice-cluster --services gateway-service --query 'services[0].events'
```

## Security Best Practices Implemented

- ✅ No direct port 80 exposure on containers
- ✅ Least-privilege IAM roles
- ✅ Private container networking
- ✅ Secure image registry (ECR)
- ✅ Container runs as non-root user
- ✅ Network segmentation with security groups
- ✅ Encrypted logs in CloudWatch
- ✅ No hardcoded secrets in code
