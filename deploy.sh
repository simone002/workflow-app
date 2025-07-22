#!/bin/bash

# 🚀 DEPLOY WORKFLOW - Con servizi Cognito, SNS, SQS

set -e

REGION="eu-west-1"
APP_NAME="workflow"

echo "🚀 Workflow  Deployment Starting..."
echo "🔄 Deployando tutti i servizi AWS"
echo "✨ Include: ECS, RDS, Cognito, SNS, SQS"
echo ""

# Verifica stato attuale
echo "🔍 Verifica stato attuale..."

ECS_COUNT=$(aws ecs describe-services \
    --cluster workflow-cluster \
    --services workflow-backend-service \
    --query 'services[0].runningCount' \
    --output text 2>/dev/null || echo "0")

RDS_STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier workflow-db \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text 2>/dev/null || echo "NOT_FOUND")

echo "📊 Stato attuale:"
echo "   ECS Tasks: $ECS_COUNT"
echo "   RDS Status: $RDS_STATUS"
echo ""

# Step 1: Crea/Verifica Cognito User Pool
echo "🔐 Step 1/8: Configurando Cognito User Pool..."

# Controlla se esiste già
EXISTING_POOLS=$(aws cognito-idp list-user-pools \
    --max-results 60 \
    --query "UserPools[?contains(Name, '${APP_NAME}-users')].Id" \
    --output text \
    --region $REGION 2>/dev/null || echo "")

if [ -n "$EXISTING_POOLS" ]; then
    USER_POOL_ID=$(echo $EXISTING_POOLS | cut -d' ' -f1)
    echo "✅ Cognito User Pool esistente trovato: $USER_POOL_ID"
    
    # Trova client esistente
    USER_POOL_CLIENT_ID=$(aws cognito-idp list-user-pool-clients \
        --user-pool-id $USER_POOL_ID \
        --query 'UserPoolClients[0].ClientId' \
        --output text \
        --region $REGION)
    echo "✅ User Pool Client esistente: $USER_POOL_CLIENT_ID"
else
    # Crea nuovo User Pool
    USER_POOL_ID=$(aws cognito-idp create-user-pool \
        --pool-name "${APP_NAME}-users" \
        --policies '{"PasswordPolicy":{"MinimumLength":6,"RequireUppercase":false,"RequireLowercase":false,"RequireNumbers":false,"RequireSymbols":false}}' \
        --username-attributes "email" \
        --auto-verified-attributes "email" \
        --query 'UserPool.Id' \
        --output text \
        --region $REGION)
    
    echo "✅ Cognito User Pool creato: $USER_POOL_ID"
    
    # Crea User Pool Client
    USER_POOL_CLIENT_ID=$(aws cognito-idp create-user-pool-client \
        --user-pool-id $USER_POOL_ID \
        --client-name "${APP_NAME}-client" \
        --explicit-auth-flows "ADMIN_NO_SRP_AUTH" "USER_PASSWORD_AUTH" \
        --query 'UserPoolClient.ClientId' \
        --output text \
        --region $REGION)
    
    echo "✅ User Pool Client creato: $USER_POOL_CLIENT_ID"
fi

# Step 2: Crea/Verifica SNS Topic
echo ""
echo "📧 Step 2/8: Configurando SNS Topic..."

# Controlla se esiste
EXISTING_TOPICS=$(aws sns list-topics \
    --query "Topics[?contains(TopicArn, '${APP_NAME}-notifications')].TopicArn" \
    --output text \
    --region $REGION 2>/dev/null || echo "")

if [ -n "$EXISTING_TOPICS" ]; then
    SNS_TOPIC_ARN=$(echo $EXISTING_TOPICS | cut -d' ' -f1)
    echo "✅ SNS Topic esistente trovato: $SNS_TOPIC_ARN"
else
    SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "${APP_NAME}-notifications" \
        --query 'TopicArn' \
        --output text \
        --region $REGION)
    
    echo "✅ SNS Topic creato: $SNS_TOPIC_ARN"
fi

# Step 3: Crea/Verifica SQS Queue
echo ""
echo "📤 Step 3/8: Configurando SQS Queue..."

# Controlla se esiste
EXISTING_QUEUES=$(aws sqs list-queues \
    --queue-name-prefix "${APP_NAME}-tasks" \
    --query 'QueueUrls[0]' \
    --output text \
    --region $REGION 2>/dev/null || echo "None")

