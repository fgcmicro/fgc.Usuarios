# Quick Start Guide - AWS Deployment

## 🚀 Deploy Rápido (3 passos)

### 1️⃣ Instalar AWS CLI

**Windows:**
```bash
# Baixar e instalar
msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi

# Configurar
aws configure
```

Insira suas credenciais quando solicitado (obtenha em AWS Console → IAM → Security Credentials).

### 2️⃣ Criar Recursos AWS

Execute o script automatizado:

```bash
# Dar permissão de execução (Git Bash no Windows)
chmod +x scripts/*.sh

# Criar todos os recursos
bash scripts/setup-aws.sh
```

Este script cria:
- ✅ RDS PostgreSQL database
- ✅ ECR repository
- ✅ Security groups
- ✅ IAM roles

**Tempo estimado:** 10-15 minutos

### 3️⃣ Deploy da Aplicação

```bash
# Build e push da imagem Docker
bash scripts/deploy-image.sh

# Criar serviço ECS Fargate (alternativa ao App Runner)
bash scripts/create-ecs-fargate.sh
```

**Pronto!** Sua aplicação estará disponível na URL fornecida.

---

## 🧪 Testar Localmente (Docker Compose)

Antes de fazer deploy na AWS, teste localmente:

```bash
# Subir PostgreSQL e API
docker-compose up

# Acessar
# API: http://localhost:8080
# Swagger: http://localhost:8080/swagger
```

---

## 🔄 CI/CD com GitHub Actions

### Configurar Secrets no GitHub

1. Vá em: **Settings → Secrets and variables → Actions**
2. Adicione:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`

### Ativar Workflow

O workflow está em `.github/workflows/deploy-aws.yml` e executa automaticamente em push para `main`.

---

## 🧹 Limpar Recursos

Para deletar todos os recursos e evitar cobranças:

```bash
bash scripts/cleanup-aws.sh
```

---

## 💰 Custos Estimados

**Free Tier (primeiros 12 meses):**
- RDS: Grátis (750h/mês)
- App Runner: Grátis primeiros 3 meses
- ECR: 500 MB grátis

**Após Free Tier:**
- ~$25-30/mês (se deixar ligado 24/7)
- **Dica:** Desligue o RDS quando não estiver usando

---

## 📚 Documentação Completa

Para instruções detalhadas, consulte: **[AWS-DEPLOYMENT-GUIDE.md](./AWS-DEPLOYMENT-GUIDE.md)**

---

## ❓ Problemas Comuns

### App não conecta no banco
```bash
# Verificar security group
aws ec2 describe-security-groups --group-names usuarios-sg

# Testar conexão
psql -h <RDS_ENDPOINT> -U postgres -d fcgames
```

### Imagem não faz push
```bash
# Refazer login no ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com
```

### Ver logs do App Runner
```bash
aws logs tail /aws/apprunner/usuarios-api-service --follow
```

---

## 🎯 Arquivos Importantes

```
├── AWS-DEPLOYMENT-GUIDE.md      # Guia completo
├── docker-compose.yml           # Teste local
├── buildspec.yml                # AWS CodeBuild
├── .github/workflows/
│   └── deploy-aws.yml          # CI/CD GitHub Actions
└── scripts/
    ├── setup-aws.sh            # Criar recursos
    ├── deploy-image.sh         # Build e push
    ├── create-apprunner.sh     # Deploy app
    └── cleanup-aws.sh          # Limpar recursos
```

---

**Precisa de ajuda?** Consulte o guia completo ou abra uma issue.
