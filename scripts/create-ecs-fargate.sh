#!/bin/bash

# Script para criar serviço ECS Fargate (alternativa ao App Runner)
# Execute com: bash scripts/create-ecs-fargate.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

AWS_REGION="us-east-1"
CLUSTER_NAME="usuarios-cluster"
SERVICE_NAME="usuarios-service"
TASK_FAMILY="usuarios-task"
ECR_REPO_NAME="usuarios-api"

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}  Criar ECS Fargate Service${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""

# Verificar se arquivo de recursos existe
if [ ! -f "aws-resources.txt" ]; then
    echo -e "${RED}❌ Arquivo aws-resources.txt não encontrado.${NC}"
    echo -e "${YELLOW}Execute primeiro: bash scripts/setup-aws.sh${NC}"
    exit 1
fi

# Ler informações do arquivo
DB_ENDPOINT=$(grep "Endpoint:" aws-resources.txt | cut -d: -f2- | xargs)
DB_NAME=$(grep "Database:" aws-resources.txt | cut -d: -f2 | xargs)
DB_USER=$(grep "Username:" aws-resources.txt | cut -d: -f2 | xargs)
DB_PASS=$(grep "Password:" aws-resources.txt | cut -d: -f2 | xargs)
SG_ID=$(grep "ID:" aws-resources.txt | grep "Security" -A1 | tail -1 | cut -d: -f2 | xargs)

# Obter Account ID e URI do ECR
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:latest"

echo -e "${GREEN}📋 Configurações:${NC}"
echo "   Cluster: ${CLUSTER_NAME}"
echo "   Service: ${SERVICE_NAME}"
echo "   Image: ${ECR_URI}"
echo ""

# 1. Criar ECS Cluster
echo -e "${YELLOW}1. Criando ECS Cluster...${NC}"
CLUSTER_EXISTS=$(aws ecs describe-clusters --clusters ${CLUSTER_NAME} --query "clusters[0].clusterName" --output text 2>/dev/null || echo "None")

if [ "$CLUSTER_EXISTS" == "None" ]; then
    aws ecs create-cluster --cluster-name ${CLUSTER_NAME} --region ${AWS_REGION} > /dev/null
    echo -e "${GREEN}✅ Cluster criado${NC}"
else
    echo -e "${YELLOW}⚠️  Cluster já existe${NC}"
fi
echo ""

# 2. Obter VPC padrão e subnets
echo -e "${YELLOW}2. Obtendo VPC e Subnets...${NC}"
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query "Subnets[*].SubnetId" --output text)
SUBNET_ARRAY=(${SUBNETS})

echo -e "${GREEN}✅ VPC: ${VPC_ID}${NC}"
echo -e "${GREEN}✅ Subnets encontradas: ${#SUBNET_ARRAY[@]}${NC}"
echo ""

# 3. Criar IAM Role para ECS Task Execution
echo -e "${YELLOW}3. Criando IAM Roles...${NC}"
EXECUTION_ROLE_NAME="ecsTaskExecutionRole-usuarios"
TASK_ROLE_NAME="ecsTaskRole-usuarios"

# Role para execução (pull de imagem ECR, logs)
EXECUTION_ROLE_ARN=$(aws iam get-role --role-name ${EXECUTION_ROLE_NAME} --query 'Role.Arn' --output text 2>/dev/null || echo "not-found")