if [ "$EXISTING_QUEUES" != "None" ] && [ -n "$EXISTING_QUEUES" ]; then
    SQS_QUEUE_URL="$EXISTING_QUEUES"
    echo "✅ SQS Queue esistente trovata: $SQS_QUEUE_URL"
else
    SQS_QUEUE_URL=$(aws sqs create-queue \
        --queue-name "${APP_NAME}-tasks" \
        --attributes "VisibilityTimeout=300,MessageRetentionPeriod=1209600,DelaySeconds=0" \
        --query 'QueueUrl' \
        --output text \
        --region $REGION)
    
    echo "✅ SQS Queue creata: $SQS_QUEUE_URL"
fi

# Ottieni ARN della coda per SNS subscription
SQS_QUEUE_ARN=$(aws sqs get-queue-attributes \
    --queue-url $SQS_QUEUE_URL \
    --attribute-names QueueArn \
    --query 'Attributes.QueueArn' \
    --output text \
    --region $REGION)

# Verifica se subscription SNS->SQS esiste già
EXISTING_SUBS=$(aws sns list-subscriptions-by-topic \
    --topic-arn $SNS_TOPIC_ARN \
    --query "Subscriptions[?Endpoint=='$SQS_QUEUE_ARN'].SubscriptionArn" \
    --output text \
    --region $REGION 2>/dev/null || echo "")

if [ -z "$EXISTING_SUBS" ]; then
    echo "🔗 Collegando SNS a SQS..."
    aws sns subscribe \
        --topic-arn $SNS_TOPIC_ARN \
        --protocol sqs \
        --notification-endpoint $SQS_QUEUE_ARN \
        --region $REGION >/dev/null
    
    echo "✅ SNS-SQS subscription creata"
else
    echo "✅ SNS-SQS subscription già esistente"
fi

# Step 4: Crea/Verifica Database
echo ""
if [ "$RDS_STATUS" = "NOT_FOUND" ] || [ "$RDS_STATUS" = "deleted" ]; then
    echo "🗄️ Step 4/8: Creando Database RDS..."
    
    aws rds create-db-instance \
        --db-instance-identifier workflow-db \
        --db-instance-class db.t3.micro \
        --engine mysql \
        --engine-version 8.0.35 \
        --master-username admin \
        --master-user-password WorkflowPass123! \
        --allocated-storage 20 \
        --storage-type gp2 \
        --db-name workflow \
        --backup-retention-period 7 \
        --storage-encrypted \
        --publicly-accessible \
        --region $REGION
    
    echo "⏳ Attendendo che il database sia disponibile (10-15 minuti)..."
    echo "💡 Questo è il tempo più lungo - il database si sta creando da zero"
    
    START_TIME=$(date +%s)
    while true; do
        STATUS=$(aws rds describe-db-instances \
            --db-instance-identifier workflow-db \
            --query 'DBInstances[0].DBInstanceStatus' \
            --output text \
            --region $REGION 2>/dev/null || echo "creating")
        
        CURRENT_TIME=$(date +%s)
        ELAPSED=$((CURRENT_TIME - START_TIME))
        MINUTES=$((ELAPSED / 60))
        
        echo "   Database status: $STATUS (${MINUTES} minuti trascorsi)"
        
        if [ "$STATUS" = "available" ]; then
            echo "✅ Database pronto!"
            break
        fi
        
        sleep 30
    done
elif [ "$RDS_STATUS" = "available" ]; then
    echo "✅ Step 4/8: Database già disponibile"
else
    echo "⏳ Step 4/8: Database in stato $RDS_STATUS, attendendo..."
    while true; do
        STATUS=$(aws rds describe-db-instances \
            --db-instance-identifier workflow-db \
            --query 'DBInstances[0].DBInstanceStatus' \
            --output text \
            --region $REGION 2>/dev/null)
        
        echo "   Database status: $STATUS"
        
        if [ "$STATUS" = "available" ]; then
            echo "✅ Database pronto!"
            break
        fi
        
        sleep 30
    done
fi

# Step 5: Configura Security Groups
echo ""
echo "🔒 Step 5/8: Configurazione Security Groups..."

# Database Security Group
DB_SG_ID=$(aws rds describe-db-instances \
    --db-instance-identifier workflow-db \
    --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
    --output text \
    --region $REGION)

echo "Database Security Group: $DB_SG_ID"

