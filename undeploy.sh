#!/bin/bash
# undeploy.sh - Undeployment parziale Workflow con servizi aggiuntivi
# Ferma i servizi costosi mantenendo S3, ECR e configurazioni

echo "🗑️ Avviando undeployment parziale..."
echo "⚠️  Questo fermerà ECS, eliminerà RDS, Cognito, SNS e SQS"
echo "💰 Costi ridotti da ~$10/mese a ~$0.50/mese"
echo ""

# Conferma utente
read -p "Vuoi continuare? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Operazione annullata"
    exit 1
fi

echo "🚀 Iniziando undeployment..."

# 1. Ferma ECS Service (costo principale)
echo ""
echo "⏹️  Step 1/6: Fermando ECS Service..."
aws ecs update-service \
    --cluster workflow-cluster \
    --service workflow-backend-service \
    --desired-count 0

# Verifica che sia fermo
echo "⏳ Attendendo che ECS si fermi..."
while true; do
    COUNT=$(aws ecs describe-services \
        --cluster workflow-cluster \
        --services workflow-backend-service \
        --query 'services[0].runningCount' \
        --output text 2>/dev/null || echo "0")
    
    echo "   Running tasks: $COUNT"
    if [ "$COUNT" = "0" ]; then
        echo "✅ ECS Service fermato!"
        break
    fi
    sleep 10
done

# 2. Elimina Database RDS con snapshot di backup
echo ""
echo "🗄️  Step 2/6: Eliminando Database RDS..."
SNAPSHOT_ID="workflow-db-snapshot-$(date +%Y%m%d-%H%M)"
echo "📸 Creando snapshot di backup: $SNAPSHOT_ID"

aws rds delete-db-instance \
    --db-instance-identifier workflow-db \
    --final-db-snapshot-identifier "$SNAPSHOT_ID" \
    --no-skip-final-snapshot

echo "⏳ Attendendo eliminazione database..."
while true; do
    STATUS=$(aws rds describe-db-instances \
        --db-instance-identifier workflow-db \
        --query 'DBInstances[0].DBInstanceStatus' \
        --output text 2>/dev/null || echo "deleted")
    
    echo "   Database status: $STATUS"
    if [ "$STATUS" = "deleted" ] || [ "$STATUS" = "deleting" ]; then
        if [ "$STATUS" = "deleted" ]; then
            echo "✅ Database eliminato!"
        else
            echo "🔄 Database in eliminazione..."
        fi
        break
    fi
    sleep 30
done

# 3. Elimina Cognito User Pool
echo ""
echo "🔐 Step 3/6: Eliminando Cognito User Pool..."

USER_POOLS=$(aws cognito-idp list-user-pools \
    --max-results 60 \
    --query "UserPools[?contains(Name, 'workflow')].Id" \
    --output text 2>/dev/null || echo "")

if [ -n "$USER_POOLS" ]; then
    for pool_id in $USER_POOLS; do
        echo "   Eliminando User Pool: $pool_id"
        
        # Elimina domini se presenti
        DOMAINS=$(aws cognito-idp describe-user-pool \
            --user-pool-id $pool_id \
            --query 'UserPool.Domain' \
            --output text 2>/dev/null || echo "")
        
        if [ "$DOMAINS" != "None" ] && [ -n "$DOMAINS" ]; then
            aws cognito-idp delete-user-pool-domain \
                --domain $DOMAINS 2>/dev/null || echo "   Dominio non trovato"
        fi
        
        aws cognito-idp delete-user-pool \
            --user-pool-id $pool_id 2>/dev/null || echo "   User Pool non trovato"
    done
    echo "✅ Cognito User Pool eliminato!"
else
    echo "✅ Nessun Cognito User Pool trovato"
fi

# 4. Elimina SNS Topic
echo ""
echo "📧 Step 4/6: Eliminando SNS Topic..."

SNS_TOPICS=$(aws sns list-topics \
    --query "Topics[?contains(TopicArn, 'workflow')].TopicArn" \
    --output text 2>/dev/null || echo "")

if [ -n "$SNS_TOPICS" ]; then
    for topic_arn in $SNS_TOPICS; do
        echo "   Eliminando topic: $topic_arn"
        aws sns delete-topic --topic-arn "$topic_arn" 2>/dev/null || echo "   Topic non trovato"
    done
    echo "✅ SNS Topic eliminato!"
else
    echo "✅ Nessun SNS Topic trovato"
fi

# 5. Elimina SQS Queue
echo ""
echo "📤 Step 5/6: Eliminando SQS Queue..."

SQS_QUEUES=$(aws sqs list-queues \
    --queue-name-prefix workflow \
    --query 'QueueUrls[]' \
    --output text 2>/dev/null || echo "")

