#!/bin/bash

set -e

REGION="eu-west-1"
APP_NAME="workflow"

echo "Starting deployment..."

# Check current state
ECS_COUNT=$(aws ecs describe-services --cluster workflow-cluster --services workflow-backend-service --query 'services[0].runningCount' --output text 2>/dev/null || echo "0")
RDS_STATUS=$(aws rds describe-db-instances --db-instance-identifier workflow-db --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || echo "NOT_FOUND")

echo "Current state - ECS: $ECS_COUNT, RDS: $RDS_STATUS"

# 1. Setup Cognito
echo "1. Setting up Cognito..."
EXISTING_POOLS=$(aws cognito-idp list-user-pools --max-results 60 --query "UserPools[?contains(Name, '${APP_NAME}-users')].Id" --output text --region $REGION 2>/dev/null || echo "")

if [ -n "$EXISTING_POOLS" ]; then
    USER_POOL_ID=$(echo $EXISTING_POOLS | cut -d' ' -f1)
    USER_POOL_CLIENT_ID=$(aws cognito-idp list-user-pool-clients --user-pool-id $USER_POOL_ID --query 'UserPoolClients[0].ClientId' --output text --region $REGION)
    echo "Found existing pool: $USER_POOL_ID"
else
    USER_POOL_ID=$(aws cognito-idp create-user-pool --pool-name "${APP_NAME}-users" --policies '{"PasswordPolicy":{"MinimumLength":6,"RequireUppercase":false,"RequireLowercase":false,"RequireNumbers":false,"RequireSymbols":false}}' --username-attributes "email" --auto-verified-attributes "email" --query 'UserPool.Id' --output text --region $REGION)
    USER_POOL_CLIENT_ID=$(aws cognito-idp create-user-pool-client --user-pool-id $USER_POOL_ID --client-name "${APP_NAME}-client" --explicit-auth-flows "ADMIN_NO_SRP_AUTH" "USER_PASSWORD_AUTH" --query 'UserPoolClient.ClientId' --output text --region $REGION)
    echo "Created pool: $USER_POOL_ID"
fi

# 2. Setup SNS and SQS
echo "2. Setting up messaging..."
EXISTING_TOPICS=$(aws sns list-topics --query "Topics[?contains(TopicArn, '${APP_NAME}-notifications')].TopicArn" --output text --region $REGION 2>/dev/null || echo "")
if [ -n "$EXISTING_TOPICS" ]; then
    SNS_TOPIC_ARN=$(echo $EXISTING_TOPICS | cut -d' ' -f1)
else
    SNS_TOPIC_ARN=$(aws sns create-topic --name "${APP_NAME}-notifications" --query 'TopicArn' --output text --region $REGION)
fi

EXISTING_QUEUES=$(aws sqs list-queues --queue-name-prefix "${APP_NAME}-tasks" --query 'QueueUrls[0]' --output text --region $REGION 2>/dev/null || echo "None")
if [ "$EXISTING_QUEUES" != "None" ] && [ -n "$EXISTING_QUEUES" ]; then
    SQS_QUEUE_URL="$EXISTING_QUEUES"
else
    SQS_QUEUE_URL=$(aws sqs create-queue --queue-name "${APP_NAME}-tasks" --attributes "VisibilityTimeout=300,MessageRetentionPeriod=1209600,DelaySeconds=0" --query 'QueueUrl' --output text --region $REGION)
fi

# Connect SNS to SQS
SQS_QUEUE_ARN=$(aws sqs get-queue-attributes --queue-url $SQS_QUEUE_URL --attribute-names QueueArn --query 'Attributes.QueueArn' --output text --region $REGION)
aws sns subscribe --topic-arn $SNS_TOPIC_ARN --protocol sqs --notification-endpoint $SQS_QUEUE_ARN --region $REGION >/dev/null 2>&1 || true

# 3. Setup S3 for frontend
echo "3. Setting up S3..."
FRONTEND_BUCKET=$(aws s3api list-buckets --query 'Buckets[?starts_with(Name, `workflow-frontend`)].Name' --output text --region $REGION | head -1)

if [ -n "$FRONTEND_BUCKET" ] && [ "$FRONTEND_BUCKET" != "None" ]; then
    echo "Found S3 bucket: $FRONTEND_BUCKET"
else
    FRONTEND_BUCKET="workflow-frontend-$(date +%s)"
    aws s3 mb s3://$FRONTEND_BUCKET --region $REGION
    echo "Created S3 bucket: $FRONTEND_BUCKET"
fi

# Configure S3 for web hosting
aws s3api delete-public-access-block --bucket $FRONTEND_BUCKET --region $REGION 2>/dev/null || true

