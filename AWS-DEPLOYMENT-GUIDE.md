# Guia de Deploy na AWS - Projeto Usuarios

Este guia fornece instruções passo a passo para fazer o deploy deste projeto .NET na AWS usando o **Free Tier**.

## 📋 Pré-requisitos

1. **Conta AWS** - Criar conta em [aws.amazon.com](https://aws.amazon.com)
2. **AWS CLI** instalado - [Download](https://aws.amazon.com/cli/)
3. **Docker** instalado localmente
4. **Git** instalado

## 🏗️ Arquitetura AWS

Vamos usar os seguintes serviços (elegíveis ao Free Tier):

- **AWS Elastic Container Registry (ECR)** - Para armazenar a imagem Docker
- **AWS App Runner** - Para executar o container (alternativa mais simples ao ECS)
- **Amazon RDS PostgreSQL** - Banco de dados (750 horas/mês no free tier)
- **AWS Secrets Manager** - Para armazenar credenciais (grátis para 30 dias)
- **AWS CloudWatch** - Para logs e monitoramento

### Alternativa de baixo custo:
- **AWS Lightsail** - Opção mais simples e econômica ($3.50/mês para o menor plano)

---

## 📝 Passo a Passo

### **ETAPA 1: Configurar AWS CLI**

1. Instale o AWS CLI:
```bash
# Windows (PowerShell como admin)
msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi

# Verificar instalação
aws --version
```

2. Configure suas credenciais:
```bash
aws configure
```
Insira:
- **AWS Access Key ID**: (obter no Console AWS → IAM → Security Credentials)
- **AWS Secret Access Key**: (obtido junto com o Access Key)
- **Default region name**: `us-east-1` (ou sua preferência)
- **Default output format**: `json`

---

### **ETAPA 2: Criar Banco de Dados RDS PostgreSQL**

#### 2.1. Via Console AWS (Método Visual)

1. Acesse o **Console AWS** → **RDS**
2. Clique em **Create database**
3. Configurações:
   - **Engine type**: PostgreSQL
   - **Version**: PostgreSQL 15.x
   - **Templates**: **Free tier**
   - **DB instance identifier**: `usuarios-db`
   - **Master username**: `postgres`
   - **Master password**: (escolha uma senha segura)
   - **DB instance class**: `db.t3.micro` ou `db.t4g.micro` (Free Tier)
   - **Storage**: 20 GB (Free Tier permite até 20 GB)
   - **Public access**: **Yes** (para testes)
   - **VPC security group**: Criar novo chamado `usuarios-sg`
   - **Initial database name**: `fcgames`

4. Clique em **Create database**

#### 2.2. Via AWS CLI (Método Automatizado)

```bash
# Criar security group
aws ec2 create-security-group \
  --group-name usuarios-sg \
  --description "Security group for Usuarios DB"

# Obter o ID do security group criado
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=usuarios-sg" \
  --query "SecurityGroups[0].GroupId" \
  --output text)

# Adicionar regra para PostgreSQL (porta 5432)
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 5432 \
  --cidr 0.0.0.0/0

# Criar banco de dados RDS
aws rds create-db-instance \
  --db-instance-identifier usuarios-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --master-username postgres \
  --master-user-password SuaSenhaSegura123! \
  --allocated-storage 20 \
  --db-name fcgames \
  --vpc-security-group-ids $SG_ID \
  --publicly-accessible \
  --backup-retention-period 0 \
  --no-multi-az
```

⏱️ **Aguarde 5-10 minutos** para o banco ser criado.

#### 2.3. Obter endpoint do banco

```bash
aws rds describe-db-instances \
  --db-instance-identifier usuarios-db \
  --query "DBInstances[0].Endpoint.Address" \
  --output text
```

Salve o endpoint, algo como: `usuarios-db.xxxxx.us-east-1.rds.amazonaws.com`

---

### **ETAPA 3: Criar Repositório ECR (Container Registry)**

```bash
# Criar repositório
aws ecr create-repository \
  --repository-name usuarios-api \
  --region us-east-1

# Obter URI do repositório
aws ecr describe-repositories \
  --repository-names usuarios-api \
  --query "repositories[0].repositoryUri" \
  --output text
```

Salve o URI, algo como: `123456789012.dkr.ecr.us-east-1.amazonaws.com/usuarios-api`

---

### **ETAPA 4: Build e Push da Imagem Docker**

1. **Fazer login no ECR**:
```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-east-1.amazonaws.com
```
(Substitua pelo seu account ID)

2. **Build da imagem**:
```bash
# No diretório raiz do projeto
docker build -t usuarios-api .
```

3. **Tag da imagem**:
```bash
docker tag usuarios-api:latest 123456789012.dkr.ecr.us-east-1.amazonaws.com/usuarios-api:latest
```

4. **Push para ECR**:
```bash
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/usuarios-api:latest
```

---

### **ETAPA 5: Deploy com AWS App Runner (RECOMENDADO para Free Tier)**

AWS App Runner é o mais simples e tem free tier de 1000 horas/mês.

#### 5.1. Via Console AWS

1. Acesse **AWS App Runner** → **Create service**
2. Configurações:
   - **Repository type**: Container registry
   - **Provider**: Amazon ECR
   - **Container image URI**: (cole o URI do ECR + :latest)
   - **Deployment trigger**: Manual
   - **ECR access role**: Criar nova role
   - **Service name**: `usuarios-api-service`
   - **Virtual CPU**: 1 vCPU
   - **Memory**: 2 GB
   - **Port**: 80
   - **Environment variables**:
     ```
     ASPNETCORE_ENVIRONMENT = Production
     DatabaseProvider = PostgreSql
     ConnectionStrings__PostgreSql = Host=usuarios-db.xxxxx.rds.amazonaws.com;Port=5432;Database=fcgames;Username=postgres;Password=SuaSenha;Ssl Mode=Require;
     Jwt__Key = 7G+H65bLToXxqzPvj7+q0oQUlxJp1WvdOU3nv3ArA1s=
     Jwt__ExpirationTimeHour = 5
     Jwt__IncreaseExpirationTimeMinutes = 20
     ```

3. Clique em **Create & deploy**

#### 5.2. Via AWS CLI

```bash
# Criar arquivo de configuração
cat > apprunner-config.json << 'EOF'
{
  "SourceConfiguration": {
    "ImageRepository": {
      "ImageIdentifier": "123456789012.dkr.ecr.us-east-1.amazonaws.com/usuarios-api:latest",
      "ImageRepositoryType": "ECR",
      "ImageConfiguration": {
        "Port": "80",
        "RuntimeEnvironmentVariables": {
          "ASPNETCORE_ENVIRONMENT": "Production",
          "DatabaseProvider": "PostgreSql"
        }
      }
    },
    "AutoDeploymentsEnabled": false
  },
  "InstanceConfiguration": {
    "Cpu": "1024",
    "Memory": "2048"
  }
}
EOF

# Criar serviço App Runner
aws apprunner create-service \
  --service-name usuarios-api-service \
  --cli-input-json file://apprunner-config.json
```

---

### **ETAPA 6 (ALTERNATIVA): Deploy com AWS Lightsail**

Opção mais simples e econômica ($3.50/mês):

1. Acesse **AWS Lightsail** → **Create container service**
2. Configurações:
   - **Service location**: Virginia (us-east-1)
   - **Capacity**: Micro (512 MB RAM, 0.25 vCPU) - $7/mês ou Nano - $3.50/mês
   - **Service name**: `usuarios-api`
   
3. **Deployment**:
   - Use a imagem do ECR ou faça push direto via Lightsail
   - Configure as variáveis de ambiente
   - Porta: 80

---

### **ETAPA 7: Testar a Aplicação**

1. Obter URL do serviço:

**App Runner:**
```bash
aws apprunner list-services
```

**Lightsail:**
Acesse o console e copie a URL pública.

2. Testar endpoints:
```bash
# Health check (se existir)
curl https://sua-url-app-runner.us-east-1.awsapprunner.com/health

# Swagger
curl https://sua-url-app-runner.us-east-1.awsapprunner.com/swagger
```

---

## 🔄 CI/CD com GitHub Actions

Crie `.github/workflows/deploy-aws.yml`:

```yaml
name: Deploy to AWS

on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v2
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: us-east-1
    
    - name: Login to Amazon ECR
      id: login-ecr
      uses: aws-actions/amazon-ecr-login@v1
    
    - name: Build and push Docker image
      env:
        ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
        ECR_REPOSITORY: usuarios-api
        IMAGE_TAG: ${{ github.sha }}
      run: |
        docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
        docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
        docker tag $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG $ECR_REGISTRY/$ECR_REPOSITORY:latest
        docker push $ECR_REGISTRY/$ECR_REPOSITORY:latest
    
    - name: Deploy to App Runner
      run: |
        aws apprunner start-deployment --service-arn <seu-service-arn>
```

---

## 💰 Custos Estimados (Free Tier)

- **RDS PostgreSQL**: Grátis (750 horas/mês db.t2.micro + 20GB)
- **ECR**: 500 MB grátis/mês
- **App Runner**: 1000 horas de build + 2000 horas de execução grátis/mês (nos primeiros 3 meses)
- **CloudWatch**: 5GB de logs grátis

**Após Free Tier:**
- RDS: ~$15-20/mês (se deixar ligado 24/7)
- App Runner: ~$10-15/mês
- **Alternativa Lightsail**: $3.50-7/mês (mais previsível)

---

## 🛠️ Comandos Úteis

### Verificar status dos recursos

```bash
# RDS
aws rds describe-db-instances --db-instance-identifier usuarios-db

# App Runner
aws apprunner list-services

# ECR
aws ecr describe-images --repository-name usuarios-api
```

### Logs

```bash
# App Runner logs
aws logs tail /aws/apprunner/usuarios-api-service --follow
```

### Cleanup (destruir recursos)

```bash
# Deletar App Runner service
aws apprunner delete-service --service-arn <service-arn>

# Deletar RDS
aws rds delete-db-instance \
  --db-instance-identifier usuarios-db \
  --skip-final-snapshot

# Deletar imagens ECR
aws ecr batch-delete-image \
  --repository-name usuarios-api \
  --image-ids imageTag=latest

# Deletar repositório ECR
aws ecr delete-repository \
  --repository-name usuarios-api \
  --force
```

---

## 🔐 Segurança

### Usar AWS Secrets Manager (Recomendado)

```bash
# Criar secret
aws secretsmanager create-secret \
  --name usuarios/db-credentials \
  --secret-string '{"username":"postgres","password":"SuaSenha123!"}'

# Obter secret
aws secretsmanager get-secret-value \
  --secret-id usuarios/db-credentials
```

Depois, modifique o código para ler do Secrets Manager.

---

## 📚 Recursos Adicionais

- [AWS Free Tier](https://aws.amazon.com/free/)
- [AWS App Runner Docs](https://docs.aws.amazon.com/apprunner/)
- [Amazon RDS Docs](https://docs.aws.amazon.com/rds/)
- [AWS CLI Reference](https://docs.aws.amazon.com/cli/)

---

## ❓ Troubleshooting

### Problema: App não conecta no RDS
- Verificar security group permite tráfego na porta 5432
- Verificar connection string está correta
- Testar conexão localmente:
  ```bash
  psql -h usuarios-db.xxxxx.rds.amazonaws.com -U postgres -d fcgames
  ```

### Problema: Imagem não faz push para ECR
- Verificar autenticação: `aws ecr get-login-password`
- Verificar permissões IAM

### Problema: App Runner não inicia
- Verificar logs no CloudWatch
- Verificar variáveis de ambiente
- Verificar porta 80 está exposta no Dockerfile

---

## 🎯 Próximos Passos

1. ✅ Configurar monitoramento com CloudWatch
2. ✅ Implementar SSL/TLS (App Runner fornece automaticamente)
3. ✅ Configurar backup automático do RDS
4. ✅ Implementar CI/CD com GitHub Actions
5. ✅ Configurar alertas de custo no AWS Billing

---

**Dúvidas?** Consulte a documentação oficial da AWS ou abra uma issue no repositório.
