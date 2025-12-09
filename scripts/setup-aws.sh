#!/bin/bash

# Script para criar todos os recursos AWS necessários para o projeto Usuarios
# Execute com: bash scripts/setup-aws.sh

set -e  # Exit on error

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configurações
AWS_REGION="us-east-1"
PROJECT_NAME="usuarios"
DB_INSTANCE_ID="${PROJECT_NAME}-db"
ECR_REPO_NAME="${PROJECT_NAME}-api"
RDS_USERNAME="postgres"
RDS_PASSWORD="ChangeMe123!"  # MUDE ISSO!
RDS_DB_NAME="fcgames"
SECURITY_GROUP_NAME="${PROJECT_NAME}-sg"

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}  AWS Setup - Projeto Usuarios${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""

# Verificar se AWS CLI está instalado
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI não encontrado. Por favor, instale: https://aws.amazon.com/cli/${NC}"
    exit 1
fi

echo -e "${GREEN}✅ AWS CLI encontrado${NC}"

# Verificar credenciais AWS
echo -e "${YELLOW}🔍 Verificando credenciais AWS...${NC}"
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}❌ Credenciais AWS não configuradas. Execute 'aws configure'${NC}"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}✅ Autenticado na conta: ${ACCOUNT_ID}${NC}"
echo ""

# =====================================================
# 1. Criar VPC Security Group
# =====================================================
echo -e "${YELLOW}📦 Criando Security Group...${NC}"

SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${SECURITY_GROUP_NAME}" \
    --query "SecurityGroups[0].GroupId" \
    --output text 2>/dev/null || echo "None")

if [ "$SG_ID" == "None" ]; then
    SG_ID=$(aws ec2 create-security-group \
        --group-name ${SECURITY_GROUP_NAME} \
        --description "Security group for ${PROJECT_NAME}" \
        --query 'GroupId' \
        --output text)
    
    echo -e "${GREEN}✅ Security Group criado: ${SG_ID}${NC}"
    
    # Adicionar regra para PostgreSQL
    aws ec2 authorize-security-group-ingress \
        --group-id ${SG_ID} \
        --protocol tcp \
        --port 5432 \
        --cidr 0.0.0.0/0
    
    echo -e "${GREEN}✅ Regra PostgreSQL (5432) adicionada${NC}"
else
    echo -e "${YELLOW}⚠️  Security Group já existe: ${SG_ID}${NC}"
fi
echo ""

# =====================================================
# 2. Criar RDS PostgreSQL
# =====================================================
echo -e "${YELLOW}🗄️  Criando RDS PostgreSQL...${NC}"

DB_STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier ${DB_INSTANCE_ID} \
    --query "DBInstances[0].DBInstanceStatus" \
    --output text 2>/dev/null || echo "not-found")

if [ "$DB_STATUS" == "not-found" ]; then
    echo -e "${YELLOW}⏳ Criando banco de dados (isso pode levar 5-10 minutos)...${NC}"
    
    aws rds create-db-instance \
        --db-instance-identifier ${DB_INSTANCE_ID} \
        --db-instance-class db.t3.micro \
        --engine postgres \
        --engine-version 15.15 \
        --master-username ${RDS_USERNAME} \
        --master-user-password ${RDS_PASSWORD} \
        --allocated-storage 20 \
        --db-name ${RDS_DB_NAME} \
        --vpc-security-group-ids ${SG_ID} \
        --publicly-accessible \
        --backup-retention-period 1 \
        --no-multi-az \
        --storage-type gp2 \
        --no-deletion-protection > /dev/null
    
    echo -e "${GREEN}✅ RDS PostgreSQL criado. Aguardando ficar disponível...${NC}"
    
    # Aguardar até estar disponível
    aws rds wait db-instance-available \
        --db-instance-identifier ${DB_INSTANCE_ID}
    
    echo -e "${GREEN}✅ Banco de dados disponível!${NC}"
else
    echo -e "${YELLOW}⚠️  RDS já existe. Status: ${DB_STATUS}${NC}"
fi

# Obter endpoint do banco
DB_ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier ${DB_INSTANCE_ID} \
    --query "DBInstances[0].Endpoint.Address" \
    --output text)

echo -e "${GREEN}📍 Endpoint do banco: ${DB_ENDPOINT}${NC}"
echo ""

# =====================================================
# 3. Criar Repositório ECR
# =====================================================
echo -e "${YELLOW}📦 Criando repositório ECR...${NC}"