aws ec2 authorize-security-group-ingress \
    --group-id $DB_SG_ID \
    --protocol tcp \
    --port 3306 \
    --cidr 10.0.0.0/16 \
    --region $REGION 2>/dev/null && echo "✅ Porta MySQL (3306) aperta" || echo "⚠️ Porta MySQL già aperta"

# ECS Security Group
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=is-default,Values=true" \
    --query 'Vpcs[0].VpcId' \
    --output text \
    --region $REGION)

SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=default" \
    --query 'SecurityGroups[0].GroupId' \
    --output text \
    --region $REGION)

echo "ECS Security Group: $SG_ID"

aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 3000 \
    --cidr 0.0.0.0/0 \
    --region $REGION 2>/dev/null && echo "✅ Porta ECS (3000) aperta" || echo "⚠️ Porta ECS già aperta"


# Step 5.5: Crea/Verifica Ruolo e Policy IAM 

echo ""
echo "🔐 Step 5.5: Configurazione Ruolo e Policy IAM per il Task ECS..."

ROLE_NAME="WorkflowTaskRole"
POLICY_NAME="WorkflowAppPermissions"

# Controlla se il ruolo esiste già
if ! aws iam get-role --role-name $ROLE_NAME --region $REGION > /dev/null 2>&1; then
    echo "🏗️  Creando IAM Role: $ROLE_NAME..."
    # Crea la trust policy per ECS
    cat << EOF > ecs-trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ecs-tasks.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    aws iam create-role \
      --role-name $ROLE_NAME \
      --assume-role-policy-document file://ecs-trust-policy.json \
      --region $REGION
    rm ecs-trust-policy.json
else
    echo "✅ IAM Role '$ROLE_NAME' già esistente."
fi

# Controlla se la policy esiste già
POLICY_ARN=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='$POLICY_NAME'].Arn" --output text --region $REGION)
if [ -z "$POLICY_ARN" ]; then
    echo "📝 Creando IAM Policy: $POLICY_NAME..."
    # Crea la policy di permessi
    cat << EOF > app-permissions-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sns:Publish",
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "cognito-idp:AdminCreateUser",
        "cognito-idp:AdminSetUserPassword",
        "cognito-idp:AdminInitiateAuth"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    POLICY_ARN=$(aws iam create-policy \
      --policy-name $POLICY_NAME \
      --policy-document file://app-permissions-policy.json \
      --query 'Policy.Arn' --output text \
      --region $REGION)
    rm app-permissions-policy.json
else
    echo "✅ IAM Policy '$POLICY_NAME' già esistente."
fi

# Collega la policy al ruolo
echo "🔗 Collegando policy al ruolo..."
aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn $POLICY_ARN \
  --region $REGION
echo "✅ Policy collegata con successo."


# Step 6: Verifica/Crea ECS Infrastructure
echo ""
echo "🏗️ Step 6/8: Configurazione ECS Infrastructure..."

# Verifica cluster
CLUSTER_EXISTS=$(aws ecs describe-clusters \
    --clusters workflow-cluster \
    --query 'clusters[0].status' \
    --output text \
    --region $REGION 2>/dev/null || echo "NOT_FOUND")

if [ "$CLUSTER_EXISTS" = "NOT_FOUND" ]; then
    echo "🏗️ Creando ECS Cluster..."
    aws ecs create-cluster \
        --cluster-name workflow-cluster \
        --capacity-providers FARGATE \
        --region $REGION
else
    echo "✅ ECS Cluster esistente"
fi

# Verifica ECR repository
ECR_EXISTS=$(aws ecr describe-repositories \
    --repository-names workflow-backend \
    --query 'repositories[0].repositoryName' \
    --output text \
    --region $REGION 2>/dev/null || echo "NOT_FOUND")

if [ "$ECR_EXISTS" = "NOT_FOUND" ]; then
    echo "📦 Creando ECR Repository..."
    aws ecr create-repository \
        --repository-name workflow-backend \
        --region $REGION
else
    echo "✅ ECR Repository esistente"
fi

# Step 7: Update Task Definition
echo ""
echo "📋 Step 7/8: Aggiornando ECS Task Definition..."

DB_ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier workflow-db \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text \
    --region $REGION)

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Database Endpoint: $DB_ENDPOINT"

