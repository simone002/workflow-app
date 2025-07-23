#!/bin/bash

set -e
REGION="eu-west-1"

echo "Stopping services to save costs..."
echo "This will stop ECS and delete RDS, Cognito, SNS, SQS"
echo "Keeps S3 and ECR for quick restart"

read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 1
fi

# Stop ECS
echo "Stopping ECS..."
aws ecs update-service --cluster workflow-cluster --service workflow-backend-service --desired-count 0 --region $REGION

# Wait for ECS to stop
while true; do
    COUNT=$(aws ecs describe-services --cluster workflow-cluster --services workflow-backend-service --query 'services[0].runningCount' --output text --region $REGION 2>/dev/null || echo "0")
    if [ "$COUNT" = "0" ]; then break; fi
    echo "Waiting for ECS to stop..."
    sleep 10
done
echo "ECS stopped"

# Delete RDS with snapshot
echo "Deleting RDS..."
SNAPSHOT_ID="workflow-db-backup-$(date +%Y%m%d-%H%M)"
aws rds delete-db-instance --db-instance-identifier workflow-db --final-db-snapshot-identifier "$SNAPSHOT_ID" --no-skip-final-snapshot --region $REGION

# Delete Cognito
echo "Deleting Cognito..."
USER_POOLS=$(aws cognito-idp list-user-pools --max-results 60 --query "UserPools[?contains(Name, 'workflow')].Id" --output text --region $REGION 2>/dev/null || echo "")
for pool_id in $USER_POOLS; do
    aws cognito-idp delete-user-pool --user-pool-id $pool_id --region $REGION 2>/dev/null || true
done

# Delete SNS
echo "Deleting SNS..."
SNS_TOPICS=$(aws sns list-topics --query "Topics[?contains(TopicArn, 'workflow')].TopicArn" --output text --region $REGION 2>/dev/null || echo "")
for topic_arn in $SNS_TOPICS; do
    aws sns delete-topic --topic-arn "$topic_arn" --region $REGION 2>/dev/null || true
done

# Delete SQS
echo "Deleting SQS..."
SQS_QUEUES=$(aws sqs list-queues --queue-name-prefix workflow --query 'QueueUrls[]' --output text --region $REGION 2>/dev/null || echo "")
for queue_url in $SQS_QUEUES; do
    aws sqs delete-queue --queue-url "$queue_url" --region $REGION 2>/dev/null || true
done

echo ""
echo "Cleanup complete!"
echo "Costs reduced from ~$10/month to ~$0.50/month"
echo ""
echo "Kept:"
echo "- S3 bucket and ECR repository"
echo "- ECS cluster and task definitions"
echo "- Database snapshot: $SNAPSHOT_ID"
echo ""
echo "To restart: ./deploy.sh"