if [ "$EXECUTION_ROLE_ARN" == "not-found" ]; then
    TRUST_POLICY='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    
    EXECUTION_ROLE_ARN=$(aws iam create-role \
        --role-name ${EXECUTION_ROLE_NAME} \
        --assume-role-policy-document "${TRUST_POLICY}" \
        --query 'Role.Arn' \
        --output text)
    
    aws iam attach-role-policy \
        --role-name ${EXECUTION_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
    
    # Adicionar política para criar log groups
    LOG_POLICY='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"],"Resource":"*"}]}'
    
    aws iam put-role-policy \
        --role-name ${EXECUTION_ROLE_NAME} \
        --policy-name CloudWatchLogsPolicy \
        --policy-document "${LOG_POLICY}"
    
    echo -e "${GREEN}✅ Execution Role criada com permissões de logs${NC}"
else
    echo -e "${YELLOW}⚠️  Execution Role já existe${NC}"
    
    # Garantir que a política de logs existe
    LOG_POLICY='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"],"Resource":"*"}]}'
    
    aws iam put-role-policy \
        --role-name ${EXECUTION_ROLE_NAME} \
        --policy-name CloudWatchLogsPolicy \
        --policy-document "${LOG_POLICY}" 2>/dev/null || true
    
    echo -e "${GREEN}✅ Permissões de logs atualizadas${NC}"
fi

# Role para a task (aplicação)
TASK_ROLE_ARN=$(aws iam get-role --role-name ${TASK_ROLE_NAME} --query 'Role.Arn' --output text 2>/dev/null || echo "not-found")

if [ "$TASK_ROLE_ARN" == "not-found" ]; then
    TRUST_POLICY='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    
    TASK_ROLE_ARN=$(aws iam create-role \
        --role-name ${TASK_ROLE_NAME} \
        --assume-role-policy-document "${TRUST_POLICY}" \
        --query 'Role.Arn' \
        --output text)
    
    echo -e "${GREEN}✅ Task Role criada${NC}"
else
    echo -e "${YELLOW}⚠️  Task Role já existe${NC}"
fi

# Aguardar roles serem propagadas
sleep 5
echo ""

# 4. Adicionar regra ao Security Group para porta 80
echo -e "${YELLOW}4. Configurando Security Group...${NC}"
aws ec2 authorize-security-group-ingress \
    --group-id ${SG_ID} \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 2>/dev/null && echo -e "${GREEN}✅ Porta 80 liberada${NC}" || echo -e "${YELLOW}⚠️  Regra já existe${NC}"
echo ""

# 5. Criar Task Definition
echo -e "${YELLOW}5. Criando Task Definition...${NC}"

TASK_DEF=$(cat <<EOF
{
  "family": "${TASK_FAMILY}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "${EXECUTION_ROLE_ARN}",
  "taskRoleArn": "${TASK_ROLE_ARN}",
  "containerDefinitions": [
    {
      "name": "usuarios-api",
      "image": "${ECR_URI}",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 80,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "ASPNETCORE_ENVIRONMENT",
          "value": "Production"
        },
        {
          "name": "DatabaseProvider",
          "value": "PostgreSql"
        },
        {
          "name": "ConnectionStrings__PostgreSql",
          "value": "Host=${DB_ENDPOINT};Port=5432;Database=${DB_NAME};Username=${DB_USER};Password=${DB_PASS};Ssl Mode=Require;"
        },
        {
          "name": "Jwt__Key",
          "value": "7G+H65bLToXxqzPvj7+q0oQUlxJp1WvdOU3nv3ArA1s="
        },
        {
          "name": "Jwt__ExpirationTimeHour",
          "value": "5"
        },
        {
          "name": "Jwt__IncreaseExpirationTimeMinutes",
          "value": "20"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/${TASK_FAMILY}",
          "awslogs-region": "${AWS_REGION}",
          "awslogs-stream-prefix": "ecs",
          "awslogs-create-group": "true"
        }
      }
    }
  ]
}
EOF
)

aws ecs register-task-definition --cli-input-json "${TASK_DEF}" > /dev/null
echo -e "${GREEN}✅ Task Definition registrada${NC}"
echo ""

# 6. Criar ou atualizar serviço ECS
echo -e "${YELLOW}6. Criando/Atualizando ECS Service...${NC}"

SERVICE_EXISTS=$(aws ecs describe-services \
    --cluster ${CLUSTER_NAME} \
    --services ${SERVICE_NAME} \
    --query "services[0].serviceName" \
    --output text 2>/dev/null || echo "None")

