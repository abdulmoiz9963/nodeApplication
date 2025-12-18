#!/bin/bash

# Variables
REGION="us-east-1"
CLUSTER_NAME="microservice-cluster"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Get VPC and subnet information
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=microservice-vpc" --query 'Vpcs[0].VpcId' --output text --region $REGION)
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[].SubnetId' --output text --region $REGION)
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=ecs-sg" --query 'SecurityGroups[0].GroupId' --output text --region $REGION)

# Get target group ARNs
GATEWAY_TG_ARN=$(aws elbv2 describe-target-groups --names gateway-tg --query 'TargetGroups[0].TargetGroupArn' --output text --region $REGION)
WORKER_TG_ARN=$(aws elbv2 describe-target-groups --names worker-tg --query 'TargetGroups[0].TargetGroupArn' --output text --region $REGION)

echo "Creating ECS services..."
echo "VPC ID: $VPC_ID"
echo "Subnets: $SUBNET_IDS"
echo "Security Group: $SECURITY_GROUP_ID"

# Register task definitions
aws ecs register-task-definition --cli-input-json file://task-definition-gateway.json --region $REGION
aws ecs register-task-definition --cli-input-json file://task-definition-worker.json --region $REGION

# Create gateway service
aws ecs create-service \
  --cluster $CLUSTER_NAME \
  --service-name gateway-service \
  --task-definition gateway-task \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_IDS],securityGroups=[$SECURITY_GROUP_ID],assignPublicIp=ENABLED}" \
  --load-balancers targetGroupArn=$GATEWAY_TG_ARN,containerName=gateway,containerPort=80 \
  --region $REGION

# Create worker service
aws ecs create-service \
  --cluster $CLUSTER_NAME \
  --service-name worker-service \
  --task-definition worker-task \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_IDS],securityGroups=[$SECURITY_GROUP_ID],assignPublicIp=ENABLED}" \
  --load-balancers targetGroupArn=$WORKER_TG_ARN,containerName=worker,containerPort=80 \
  --region $REGION

echo "ECS services created successfully!"

# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers --names microservice-alb --query 'LoadBalancers[0].DNSName' --output text --region $REGION)
echo "Application accessible at: http://$ALB_DNS"