cat > bucket-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": "*",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::${FRONTEND_BUCKET}/*"
  }]
}
EOF

aws s3api put-bucket-policy --bucket $FRONTEND_BUCKET --policy file://bucket-policy.json --region $REGION 2>/dev/null || true
aws s3api put-bucket-website --bucket $FRONTEND_BUCKET --website-configuration '{"IndexDocument":{"Suffix":"index.html"},"ErrorDocument":{"Key":"index.html"}}' --region $REGION 2>/dev/null || true
rm bucket-policy.json

FRONTEND_URL="http://${FRONTEND_BUCKET}.s3-website-${REGION}.amazonaws.com"

# 4. Setup Database
echo "4. Setting up database..."
if [ "$RDS_STATUS" = "NOT_FOUND" ] || [ "$RDS_STATUS" = "deleted" ]; then
    aws rds create-db-instance --db-instance-identifier workflow-db --db-instance-class db.t3.micro --engine mysql --engine-version 8.0.35 --master-username admin --master-user-password WorkflowPass123! --allocated-storage 20 --storage-type gp2 --db-name workflow --backup-retention-period 7 --storage-encrypted --publicly-accessible --region $REGION
    
    echo "Waiting for database (this takes ~10 minutes)..."
    while true; do
        STATUS=$(aws rds describe-db-instances --db-instance-identifier workflow-db --query 'DBInstances[0].DBInstanceStatus' --output text --region $REGION 2>/dev/null || echo "creating")
        echo "Database status: $STATUS"
        if [ "$STATUS" = "available" ]; then break; fi
        sleep 30
    done
fi

# 5. Setup security groups
echo "5. Configuring security..."
DB_SG_ID=$(aws rds describe-db-instances --db-instance-identifier workflow-db --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' --output text --region $REGION)
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text --region $REGION)
SG_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=default" --query 'SecurityGroups[0].GroupId' --output text --region $REGION)

aws ec2 authorize-security-group-ingress --group-id $DB_SG_ID --protocol tcp --port 3306 --cidr 10.0.0.0/16 --region $REGION 2>/dev/null || true
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 3000 --cidr 0.0.0.0/0 --region $REGION 2>/dev/null || true

# 6. Create IAM role if needed
echo "6. Setting up IAM..."
ROLE_NAME="WorkflowTaskRole"
aws iam get-role --role-name $ROLE_NAME --region $REGION >/dev/null 2>&1 || {
    cat > trust-policy.json << EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF
    aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file://trust-policy.json --region $REGION
    
    cat > permissions.json << EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["sns:Publish","sqs:SendMessage","sqs:ReceiveMessage","cognito-idp:AdminCreateUser","cognito-idp:AdminSetUserPassword","cognito-idp:AdminInitiateAuth"],"Resource":"*"}]}
EOF
    POLICY_ARN=$(aws iam create-policy --policy-name WorkflowAppPermissions --policy-document file://permissions.json --query 'Policy.Arn' --output text --region $REGION)
    aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn $POLICY_ARN --region $REGION
    rm trust-policy.json permissions.json
}

# 7. Setup ECS
echo "7. Setting up containers..."
aws ecs describe-clusters --clusters workflow-cluster --region $REGION >/dev/null 2>&1 || aws ecs create-cluster --cluster-name workflow-cluster --capacity-providers FARGATE --region $REGION
aws ecr describe-repositories --repository-names workflow-backend --region $REGION >/dev/null 2>&1 || aws ecr create-repository --repository-name workflow-backend --region $REGION

# 8. Deploy backend
echo "8. Deploying backend..."
DB_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier workflow-db --query 'DBInstances[0].Endpoint.Address' --output text --region $REGION)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

cat > task-def.json << EOF
{
  "family": "workflow-backend",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::${ACCOUNT_ID}:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::${ACCOUNT_ID}:role/WorkflowTaskRole",
  "containerDefinitions": [{
    "name": "backend",
    "image": "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/workflow-backend:latest",
    "portMappings": [{"containerPort": 3000}],
    "environment": [
      {"name": "NODE_ENV", "value": "production"},
      {"name": "DB_HOST", "value": "$DB_ENDPOINT"},
      {"name": "DB_USER", "value": "admin"},
      {"name": "DB_PASSWORD", "value": "WorkflowPass123!"},
      {"name": "DB_NAME", "value": "workflow"},
      {"name": "JWT_SECRET", "value": "workflow-secret-$(date +%s)"},
      {"name": "PORT", "value": "3000"},
      {"name": "AWS_REGION", "value": "$REGION"},
      {"name": "COGNITO_USER_POOL_ID", "value": "$USER_POOL_ID"},
      {"name": "COGNITO_CLIENT_ID", "value": "$USER_POOL_CLIENT_ID"},
      {"name": "SNS_TOPIC_ARN", "value": "$SNS_TOPIC_ARN"},
      {"name": "SQS_QUEUE_URL", "value": "$SQS_QUEUE_URL"}
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/workflow-simple",
        "awslogs-region": "$REGION",
        "awslogs-stream-prefix": "ecs",
        "awslogs-create-group": "true"
      }
    }
  }]
}
EOF