ECR_URI=$(aws ecr describe-repositories \
    --repository-names ${ECR_REPO_NAME} \
    --query "repositories[0].repositoryUri" \
    --output text 2>/dev/null || echo "not-found")

if [ "$ECR_URI" == "not-found" ]; then
    ECR_URI=$(aws ecr create-repository \
        --repository-name ${ECR_REPO_NAME} \
        --region ${AWS_REGION} \
        --query 'repository.repositoryUri' \
        --output text)
    
    echo -e "${GREEN}✅ Repositório ECR criado: ${ECR_URI}${NC}"
else
    echo -e "${YELLOW}⚠️  Repositório ECR já existe: ${ECR_URI}${NC}"
fi
echo ""

# =====================================================
# 4. Criar IAM Role para App Runner
# =====================================================
echo -e "${YELLOW}🔐 Criando IAM Role para App Runner...${NC}"

ROLE_NAME="${PROJECT_NAME}-apprunner-role"

ROLE_ARN=$(aws iam get-role \
    --role-name ${ROLE_NAME} \
    --query 'Role.Arn' \
    --output text 2>/dev/null || echo "not-found")

if [ "$ROLE_ARN" == "not-found" ]; then
    # Criar trust policy inline
    TRUST_POLICY='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"build.apprunner.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

    ROLE_ARN=$(aws iam create-role \
        --role-name ${ROLE_NAME} \
        --assume-role-policy-document "${TRUST_POLICY}" \
        --query 'Role.Arn' \
        --output text)
    
    # Anexar policy para acessar ECR
    aws iam attach-role-policy \
        --role-name ${ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess
    
    echo -e "${GREEN}✅ IAM Role criada: ${ROLE_ARN}${NC}"
else
    echo -e "${YELLOW}⚠️  IAM Role já existe: ${ROLE_ARN}${NC}"
fi
echo ""

# =====================================================
# RESUMO
# =====================================================
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}  ✅ Setup Completo!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo -e "${YELLOW}📋 Informações dos recursos criados:${NC}"
echo ""
echo -e "🗄️  ${GREEN}RDS PostgreSQL:${NC}"
echo -e "   Instance ID: ${DB_INSTANCE_ID}"
echo -e "   Endpoint: ${DB_ENDPOINT}"
echo -e "   Database: ${RDS_DB_NAME}"
echo -e "   Username: ${RDS_USERNAME}"
echo -e "   Password: ${RDS_PASSWORD}"
echo ""
echo -e "📦 ${GREEN}ECR Repository:${NC}"
echo -e "   URI: ${ECR_URI}"
echo ""
echo -e "🔐 ${GREEN}Security Group:${NC}"
echo -e "   ID: ${SG_ID}"
echo ""
echo -e "🔐 ${GREEN}IAM Role:${NC}"
echo -e "   ARN: ${ROLE_ARN}"
echo ""
echo -e "${YELLOW}📝 Connection String:${NC}"
echo "Host=${DB_ENDPOINT};Port=5432;Database=${RDS_DB_NAME};Username=${RDS_USERNAME};Password=${RDS_PASSWORD};Ssl Mode=Require;"
echo ""
echo -e "${YELLOW}🚀 Próximos passos:${NC}"
echo "1. Fazer build e push da imagem Docker:"
echo "   bash scripts/deploy-image.sh"
echo ""
echo "2. Criar App Runner service:"
echo "   bash scripts/create-apprunner.sh"
echo ""
echo -e "${RED}⚠️  IMPORTANTE: Altere a senha do RDS antes de usar em produção!${NC}"
echo ""

# Salvar informações em arquivo
cat > aws-resources.txt << EOF
AWS Resources for ${PROJECT_NAME}
Created: $(date)

RDS PostgreSQL:
  Instance ID: ${DB_INSTANCE_ID}
  Endpoint: ${DB_ENDPOINT}
  Database: ${RDS_DB_NAME}
  Username: ${RDS_USERNAME}
  Password: ${RDS_PASSWORD}

ECR Repository:
  URI: ${ECR_URI}

Security Group:
  ID: ${SG_ID}

IAM Role:
  ARN: ${ROLE_ARN}

Connection String:
Host=${DB_ENDPOINT};Port=5432;Database=${RDS_DB_NAME};Username=${RDS_USERNAME};Password=${RDS_PASSWORD};Ssl Mode=Require;
EOF

echo -e "${GREEN}✅ Informações salvas em: aws-resources.txt${NC}"