if [ -n "$SQS_QUEUES" ]; then
    for queue_url in $SQS_QUEUES; do
        echo "   Eliminando coda: $queue_url"
        aws sqs delete-queue --queue-url "$queue_url" 2>/dev/null || echo "   Coda non trovata"
    done
    echo "✅ SQS Queue eliminato!"
else
    echo "✅ Nessuna SQS Queue trovata"
fi

# 6. Verifica stato finale
echo ""
echo "🔍 Step 6/6: Verifica stato finale..."

# Controlla ECS
ECS_COUNT=$(aws ecs describe-services \
    --cluster workflow-cluster \
    --services workflow-backend-service \
    --query 'services[0].runningCount' \
    --output text 2>/dev/null || echo "0")

# Controlla RDS
RDS_STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier workflow-db \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text 2>/dev/null || echo "NOT_FOUND")

# Controlla S3 (dovrebbe rimanere)
BUCKET_NAME=$(aws s3api list-buckets \
    --query 'Buckets[?contains(Name, `workflow-frontend`)].Name' \
    --output text | head -1)

# Controlla ECR (dovrebbe rimanere)
ECR_REPO=$(aws ecr describe-repositories \
    --repository-names workflow-backend \
    --query 'repositories[0].repositoryName' \
    --output text 2>/dev/null || echo "NOT_FOUND")

# Controlla Cognito
COGNITO_POOLS=$(aws cognito-idp list-user-pools \
    --max-results 10 \
    --query "UserPools[?contains(Name, 'workflow')].Id" \
    --output text 2>/dev/null || echo "")

# Controlla SNS
SNS_COUNT=$(aws sns list-topics \
    --query "length(Topics[?contains(TopicArn, 'workflow')])" \
    --output text 2>/dev/null || echo "0")

# Controlla SQS
SQS_COUNT=$(aws sqs list-queues \
    --queue-name-prefix workflow \
    --query 'length(QueueUrls)' \
    --output text 2>/dev/null || echo "0")

echo ""
echo "📊 STATO FINALE:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ECS Tasks Running:    $ECS_COUNT (dovrebbe essere 0)"
echo "RDS Status:           $RDS_STATUS (dovrebbe essere NOT_FOUND)"
echo "S3 Bucket:            ${BUCKET_NAME:-NOT_FOUND} (mantenuto)"
echo "ECR Repository:       ${ECR_REPO:-NOT_FOUND} (mantenuto)"
echo "Cognito User Pools:   ${COGNITO_POOLS:-0} (dovrebbe essere vuoto)"
echo "SNS Topics:           $SNS_COUNT (dovrebbe essere 0)"
echo "SQS Queues:           $SQS_COUNT (dovrebbe essere 0)"
echo ""

# Stima costi
if [ "$ECS_COUNT" = "0" ] && [ "$RDS_STATUS" != "available" ] && [ "$SNS_COUNT" = "0" ] && [ "$SQS_COUNT" = "0" ]; then
    echo "✅ UNDEPLOYMENT COMPLETATO CON SUCCESSO!"
    echo ""
    echo "💰 IMPATTO COSTI:"
    echo "   Prima:  ~$7-11/mese (ECS + RDS + S3 + ECR + Cognito + SNS + SQS)"
    echo "   Ora:    ~$0.20-0.60/mese (solo S3 + ECR)"
    echo "   Risparmio: ~$6-10/mese"
    echo ""
    echo "📦 COSA È STATO MANTENUTO:"
    echo "   ✅ S3 Bucket con frontend"
    echo "   ✅ ECR Repository con immagine Docker"
    echo "   ✅ ECS Cluster, Service e Task Definition"
    echo "   ✅ CloudWatch Log Groups"
    echo "   ✅ Security Groups"
    echo "   ✅ Snapshot database per backup"
    echo ""
    echo "🗑️ COSA È STATO ELIMINATO:"
    echo "   ❌ ECS Tasks (fermati, non eliminati)"
    echo "   ❌ RDS Database (con backup snapshot)"
    echo "   ❌ Cognito User Pool"
    echo "   ❌ SNS Topic"
    echo "   ❌ SQS Queue"
    echo ""
    echo "🚀 PER RIAVVIARE:"
    echo "   Usa lo script deploy.sh"
    echo "   Tempo stimato: 15-20 minuti"
    echo ""
else
    echo "⚠️  ATTENZIONE: Qualcosa potrebbe non essere andato come previsto"
    echo "   ECS Count: $ECS_COUNT (dovrebbe essere 0)"
    echo "   RDS Status: $RDS_STATUS (dovrebbe essere NOT_FOUND)"
    echo "   SNS Topics: $SNS_COUNT (dovrebbe essere 0)"
    echo "   SQS Queues: $SQS_COUNT (dovrebbe essere 0)"
fi

echo "📋 SNAPSHOT CREATO: $SNAPSHOT_ID"
echo "   (utilizzabile per ripristino dati se necessario)"