aws ecs register-task-definition --cli-input-json file://task-def.json --region $REGION

# Start or update service
SERVICE_EXISTS=$(aws ecs describe-services --cluster workflow-cluster --services workflow-backend-service --query 'services[0].status' --output text --region $REGION 2>/dev/null || echo "NOT_FOUND")
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[0:2].SubnetId' --output text --region $REGION | tr '\t' ',')

if [ "$SERVICE_EXISTS" = "NOT_FOUND" ]; then
    aws ecs create-service --cluster workflow-cluster --service-name workflow-backend-service --task-definition workflow-backend --desired-count 1 --launch-type FARGATE --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_IDS],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" --region $REGION
else
    aws ecs update-service --cluster workflow-cluster --service workflow-backend-service --desired-count 1 --force-new-deployment --region $REGION
fi

# Wait for backend
echo "Waiting for backend to start..."
for i in {1..20}; do
    COUNT=$(aws ecs describe-services --cluster workflow-cluster --services workflow-backend-service --query 'services[0].runningCount' --output text --region $REGION 2>/dev/null || echo "0")
    if [ "$COUNT" = "1" ]; then break; fi
    echo "Attempt $i/20..."
    sleep 15
done

# 9. Get backend IP and deploy frontend
echo "9. Deploying frontend..."
sleep 30  # Let backend stabilize

TASK_ARN=$(aws ecs list-tasks --cluster workflow-cluster --service-name workflow-backend-service --query 'taskArns[0]' --output text --region $REGION)
if [ "$TASK_ARN" != "None" ] && [ -n "$TASK_ARN" ]; then
    BACKEND_IP=$(aws ecs describe-tasks --cluster workflow-cluster --tasks $TASK_ARN --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text --region $REGION | xargs -I {} aws ec2 describe-network-interfaces --network-interface-ids {} --query 'NetworkInterfaces[0].Association.PublicIp' --output text --region $REGION)
    
    # Test backend
    for i in {1..10}; do
        if curl -f -s "http://$BACKEND_IP:3000/health" >/dev/null; then
            echo "Backend ready at $BACKEND_IP"
            break
        fi
        echo "Backend starting... ($i/10)"
        sleep 10
    done
    
    # Deploy frontend
    if [ -d "frontend" ]; then
        cd frontend
        cat > .env << EOF
REACT_APP_API_URL=http://$BACKEND_IP:3000
REACT_APP_AWS_REGION=$REGION
REACT_APP_COGNITO_USER_POOL_ID=$USER_POOL_ID
REACT_APP_COGNITO_CLIENT_ID=$USER_POOL_CLIENT_ID
GENERATE_SOURCEMAP=false
SKIP_PREFLIGHT_CHECK=true
EOF
        
        if [ -d "node_modules" ]; then
            npm run build
            if [ -d "build" ]; then
                aws s3 sync build/ s3://$FRONTEND_BUCKET --region $REGION --delete
                echo "Frontend deployed to $FRONTEND_URL"
            else
                FRONTEND_URL="N/A (build failed)"
            fi
        else
            FRONTEND_URL="N/A (no node_modules)"
        fi
        cd ..
    else
        FRONTEND_URL="N/A (no frontend dir)"
    fi
else
    BACKEND_IP="N/A"
    FRONTEND_URL="N/A"
fi

# Cleanup
rm -f task-def.json

# Save config
cat > deploy-config.txt << EOF
# Workflow Deploy Configuration
Frontend: $FRONTEND_URL
Backend: http://$BACKEND_IP:3000
Health: http://$BACKEND_IP:3000/health
Cognito User Pool: $USER_POOL_ID
Cognito Client: $USER_POOL_CLIENT_ID  
SNS Topic: $SNS_TOPIC_ARN
SQS Queue: $SQS_QUEUE_URL
Database: $DB_ENDPOINT
S3 Frontend Bucket: $FRONTEND_BUCKET
EOF

echo ""
echo "Deployment complete!"
echo "Frontend: $FRONTEND_URL"
echo "Backend: http://$BACKEND_IP:3000"
echo ""
echo "Test commands:"
echo "curl http://$BACKEND_IP:3000/health"
echo "curl $FRONTEND_URL"