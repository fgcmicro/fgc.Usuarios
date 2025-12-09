#!/bin/bash

# Script para fazer build e push da imagem Docker para ECR
# Execute com: bash scripts/deploy-image.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

AWS_REGION="us-east-1"
ECR_REPO_NAME="usuarios-api"
IMAGE_TAG="${1:-latest}"

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}  Docker Build & Push to ECR${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""

# Verificar se Docker está rodando
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Docker não está rodando. Por favor, inicie o Docker.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Docker está rodando${NC}"

# Obter Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}✅ Account ID: ${ACCOUNT_ID}${NC}"

# URI completo do ECR
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"

# Login no ECR
echo -e "${YELLOW}🔐 Fazendo login no ECR...${NC}"
aws ecr get-login-password --region ${AWS_REGION} | \
    docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

echo -e "${GREEN}✅ Login no ECR realizado${NC}"
echo ""

# Build da imagem
echo -e "${YELLOW}🔨 Construindo imagem Docker...${NC}"
docker build -t ${ECR_REPO_NAME}:${IMAGE_TAG} .

echo -e "${GREEN}✅ Imagem construída com sucesso${NC}"
echo ""

# Tag da imagem
echo -e "${YELLOW}🏷️  Tagueando imagem...${NC}"
docker tag ${ECR_REPO_NAME}:${IMAGE_TAG} ${ECR_URI}:${IMAGE_TAG}

if [ "${IMAGE_TAG}" != "latest" ]; then
    docker tag ${ECR_REPO_NAME}:${IMAGE_TAG} ${ECR_URI}:latest
fi

echo -e "${GREEN}✅ Imagem tagueada${NC}"
echo ""

# Push para ECR
echo -e "${YELLOW}📤 Fazendo push para ECR...${NC}"
docker push ${ECR_URI}:${IMAGE_TAG}

if [ "${IMAGE_TAG}" != "latest" ]; then
    docker push ${ECR_URI}:latest
fi

echo -e "${GREEN}✅ Push concluído!${NC}"
echo ""

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}  ✅ Deploy da Imagem Completo!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo -e "📦 ${GREEN}Imagem disponível em:${NC}"
echo "   ${ECR_URI}:${IMAGE_TAG}"
if [ "${IMAGE_TAG}" != "latest" ]; then
    echo "   ${ECR_URI}:latest"
fi
echo ""
echo -e "${YELLOW}🚀 Próximo passo:${NC}"
echo "   Criar ou atualizar o App Runner service"
echo "   bash scripts/create-apprunner.sh"
echo ""
