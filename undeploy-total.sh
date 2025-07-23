#!/bin/bash

set -e
REGION="eu-west-1"

echo "WARNING: This will delete ALL project resources"
echo "ECS, RDS (no backup), S3, ECR, Cognito, SNS, SQS, IAM"

read -p "Type 'DELETE' to confirm: " CONFIRMATION
if [ "$CONFIRMATION" != "DELETE" ]; then
    echo "Cancelled"
    exit 1
fi

echo "Deleting everything..."

# ECS
echo "Deleting ECS..."
aws ecs update-service --cluster workflow-cluster --service workflow-backend-service --desired-count 0 --region $REGION >/dev/null 2>&1 || true
aws ecs delete-service --cluster workflow-cluster --service workflow-backend-service --force --region $REGION >/dev/null 2>&1 || true
aws ecs delete-cluster --cluster workflow-cluster --region $REGION >/dev/null 2>&1 || true

# RDS (no backup)
echo "Deleting RDS..."
aws rds delete-db-instance --db-instance-identifier workflow-db --skip-final-snapshot --region $REGION >/dev/null 2>&1 || true

# S3
echo "Deleting S3..."
BUCKET_NAME=$(aws s3api list-buckets --query 'Buckets[?contains(Name, `workflow-frontend`)].Name' --output text 2>/dev/null | head -1)
if [ -n "$BUCKET_NAME" ]; then
    aws s3 rb "s3://$BUCKET_NAME" --force --region $REGION >/dev/null 2>&1 || true
fi

# ECR
echo "Deleting ECR..."
aws ecr delete-repository --repository-name workflow-backend --force --region $REGION >/dev/null 2>&1 || true

# Cognito
echo "Deleting Cognito..."
USER_POOLS=$(aws cognito-idp list-user-pools --max-results 60 --query "UserPools[?contains(Name, 'workflow')].Id" --output text --region $REGION 2>/dev/null || echo "")
for pool_id in $USER_POOLS; do
    aws cognito-idp delete-user-pool --user-pool-id $pool_id --region $REGION >/dev/null 2>&1 || true
done

# SNS
echo "Deleting SNS..."
SNS_TOPICS=$(aws sns list-topics --query "Topics[?contains(TopicArn, 'workflow')].TopicArn" --output text --region $REGION 2>/dev/null || echo "")
for topic_arn in $SNS_TOPICS; do
    aws sns delete-topic --topic-arn "$topic_arn" --region $REGION >/dev/null 2>&1 || true
done

# SQS
echo "Deleting SQS..."
SQS_QUEUES=$(aws sqs list-queues --queue-name-prefix workflow --query 'QueueUrls[]' --output text --region $REGION 2>/dev/null || echo "")
for queue_url in $SQS_QUEUES; do
    aws sqs delete-queue --queue-url "$queue_url" --region $REGION >/dev/null 2>&1 || true
done

# IAM
echo "Deleting IAM..."
ROLE_NAME="WorkflowTaskRole"
POLICY_ARN=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='WorkflowAppPermissions'].Arn" --output text --region $REGION 2>/dev/null || echo "")
if [ -n "$POLICY_ARN" ]; then
    aws iam detach-role-policy --role-name $ROLE_NAME --policy-arn $POLICY_ARN --region $REGION >/dev/null 2>&1 || true
    aws iam delete-policy --policy-arn $POLICY_ARN --region $REGION >/dev/null 2>&1 || true
fi
aws iam delete-role --role-name $ROLE_NAME --region $REGION >/dev/null 2>&1 || true

# CloudWatch logs
echo "Deleting logs..."
aws logs delete-log-group --log-group-name "/ecs/workflow-simple" --region $REGION >/dev/null 2>&1 || true

echo ""
echo "Complete deletion finished"
echo "All project resources removed"