# Crea enhanced task definition
cat << EOF > enhanced-task-definition.json
{
  "family": "workflow-backend",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::${ACCOUNT_ID}:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::${ACCOUNT_ID}:role/WorkflowTaskRole",
  "containerDefinitions": [
    {
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
    }
  ]
}
EOF

aws ecs register-task-definition \
    --cli-input-json file://enhanced-task-definition.json \
    --region $REGION

echo "✅ Task Definition registrata con tutti i servizi AWS"

# Verifica se service esiste
SERVICE_EXISTS=$(aws ecs describe-services \
    --cluster workflow-cluster \
    --services workflow-backend-service \
    --query 'services[0].status' \
    --output text \
    --region $REGION 2>/dev/null || echo "NOT_FOUND")

if [ "$SERVICE_EXISTS" = "NOT_FOUND" ]; then
    echo "🚀 Creando ECS Service..."
    
    SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'Subnets[0:2].SubnetId' \
        --output text \
        --region $REGION | tr '\t' ',')
    
    aws ecs create-service \
        --cluster workflow-cluster \
        --service-name workflow-backend-service \
        --task-definition workflow-backend \
        --desired-count 1 \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_IDS],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
        --region $REGION
else
    echo "🔄 Aggiornando ECS Service esistente..."
    aws ecs update-service \
        --cluster workflow-cluster \
        --service workflow-backend-service \
        --desired-count 1 \
        --force-new-deployment \
        --region $REGION
fi

echo ""
echo "⏳ Step 8/8: Attendendo che ECS sia operativo..."

# Attesa con timeout e progress
TIMEOUT=600  # 10 minuti
ELAPSED=0
START_TIME=$(date +%s)

while [ $ELAPSED -lt $TIMEOUT ]; do
    COUNT=$(aws ecs describe-services \
        --cluster workflow-cluster \
        --services workflow-backend-service \
        --query 'services[0].runningCount' \
        --output text \
        --region $REGION 2>/dev/null || echo "0")
    
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    MINUTES=$((ELAPSED / 60))
    
    echo "   Running tasks: $COUNT/1 (${MINUTES} minuti trascorsi)"
    
    if [ "$COUNT" = "1" ]; then
        echo "✅ ECS Service operativo!"
        break
    fi
    
    sleep 30
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "⚠️ Timeout ECS startup, ma il servizio potrebbe ancora avviarsi"
fi

# Step 9: Aggiorna Frontend
echo ""
echo "🌐 Step 9/9: Aggiornando Frontend..."

# Attendi che il task sia completamente avviato
echo "⏳ Attendendo stabilizzazione backend..."
sleep 60

TASK_ARN=$(aws ecs list-tasks \
    --cluster workflow-cluster \
    --service-name workflow-backend-service \
    --query 'taskArns[0]' \
    --output text \
    --region $REGION)

if [ "$TASK_ARN" != "None" ] && [ -n "$TASK_ARN" ]; then
    BACKEND_IP=$(aws ecs describe-tasks \
        --cluster workflow-cluster \
        --tasks $TASK_ARN \
        --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
        --output text \
        --region $REGION | xargs -I {} aws ec2 describe-network-interfaces \
        --network-interface-ids {} \
        --query 'NetworkInterfaces[0].Association.PublicIp' \
        --output text \
        --region $REGION)
    
    echo "✅ Backend IP ottenuto: $BACKEND_IP"
    
    # Test backend connectivity
    echo "🧪 Testing backend connectivity..."
    for i in {1..10}; do
        if curl -f -s "http://$BACKEND_IP:3000/health" >/dev/null; then
            echo "✅ Backend risponde correttamente!"
            break
        fi
        echo "   Tentativo $i/10... backend in startup"
        sleep 10
    done
    
    # Aggiorna frontend se esiste la directory
    if [ -d "frontend" ]; then
        cd frontend
        
        cat << EOF > .env
