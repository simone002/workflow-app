#!/bin/bash
# undeploy-total.sh - Undeployment COMPLETO del progetto Workflow

set -e
REGION="eu-west-1"

echo "🗑️  ATTENZIONE: Avviando undeployment TOTALE e DISTRUTTIVO."
echo "🔥  Questo eliminerà TUTTE le risorse del progetto: ECS, RDS (senza backup), S3, ECR, Cognito, SNS, SQS, IAM Role/Policy."
echo ""

# Conferma utente esplicita
read -p "Scrivi 'DELETE' per confermare l'eliminazione completa: " CONFIRMATION
if [ "$CONFIRMATION" != "DELETE" ]; then
    echo "❌ Operazione annullata."
    exit 1
fi

echo "🚀 Iniziando undeployment totale..."

# 1. Ferma e cancella il servizio ECS
echo ""
echo "🔥 Step 1/8: Eliminando Servizio e Cluster ECS..."
aws ecs update-service \
    --cluster workflow-cluster \
    --service workflow-backend-service \
    --desired-count 0 \
    --region $REGION > /dev/null
echo "  - Servizio scalato a 0 task."

aws ecs delete-service \
    --cluster workflow-cluster \
    --service workflow-backend-service \
    --force \
    --region $REGION > /dev/null
echo "  - Servizio ECS eliminato."

aws ecs delete-cluster \
    --cluster workflow-cluster \
    --region $REGION > /dev/null
echo "✅ Cluster ECS eliminato."


# 2. Elimina il Database RDS (SENZA snapshot finale)
echo ""
echo "🔥 Step 2/8: Eliminando Database RDS (SENZA BACKUP)..."
aws rds delete-db-instance \
    --db-instance-identifier workflow-db \
    --skip-final-snapshot \
    --region $REGION > /dev/null
echo "✅ Comando di eliminazione RDS inviato."


# 3. Svuota ed elimina il bucket S3
echo ""
echo "🔥 Step 3/8: Eliminando Bucket S3..."
BUCKET_NAME=$(aws s3api list-buckets --query 'Buckets[?contains(Name, `workflow-frontend`)].Name' --output text | head -1)
if [ -n "$BUCKET_NAME" ]; then
    aws s3 rb "s3://$BUCKET_NAME" --force --region $REGION
    echo "✅ Bucket S3 '$BUCKET_NAME' eliminato."
else
    echo "  - Nessun bucket S3 trovato."
fi


# 4. Elimina il repository ECR
echo ""
echo "🔥 Step 4/8: Eliminando Repository ECR..."
if aws ecr describe-repositories --repository-names workflow-backend --region $REGION > /dev/null 2>&1; then
    aws ecr delete-repository --repository-name workflow-backend --force --region $REGION
    echo "✅ Repository ECR 'workflow-backend' eliminato."
else
    echo "  - Nessun repository ECR trovato."
fi


# 5. Elimina Cognito, SNS, SQS (con ricerche specifiche)
echo ""
echo "🔥 Step 5/8: Eliminando Cognito, SNS, SQS..."
USER_POOL_ID=$(aws cognito-idp list-user-pools --max-results 1 --query "UserPools[?Name=='workflow-users'].Id" --output text --region $REGION)
if [ -n "$USER_POOL_ID" ]; then
    aws cognito-idp delete-user-pool --user-pool-id $USER_POOL_ID --region $REGION
    echo "  - Cognito User Pool eliminato."
fi

SNS_TOPIC_ARN=$(aws sns list-topics --query "Topics[?contains(TopicArn, 'workflow-notifications')].TopicArn" --output text --region $REGION)
if [ -n "$SNS_TOPIC_ARN" ]; then
    aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN" --region $REGION
    echo "  - SNS Topic eliminato."
fi

SQS_QUEUE_URL=$(aws sqs get-queue-url --queue-name workflow-tasks --query QueueUrl --output text --region $REGION 2>/dev/null || echo "")
if [ -n "$SQS_QUEUE_URL" ]; then
    aws sqs delete-queue --queue-url "$SQS_QUEUE_URL" --region $REGION
    echo "  - SQS Queue eliminata."
fi
echo "✅ Servizi di messaggistica eliminati."


# 6. Elimina Ruolo e Policy IAM
echo ""
echo "🔥 Step 6/8: Eliminando Ruolo e Policy IAM..."
ROLE_NAME="WorkflowTaskRole"
POLICY_NAME="WorkflowAppPermissions"
POLICY_ARN=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='$POLICY_NAME'].Arn" --output text --region $REGION)

if [ -n "$POLICY_ARN" ]; then
    aws iam detach-role-policy --role-name $ROLE_NAME --policy-arn $POLICY_ARN --region $REGION
    echo "  - Policy scollegata dal ruolo."
    aws iam delete-policy --policy-arn $POLICY_ARN --region $REGION
    echo "  - Policy IAM eliminata."
fi

if aws iam get-role --role-name $ROLE_NAME --region $REGION > /dev/null 2>&1; then
    aws iam delete-role --role-name $ROLE_NAME --region $REGION
    echo "  - Ruolo IAM eliminato."
fi
echo "✅ Risorse IAM eliminate."


# 7. Elimina il Log Group di CloudWatch
echo ""
echo "🔥 Step 7/8: Eliminando Log Group di CloudWatch..."
LOG_GROUP_NAME="/ecs/workflow-simple"
if aws logs describe-log-groups --log-group-name-prefix $LOG_GROUP_NAME --region $REGION | grep $LOG_GROUP_NAME > /dev/null 2>&1; then
    aws logs delete-log-group --log-group-name $LOG_GROUP_NAME --region $REGION
    echo "✅ Log Group '$LOG_GROUP_NAME' eliminato."
else
    echo "  - Nessun Log Group trovato."
fi

# 8. Elimina snapshot RDS (opzionale, se vuoi una pulizia completa)
echo ""
echo "🔥 Step 8/8: Eliminando Snapshot del database..."
SNAPSHOT_ID=$(aws rds describe-db-snapshots --db-instance-identifier workflow-db --query "DBSnapshots[-1].DBSnapshotIdentifier" --output text --region $REGION 2>/dev/null || echo "")
if [ -n "$SNAPSHOT_ID" ]; then
    aws rds delete-db-snapshot --db-snapshot-identifier "$SNAPSHOT_ID" --region $REGION
    echo "✅ Snapshot '$SNAPSHOT_ID' eliminato."
else
    echo "  - Nessuno snapshot del DB trovato."
fi


echo ""
echo "✅ UNDEPLOYMENT TOTALE COMPLETATO."
echo "Tutte le risorse del progetto sono state eliminate."