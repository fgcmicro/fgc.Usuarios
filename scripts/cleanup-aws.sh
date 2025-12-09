#!/bin/bash

# Script para destruir todos os recursos AWS criados
# Execute com: bash scripts/cleanup-aws.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

AWS_REGION="us-east-1"
PROJECT_NAME="usuarios"
DB_INSTANCE_ID="${PROJECT_NAME}-db"
ECR_REPO_NAME="${PROJECT_NAME}-api"
SECURITY_GROUP_NAME="${PROJECT_NAME}-sg"
ROLE_NAME="${PROJECT_NAME}-apprunner-role"
SERVICE_NAME="usuarios-api-service"

echo -e "${RED}=====================================${NC}"
echo -e "${RED}  ⚠️  AWS Cleanup - DESTRUIR RECURSOS${NC}"
echo -e "${RED}=====================================${NC}"
echo ""
echo -e "${YELLOW}Este script vai DELETAR permanentemente:${NC}"
echo "  - App Runner Service"
echo "  - RDS Database"
echo "  - ECR Repository e todas as imagens"
echo "  - Security Group"
echo "  - IAM Role"
echo ""
read -p "Tem certeza que deseja continuar? (digite 'yes' para confirmar): " -r
echo

if [ "$REPLY" != "yes" ]; then
    echo -e "${GREEN}Operação cancelada.${NC}"
    exit 0
fi

echo ""
echo -e "${RED}🗑️  Iniciando limpeza...${NC}"
echo ""

# 1. Deletar App Runner Service
echo -e "${YELLOW}1. Deletando App Runner Service...${NC}"
SERVICE_ARN=$(aws apprunner list-services \
    --region ${AWS_REGION} \
    --query "ServiceSummaryList[?ServiceName=='${SERVICE_NAME}'].ServiceArn" \
    --output text 2>/dev/null || echo "")

if [ -n "$SERVICE_ARN" ]; then
    aws apprunner delete-service \
        --service-arn ${SERVICE_ARN} \
        --region ${AWS_REGION} > /dev/null
    echo -e "${GREEN}✅ App Runner Service deletado${NC}"
    
    # Aguardar deleção
    echo -e "${YELLOW}⏳ Aguardando deleção completa...${NC}"
    sleep 30
else
    echo -e "${YELLOW}⚠️  App Runner Service não encontrado${NC}"
fi
echo ""

# 2. Deletar RDS Database
echo -e "${YELLOW}2. Deletando RDS Database...${NC}"
DB_EXISTS=$(aws rds describe-db-instances \
    --db-instance-identifier ${DB_INSTANCE_ID} \
    --query "DBInstances[0].DBInstanceIdentifier" \
    --output text 2>/dev/null || echo "not-found")

if [ "$DB_EXISTS" != "not-found" ]; then
    aws rds delete-db-instance \
        --db-instance-identifier ${DB_INSTANCE_ID} \
        --skip-final-snapshot \
        --delete-automated-backups > /dev/null
    
    echo -e "${GREEN}✅ RDS Database deletado (aguardando...)${NC}"
    
    # Aguardar deleção (pode levar alguns minutos)
    echo -e "${YELLOW}⏳ Isso pode levar alguns minutos...${NC}"
    aws rds wait db-instance-deleted \
        --db-instance-identifier ${DB_INSTANCE_ID} 2>/dev/null || true
    
    echo -e "${GREEN}✅ RDS Database completamente removido${NC}"
else
    echo -e "${YELLOW}⚠️  RDS Database não encontrado${NC}"
fi
echo ""

# 3. Deletar imagens e repositório ECR
echo -e "${YELLOW}3. Deletando ECR Repository...${NC}"
ECR_EXISTS=$(aws ecr describe-repositories \
    --repository-names ${ECR_REPO_NAME} \
    --query "repositories[0].repositoryName" \
    --output text 2>/dev/null || echo "not-found")

if [ "$ECR_EXISTS" != "not-found" ]; then
    # Deletar todas as imagens
    IMAGE_IDS=$(aws ecr list-images \
        --repository-name ${ECR_REPO_NAME} \
        --query 'imageIds[*]' \
        --output json)
    
    if [ "$IMAGE_IDS" != "[]" ]; then
        aws ecr batch-delete-image \
            --repository-name ${ECR_REPO_NAME} \
            --image-ids "$IMAGE_IDS" > /dev/null
        echo -e "${GREEN}✅ Imagens deletadas${NC}"
    fi
    
    # Deletar repositório
    aws ecr delete-repository \
        --repository-name ${ECR_REPO_NAME} \
        --force > /dev/null
    
    echo -e "${GREEN}✅ ECR Repository deletado${NC}"
else
    echo -e "${YELLOW}⚠️  ECR Repository não encontrado${NC}"
fi
echo ""

# 4. Deletar IAM Role
echo -e "${YELLOW}4. Deletando IAM Role...${NC}"
ROLE_EXISTS=$(aws iam get-role \
    --role-name ${ROLE_NAME} \
    --query 'Role.RoleName' \
    --output text 2>/dev/null || echo "not-found")

if [ "$ROLE_EXISTS" != "not-found" ]; then
    # Desanexar políticas
    ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
        --role-name ${ROLE_NAME} \
        --query 'AttachedPolicies[].PolicyArn' \
        --output text)
    
    for POLICY_ARN in $ATTACHED_POLICIES; do
        aws iam detach-role-policy \
            --role-name ${ROLE_NAME} \
            --policy-arn ${POLICY_ARN}
    done
    
    # Deletar role
    aws iam delete-role --role-name ${ROLE_NAME}
    
    echo -e "${GREEN}✅ IAM Role deletada${NC}"
else
    echo -e "${YELLOW}⚠️  IAM Role não encontrada${NC}"
fi
echo ""

# 5. Deletar Security Group
echo -e "${YELLOW}5. Deletando Security Group...${NC}"
SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${SECURITY_GROUP_NAME}" \
    --query "SecurityGroups[0].GroupId" \
    --output text 2>/dev/null || echo "None")

if [ "$SG_ID" != "None" ]; then
    # Tentar deletar (pode falhar se ainda houver recursos usando)
    aws ec2 delete-security-group --group-id ${SG_ID} 2>/dev/null && \
        echo -e "${GREEN}✅ Security Group deletado${NC}" || \
        echo -e "${YELLOW}⚠️  Security Group não pode ser deletado (ainda em uso)${NC}"
else
    echo -e "${YELLOW}⚠️  Security Group não encontrado${NC}"
fi
echo ""

# 6. Remover arquivo de recursos
if [ -f "aws-resources.txt" ]; then
    rm aws-resources.txt
    echo -e "${GREEN}✅ Arquivo aws-resources.txt removido${NC}"
fi

echo ""
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}  ✅ Limpeza Concluída!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo -e "${YELLOW}Todos os recursos AWS foram removidos.${NC}"
echo -e "${YELLOW}Verifique no console AWS se há cobranças pendentes.${NC}"
echo ""