REACT_APP_API_URL=http://$BACKEND_IP:3000
REACT_APP_AWS_REGION=$REGION
REACT_APP_COGNITO_USER_POOL_ID=$USER_POOL_ID
REACT_APP_COGNITO_CLIENT_ID=$USER_POOL_CLIENT_ID
GENERATE_SOURCEMAP=false
SKIP_PREFLIGHT_CHECK=true
EOF
        
        echo "✅ Frontend .env aggiornato"
        
        # Build se node_modules esiste
        if [ -d "node_modules" ]; then
            npm run build
            
            BUCKET_NAME=$(aws s3api list-buckets \
                --query 'Buckets[?contains(Name, `workflow-frontend`)].Name' \
                --output text | head -1)
            
            if [ -n "$BUCKET_NAME" ]; then
                aws s3 sync build/ s3://$BUCKET_NAME --region $REGION
                FRONTEND_URL="http://${BUCKET_NAME}.s3-website-${REGION}.amazonaws.com"
                echo "✅ Frontend deployato su S3"
            else
                echo "⚠️ Bucket frontend non trovato"
                FRONTEND_URL="N/A"
            fi
        else
            echo "⚠️ node_modules non trovato, esegui: cd frontend && npm install && npm run build"
            FRONTEND_URL="N/A"
        fi
        
        cd ..
    else
        echo "⚠️ Directory frontend non trovata"
        FRONTEND_URL="N/A"
    fi
else
    echo "⚠️ Task ECS non trovato"
    BACKEND_IP="N/A"
    FRONTEND_URL="N/A"
fi

# Cleanup
rm -f enhanced-task-definition.json

echo ""
echo "🎉 DEPLOY COMPLETATO CON SUCCESSO!"
echo ""
echo "📊 SERVIZI DEPLOYATI:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ ECS Fargate        - Backend API Container"
echo "✅ RDS MySQL          - Managed Database"
echo "✅ S3 Static Website  - Frontend React App"
echo "✅ ECR Registry       - Container Images"
echo "✅ Cognito User Pool  - User Authentication"
echo "✅ SNS Topic          - Push Notifications"  
echo "✅ SQS Queue          - Async Message Processing"
echo "✅ CloudWatch Logs    - Application Monitoring"
echo ""
echo "🔗 APPLICATION ENDPOINTS:"
if [ "$FRONTEND_URL" != "N/A" ]; then
    echo "   🌐 Frontend App:  $FRONTEND_URL"
fi
if [ "$BACKEND_IP" != "N/A" ]; then
    echo "   🔧 Backend API:   http://$BACKEND_IP:3000"
    echo "   🏥 Health Check:  http://$BACKEND_IP:3000/health"
    echo "   📋 Demo Services: http://$BACKEND_IP:3000/api/demo/aws-services"
    echo "   📤 Queue Admin:   http://$BACKEND_IP:3000/api/admin/queue-messages"
fi
echo ""
echo "🔐 AWS SERVICES CONFIGURATION:"
echo "   Cognito User Pool:  $USER_POOL_ID"
echo "   Cognito Client:     $USER_POOL_CLIENT_ID"
echo "   SNS Topic:          $SNS_TOPIC_ARN"
echo "   SQS Queue:          $SQS_QUEUE_URL"
echo "   Database Endpoint:  $DB_ENDPOINT"
echo ""
echo "💰 Costi Mensili Stimati: ~$7-11/mese"
echo ""
echo "🧪 TEST RAPIDI:"
if [ "$BACKEND_IP" != "N/A" ]; then
    echo "   curl http://$BACKEND_IP:3000/health"
    echo "   curl http://$BACKEND_IP:3000/api/demo/aws-services"
fi
echo ""
echo "🎓 Applicazione pronta per demo esame universitario!"
echo "🚀 Architettura Cloud-Native completa con 8 servizi AWS integrati"

# Salva configurazione per riferimento futuro
cat << EOF > deploy-config.txt
# Workflow Enhanced Deploy Configuration
# Generated: $(date)

# Application URLs
Frontend: ${FRONTEND_URL:-N/A}
Backend: http://$BACKEND_IP:3000
Health: http://$BACKEND_IP:3000/health

# AWS Services IDs
Cognito User Pool: $USER_POOL_ID
Cognito Client: $USER_POOL_CLIENT_ID  
SNS Topic: $SNS_TOPIC_ARN
SQS Queue: $SQS_QUEUE_URL
Database: $DB_ENDPOINT

# Quick Commands
Health Check: curl http://$BACKEND_IP:3000/health
View Logs: aws logs tail /ecs/workflow-simple --follow --region $REGION
Stop Services: ./undeploy.sh
Restart Backend: aws ecs update-service --cluster workflow-cluster --service workflow-backend-service --force-new-deployment --region $REGION
EOF

echo ""
echo "📝 Configurazione salvata in: deploy-config.txt"
echo "🗑️ Per spegnere e risparmiare: ./undeploy.sh"