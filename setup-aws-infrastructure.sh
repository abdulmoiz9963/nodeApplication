#!/bin/bash

# Variables
REGION="us-east-1"
CLUSTER_NAME="microservice-cluster"
VPC_NAME="microservice-vpc"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Setting up AWS infrastructure..."
echo "Account ID: $ACCOUNT_ID"
echo "Region: $REGION"

# Create ECR repositories
echo "Creating ECR repositories..."
aws ecr create-repository --repository-name microservice-gateway --region $REGION || true
aws ecr create-repository --repository-name microservice-worker --region $REGION || true

# Create VPC and networking
echo "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --region $REGION --query 'Vpc.VpcId' --output text)
aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=$VPC_NAME --region $REGION

# Create Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway --region $REGION --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID --region $REGION

# Create public subnets
SUBNET1_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --availability-zone ${REGION}a --region $REGION --query 'Subnet.SubnetId' --output text)
SUBNET2_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --availability-zone ${REGION}b --region $REGION --query 'Subnet.SubnetId' --output text)

# Create route table and routes
ROUTE_TABLE_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --region $REGION --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $ROUTE_TABLE_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID --region $REGION
aws ec2 associate-route-table --subnet-id $SUBNET1_ID --route-table-id $ROUTE_TABLE_ID --region $REGION
aws ec2 associate-route-table --subnet-id $SUBNET2_ID --route-table-id $ROUTE_TABLE_ID --region $REGION

# Create security groups
ALB_SG_ID=$(aws ec2 create-security-group --group-name alb-sg --description "ALB Security Group" --vpc-id $VPC_ID --region $REGION --query 'GroupId' --output text)
ECS_SG_ID=$(aws ec2 create-security-group --group-name ecs-sg --description "ECS Security Group" --vpc-id $VPC_ID --region $REGION --query 'GroupId' --output text)

# ALB security group rules
aws ec2 authorize-security-group-ingress --group-id $ALB_SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0 --region $REGION
aws ec2 authorize-security-group-ingress --group-id $ALB_SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0 --region $REGION

# ECS security group rules
aws ec2 authorize-security-group-ingress --group-id $ECS_SG_ID --protocol tcp --port 80 --source-group $ALB_SG_ID --region $REGION

# Create Application Load Balancer
ALB_ARN=$(aws elbv2 create-load-balancer --name microservice-alb --subnets $SUBNET1_ID $SUBNET2_ID --security-groups $ALB_SG_ID --region $REGION --query 'LoadBalancers[0].LoadBalancerArn' --output text)

# Create target groups
GATEWAY_TG_ARN=$(aws elbv2 create-target-group --name gateway-tg --protocol HTTP --port 80 --vpc-id $VPC_ID --target-type ip --health-check-path / --region $REGION --query 'TargetGroups[0].TargetGroupArn' --output text)
WORKER_TG_ARN=$(aws elbv2 create-target-group --name worker-tg --protocol HTTP --port 80 --vpc-id $VPC_ID --target-type ip --health-check-path /api/data --region $REGION --query 'TargetGroups[0].TargetGroupArn' --output text)

# Create ALB listener
aws elbv2 create-listener --load-balancer-arn $ALB_ARN --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=$GATEWAY_TG_ARN --region $REGION

# Create ECS cluster
aws ecs create-cluster --cluster-name $CLUSTER_NAME --region $REGION

# Create IAM roles
echo "Creating IAM roles..."

# ECS Task Execution Role
aws iam create-role --role-name ecsTaskExecutionRole --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}' || true

aws iam attach-role-policy --role-name ecsTaskExecutionRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# ECS Task Role
aws iam create-role --role-name ecsTaskRole --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}' || true

# Create CloudWatch log groups
aws logs create-log-group --log-group-name /ecs/gateway-task --region $REGION || true
aws logs create-log-group --log-group-name /ecs/worker-task --region $REGION || true

echo "Infrastructure setup complete!"
echo "VPC ID: $VPC_ID"
echo "Subnet IDs: $SUBNET1_ID, $SUBNET2_ID"
echo "ALB ARN: $ALB_ARN"
echo "Gateway Target Group ARN: $GATEWAY_TG_ARN"
echo "Worker Target Group ARN: $WORKER_TG_ARN"
echo "ECS Security Group ID: $ECS_SG_ID"

# Update task definitions with actual account ID
sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" task-definition-gateway.json
sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" task-definition-worker.json

echo "Task definitions updated with Account ID: $ACCOUNT_ID"
