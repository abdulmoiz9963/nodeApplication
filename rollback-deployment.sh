#!/bin/bash

REGION="us-east-1"
CLUSTER_NAME="microservice-cluster"
SERVICE_NAME=$1
REVISION=$2

if [ -z "$SERVICE_NAME" ] || [ -z "$REVISION" ]; then
    echo "Usage: $0 <service-name> <task-definition-revision>"
    echo "Example: $0 gateway-service 5"
    exit 1
fi

echo "Rolling back $SERVICE_NAME to revision $REVISION..."

# Get the task definition family
TASK_DEF_FAMILY=$(aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --query 'services[0].taskDefinition' --output text --region $REGION | cut -d'/' -f2 | cut -d':' -f1)

# Update service to use previous revision
aws ecs update-service \
  --cluster $CLUSTER_NAME \
  --service $SERVICE_NAME \
  --task-definition $TASK_DEF_FAMILY:$REVISION \
  --region $REGION

echo "Rollback initiated. Waiting for service stability..."

# Wait for service to stabilize
aws ecs wait services-stable \
  --cluster $CLUSTER_NAME \
  --services $SERVICE_NAME \
  --region $REGION

echo "Rollback completed successfully!"

# Show current service status
aws ecs describe-services \
  --cluster $CLUSTER_NAME \
  --services $SERVICE_NAME \
  --query 'services[0].{ServiceName:serviceName,TaskDefinition:taskDefinition,RunningCount:runningCount,DesiredCount:desiredCount}' \
  --output table \
  --region $REGION