if [ "$SERVICE_EXISTS" == "None" ]; then
    aws ecs create-service \
        --cluster ${CLUSTER_NAME} \
        --service-name ${SERVICE_NAME} \
        --task-definition ${TASK_FAMILY} \
        --desired-count 1 \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_ARRAY[0]},${SUBNET_ARRAY[1]}],securityGroups=[${SG_ID}],assignPublicIp=ENABLED}" \
        --region ${AWS_REGION} > /dev/null
    
    echo -e "${GREEN}✅ Serviço criado${NC}"
else
    aws ecs update-service \
        --cluster ${CLUSTER_NAME} \
        --service ${SERVICE_NAME} \
        --task-definition ${TASK_FAMILY} \
        --force-new-deployment \
        --region ${AWS_REGION} > /dev/null
    
    echo -e "${GREEN}✅ Serviço atualizado${NC}"
fi
echo ""

# 7. Aguardar serviço estabilizar
echo -e "${YELLOW}⏳ Aguardando serviço iniciar...${NC}"
sleep 30

# Verificar status do serviço
SERVICE_STATUS=$(aws ecs describe-services \
    --cluster ${CLUSTER_NAME} \
    --services ${SERVICE_NAME} \
    --query "services[0].deployments[0].rolloutState" \
    --output text)

echo -e "${YELLOW}Status do deployment: ${SERVICE_STATUS}${NC}"

# 8. Obter IP público da task
echo -e "${YELLOW}8. Obtendo IP público...${NC}"

# Tentar obter task ARN (pode não estar pronto ainda)
TASK_ARN=$(aws ecs list-tasks --cluster ${CLUSTER_NAME} --service-name ${SERVICE_NAME} --query "taskArns[0]" --output text 2>/dev/null || echo "None")

if [ "$TASK_ARN" == "None" ] || [ -z "$TASK_ARN" ]; then
    echo -e "${YELLOW}⚠️  Task ainda não está disponível. Aguardando...${NC}"
    sleep 20
    TASK_ARN=$(aws ecs list-tasks --cluster ${CLUSTER_NAME} --service-name ${SERVICE_NAME} --query "taskArns[0]" --output text)
fi

if [ "$TASK_ARN" != "None" ] && [ -n "$TASK_ARN" ]; then
    ENI_ID=$(aws ecs describe-tasks --cluster ${CLUSTER_NAME} --tasks ${TASK_ARN} --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" --output text 2>/dev/null || echo "")
    
    if [ -n "$ENI_ID" ]; then
        PUBLIC_IP=$(aws ec2 describe-network-interfaces --network-interface-ids ${ENI_ID} --query "NetworkInterfaces[0].Association.PublicIp" --output text 2>/dev/null || echo "")
    fi
fi

if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" == "None" ]; then
    PUBLIC_IP="Aguardando atribuição de IP..."
fi

echo ""
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}  ✅ ECS Fargate Configurado!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo -e "🌐 ${GREEN}URL da API:${NC}"
echo "   http://${PUBLIC_IP}"
echo ""
echo -e "📖 ${GREEN}Swagger:${NC}"
echo "   http://${PUBLIC_IP}/swagger"
echo ""
echo -e "${YELLOW}⚠️  Nota: O IP é temporário. Para produção, use um Application Load Balancer.${NC}"
echo ""
echo -e "${YELLOW}📊 Ver logs:${NC}"
echo "   aws logs tail /ecs/${TASK_FAMILY} --follow --region ${AWS_REGION}"
echo ""
echo -e "${YELLOW}🔍 Gerenciar:${NC}"
echo "   aws ecs describe-services --cluster ${CLUSTER_NAME} --services ${SERVICE_NAME}"
echo ""

# Salvar informações
cat >> aws-resources.txt << EOF

ECS Fargate:
  Cluster: ${CLUSTER_NAME}
  Service: ${SERVICE_NAME}
  Public IP: ${PUBLIC_IP}
  Task Definition: ${TASK_FAMILY}
EOF

echo -e "${GREEN}✅ Informações atualizadas em: aws-resources.txt${NC}"
echo ""
