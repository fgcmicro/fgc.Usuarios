#!/bin/bash

# Script para criar serviço App Runner
# Execute com: bash scripts/create-apprunner.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

AWS_REGION="us-east-1"
SERVICE_NAME="usuarios-api-service"
ECR_REPO_NAME="usuarios-api"

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}  Criar AWS App Runner Service${NC}"
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
ROLE_ARN=$(grep "ARN:" aws-resources.txt | cut -d: -f2- | xargs)

# Obter Account ID e URI do ECR
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:latest"

echo -e "${GREEN}📋 Configurações:${NC}"
echo "   Service Name: ${SERVICE_NAME}"
echo "   ECR Image: ${ECR_URI}"
echo "   Database: ${DB_ENDPOINT}"
echo ""

# Verificar se serviço já existe
SERVICE_ARN=$(aws apprunner list-services \
    --region ${AWS_REGION} \
    --query "ServiceSummaryList[?ServiceName=='${SERVICE_NAME}'].ServiceArn" \
    --output text 2>/dev/null || echo "")

if [ -n "$SERVICE_ARN" ]; then
    echo -e "${YELLOW}⚠️  Serviço já existe: ${SERVICE_NAME}${NC}"
    echo -e "${YELLOW}ARN: ${SERVICE_ARN}${NC}"
    echo ""
    read -p "Deseja atualizar o serviço? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
    
    echo -e "${YELLOW}🔄 Atualizando serviço...${NC}"
    
    aws apprunner update-service \
        --service-arn ${SERVICE_ARN} \
        --source-configuration "ImageRepository={ImageIdentifier=${ECR_URI},ImageRepositoryType=ECR,ImageConfiguration={Port=80,RuntimeEnvironmentVariables={ASPNETCORE_ENVIRONMENT=Production,DatabaseProvider=PostgreSql,ConnectionStrings__PostgreSql=Host=${DB_ENDPOINT};Port=5432;Database=${DB_NAME};Username=${DB_USER};Password=${DB_PASS};Ssl Mode=Require;,Jwt__Key=7G+H65bLToXxqzPvj7+q0oQUlxJp1WvdOU3nv3ArA1s=,Jwt__ExpirationTimeHour=5,Jwt__IncreaseExpirationTimeMinutes=20}}},AutoDeploymentsEnabled=false" \
        --region ${AWS_REGION} > /dev/null
    
    echo -e "${GREEN}✅ Serviço atualizado!${NC}"
else
    echo -e "${YELLOW}🚀 Criando serviço App Runner...${NC}"
    echo -e "${YELLOW}⏳ Isso pode levar alguns minutos...${NC}"
    
    # Criar serviço
    SERVICE_ARN=$(aws apprunner create-service \
        --service-name ${SERVICE_NAME} \
        --source-configuration "ImageRepository={ImageIdentifier=${ECR_URI},ImageRepositoryType=ECR,ImageConfiguration={Port=80,RuntimeEnvironmentVariables={ASPNETCORE_ENVIRONMENT=Production,DatabaseProvider=PostgreSql,ConnectionStrings__PostgreSql=Host=${DB_ENDPOINT};Port=5432;Database=${DB_NAME};Username=${DB_USER};Password=${DB_PASS};Ssl Mode=Require;,Jwt__Key=7G+H65bLToXxqzPvj7+q0oQUlxJp1WvdOU3nv3ArA1s=,Jwt__ExpirationTimeHour=5,Jwt__IncreaseExpirationTimeMinutes=20}}},AutoDeploymentsEnabled=false,AuthenticationConfiguration={AccessRoleArn=${ROLE_ARN}}" \
        --instance-configuration "Cpu=1024,Memory=2048" \
        --health-check-configuration "Protocol=TCP,Path=/,Interval=10,Timeout=5,HealthyThreshold=1,UnhealthyThreshold=5" \
        --region ${AWS_REGION} \
        --query 'Service.ServiceArn' \
        --output text)
    
    echo -e "${GREEN}✅ Serviço criado: ${SERVICE_ARN}${NC}"
fi

echo ""
echo -e "${YELLOW}⏳ Aguardando serviço ficar ativo...${NC}"

# Aguardar serviço ficar running
while true; do
    STATUS=$(aws apprunner describe-service \
        --service-arn ${SERVICE_ARN} \
        --region ${AWS_REGION} \
        --query 'Service.Status' \
        --output text)
    
    echo -e "${YELLOW}Status atual: ${STATUS}${NC}"
    
    if [ "$STATUS" == "RUNNING" ]; then
        break
    elif [ "$STATUS" == "CREATE_FAILED" ] || [ "$STATUS" == "UPDATE_FAILED" ]; then
        echo -e "${RED}❌ Falha ao criar/atualizar serviço${NC}"
        exit 1
    fi
    
    sleep 10
done

# Obter URL do serviço
SERVICE_URL=$(aws apprunner describe-service \
    --service-arn ${SERVICE_ARN} \
    --region ${AWS_REGION} \
    --query 'Service.ServiceUrl' \
    --output text)

echo ""
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}  ✅ App Runner Configurado!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo -e "🌐 ${GREEN}URL da API:${NC}"
echo "   https://${SERVICE_URL}"
echo ""
echo -e "📖 ${GREEN}Swagger:${NC}"
echo "   https://${SERVICE_URL}/swagger"
echo ""
echo -e "🔍 ${GREEN}Health Check:${NC}"
echo "   https://${SERVICE_URL}/health"
echo ""
echo -e "${YELLOW}📋 Service ARN:${NC}"
echo "   ${SERVICE_ARN}"
echo ""
echo -e "${YELLOW}📊 Ver logs:${NC}"
echo "   aws logs tail /aws/apprunner/${SERVICE_NAME} --follow --region ${AWS_REGION}"
echo ""

# Salvar URL em arquivo
echo "Service URL: https://${SERVICE_URL}" >> aws-resources.txt
echo "Service ARN: ${SERVICE_ARN}" >> aws-resources.txt

echo -e "${GREEN}✅ Informações atualizadas em: aws-resources.txt${NC}"
echo ""
