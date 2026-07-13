# Toggle Master Microservices - Deploy de Infraestrutura na AWS



[Objetivo do Projeto](##2-objetivo-do-projeto)

[Teste Local e criação dos Dockerfiles](##3-execução-local-e-criação-dos-dockerfiles)

[Infraestrutura na Nuvem (Console AWS e eksctl)](#4-infraestrutura-na-nuvem-console-aws-e-eksctl)

[Escalabilidade Horizontal](#5-escalabilidade-horizontal)

[Orquestração e Implantação (Manifestos)](#6-orquestração-e-implantação-manifestos)

[Testes da Aplicação no Cloud e Escalabilidade](#testes-da-aplicação-no-cloud-e-escalabilidade)

[Arquitetura e Desafios Encontrados](#7-arquitetura-e-desafios-encontrados)

[Diferença de Bancos](#8-diferença-de-bancos)

[Vídeo de Apresentação](#9-vídeo-de-apresentação)



## **1. Identificação do Projeto**

- **Projeto:** Toggle Master Microservices
- **Fase:** 02 - Microserviços e Infraestrutura AWS
- **Integrantes:** Grupo 53
  - Arthur de Castilho Nascimento - RM371601 - [castartx@gmail.com](mailto:castartx@gmail.com)
  - Gerusa Fernandes Lobo Nogueira - RM367568 - [gerusalobo@gmail.com](mailto:gerusalobo@gmail.com)
  - Lorenzo Ghisi de Figueiredo - RM372288 - [http.figueiredo@gmail.com](mailto:http.figueiredo@gmail.com)
  - José Henrique Cavalcanti de Melo Filho -  RM 372074 - [meloricke.bra@gmail.com](mailto:meloricke.bra@gmail.com)
  - Pedro Vinicius Araujo Negreiros - RM372553 - [pedro28vinicius@hotmail.com](mailto:pedro28vinicius@hotmail.com)




## 2. Objetivo do Projeto

A arquitetura foi dividida nos em 5 microsserviços:

- **auth-service (Go)**: Gerencia chaves de API e autenticação. (Banco de Dados: PostgreSQL) 

- **flag-service (Python)**: CRUD das definições das feature flags. (Banco de Dados: PostgreSQL) 

- **targeting-service (Python)**: Gerencia regras complexas de segmentação. (Banco de Dados: PostgreSQL) 

- **evaluation-service (Go)**: O "caminho quente" (hot path) de alta performance que retorna a decisão final (true/false). (Cache: Redis) 

- **analytics-service (Python)**: Consome eventos de uma fila e salva dados de análise. (Fila: AWS SQS, Banco de Dados: AWS DynamoDB)

A missão desse projeto é projetar e implementar a infraestrutura de contêineres e orquestração para colocar esse novo ecossistema em produção na AWS.

## 3. Teste Local e criação dos Dockerfiles

Preparação de cada microserviço, para rodar localmente, criando os DockerFiles e rodando através de Dockercompose.

![image-20260712150534788](./img/image-20260712150534788.png)

### 3.1 auth-service

Aplicação em Go com banco PostgreSQL

Foi criado o DockerFile, para a aplicação:

```
# ==========================
# Build Stage
# ==========================
FROM golang:1.21 AS builder

WORKDIR /app

COPY go.mod .
COPY go.sum .

RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o auth-service .

# ==========================
# Runtime Stage
# ==========================
FROM alpine:3.20

WORKDIR /app

RUN apk --no-cache add ca-certificates

COPY --from=builder /app/auth-service .

EXPOSE 8001

CMD ["./auth-service"]
```

Imagem: 30.4MB

[Dockerfile](docker/auth-service-main/Dockerfile)

[ReadMe do Auth Service](docker/auth-service-main/README.md)

Durante a ativação local, foram identificados alguns ajustes necessários para que a aplicação rodasse:

Imports não usados e removidos

```
./handlers.go:4:2: "crypto/sha256" imported and not used

./handlers.go:5:2: "encoding/hex" imported and not used

./key.go:7:2: "fmt" imported and not used

./main.go:5:2: "fmt" imported and not used

./main.go:10:2: "github.com/jackc/pgx/v4/stdlib" imported and not used
```

E incluído o:

_ "github.com/jackc/pgx/v4/stdlib" no main.go para registrar o drive do postgres

Foi necessário rodar manualmente o go mod tidy para criar o go sum.

Dentro do Docker Compose foi criadas as condições para que o app só rode após o banco estar ativo.

```
services:

  auth-service:
    build: ./auth-service-main
    ports:
      - "8001:8001"
    environment:
      DATABASE_URL: postgres://admin:123@postgres-auth:5432/auth_db?sslmode=disable
      PORT: 8001
      MASTER_KEY: admin-secreto-123
    depends_on:
      postgres-auth:
        condition: service_healthy
        
  postgres-auth:
    image: postgres:16
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: 123
      POSTGRES_DB: auth_db
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U admin -d auth_db"]
      interval: 5s
      timeout: 5s
      retries: 10
    volumes:
      - auth_data:/var/lib/postgresql/data
      - ./auth-service-main/db/init.sql:/docker-entrypoint-initdb.d/init.sql
```



### 3.2 flag-service

Aplicação em Python com banco PostgresSQL

Durante a importação das bibliotecas, verificamos erros de versão do Flask.

O requirements.txt foi ajustado para:

```
Flask==3.0.0
werkzeug==3.0.1
psycopg2-binary==2.9.5
gunicorn==20.1.0
python-dotenv==0.21.0
requests==2.28.1
```

Dockerfile: 

Apesar do Python não precisar compilar, colocamos 2 estágios para poder deixar a imagem final menor copiando apenas o necessário, com uma redução de 541M para 210M = 61%

```
# ==========================
# Build Stage
# ==========================
FROM python:3.11-slim AS builder

WORKDIR /app

# Instala as dependências necessárias para build
RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

# Instala as dependências em um diretório separado
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ==========================
# Runtime Stage
# ==========================

FROM python:3.11-slim

WORKDIR /app

# Copia as dependências já instaladas
COPY --from=builder /install /usr/local

# Copia o código da aplicação
COPY app.py .
COPY db ./db

EXPOSE 8002

CMD ["gunicorn", "--bind", "0.0.0.0:8002", "app:app"]
```

Imagem: 210MB

[Dockerfile](docker/flag-service-main/Dockerfile)

[ReadMe do Flag Service](docker/flag-service-main/README.md)

No docker-compose, foi necessário colocar as dependências do auth e banco:

```
flag-service:
    build: ./flag-service-main
    ports:
      - "8002:8002"
    environment:
      DATABASE_URL: postgres://admin:123@postgres-flags:5432/flags_db?sslmode=disable
      AUTH_SERVICE_URL: http://auth-service:8001
      PORT: 8002
    depends_on:
      auth-service:
        condition: service_started
      postgres-flags:
        condition: service_healthy
        
  postgres-flags:
    image: postgres:16
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: 123
      POSTGRES_DB: flags_db
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U admin -d flags_db"]
      interval: 5s
      timeout: 5s
      retries: 10
    volumes:
      - flags_data:/var/lib/postgresql/data
      - ./flag-service-main/db/init.sql:/docker-entrypoint-initdb.d/init.sql
```



### 3.3 targeting-service

Aplicação em Python com banco PostgresSQL

Durante a importação das bibliotecas, verificamos erros de versão do Flask.

O requirements.txt foi ajustado para:

```
Flask==3.0.0
werkzeug==3.0.1
psycopg2-binary==2.9.5
gunicorn==20.1.0
python-dotenv==0.21.0
requests==2.28.1
```

Dockerfile:

Apesar do Python não precisar compilar, colocamos 2 estágios para poder deixar a imagem final menor copiando apenas o necessário, com uma redução de 529M para 210M = 60%

```
# ==========================
# Build Stage
# ==========================
FROM python:3.11-slim AS builder

WORKDIR /app

# Instala as dependências necessárias para build
RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc libpq-dev && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

# Instala as dependências em um diretório separado
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ==========================
# Runtime Stage
# ==========================
FROM python:3.11-slim

WORKDIR /app

# Copia as dependências já instaladas
COPY --from=builder /install /usr/local

# Copia o código da aplicação
COPY app.py .
COPY db ./db

EXPOSE 8003

CMD ["gunicorn", "--bind", "0.0.0.0:8003", "app:app"]
```
Imagem: 210M

[Dockerfile](docker/targeting-service-main/Dockerfile)

[ReadMe do Targeting Service](docker/targeting-service-main/README.md)

No docker-compose, foi necessário colocar as dependências do auth e banco:

```
  targeting-service:
    build: ./targeting-service-main
    ports:
      - "8003:8003"
    environment:
      DATABASE_URL: postgres://admin:123@postgres-targeting:5432/targeting_db
      AUTH_SERVICE_URL: http://auth-service:8001
      PORT: 8003
    depends_on:
      auth-service:
        condition: service_started
      postgres-targeting:
        condition: service_healthy
  
  postgres-targeting:
    image: postgres:16
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: 123
      POSTGRES_DB: targeting_db
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U admin -d targeting_db"]
      interval: 5s
      timeout: 5s
      retries: 10
    volumes:
      - targeting_data:/var/lib/postgresql/data
      - ./targeting-service-main/db/init.sql:/docker-entrypoint-initdb.d/init.sql
```

### 3.4 evaluation-service

Aplicação em Go usando o Redis e o SQS da AWS

Para a aplicação em Go rodar, foram necessários alguns ajustes de pacotes:

```
0.241 main.go:10:2: missing go.sum entry for module providing package github.com/aws/aws-sdk-go/aws (imported by evaluation-service); to add:
0.241   go get evaluation-service
0.241 main.go:11:2: missing go.sum entry for module providing package github.com/aws/aws-sdk-go/aws/session (imported by evaluation-service); to add:
0.241   go get evaluation-service
0.241 main.go:12:2: missing go.sum entry for module providing package github.com/aws/aws-sdk-go/service/sqs (imported by evaluation-service); to add:
0.241   go get evaluation-service
0.241 main.go:13:2: missing go.sum entry for module providing package github.com/go-redis/redis/v8 (imported by evaluation-service); to add:
0.241   go get evaluation-service
0.241 main.go:14:2: missing go.sum entry for module providing package github.com/joho/godotenv (imported by evaluation-service); to add:
0.241   go get evaluation-service
```

Rodamos o go mod tidy para atualizar o go sum.

Retiramos do evaluation Go o "context" e inserimos o "os"

Dockerfile:

```
# ==========================
# Build Stage
# ==========================
FROM python:3.11-slim AS builder

ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Instala as dependências necessárias para build
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

# Instala as dependências em um diretório separado
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ==========================
# Runtime Stage
# ==========================
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Copia as dependências já instalada
COPY --from=builder /install /usr/local

# Copia o código da aplicação
COPY app.py .
COPY db ./db

EXPOSE 8005

CMD ["gunicorn", "--bind", "0.0.0.0:8005", "app:app"]
```

Imagem: 35.7MB

[Dockerfile](docker/evaluation-service-main/Dockerfile)

[ReadMe do Evaluation Service](docker/evaluation-service-main/README.md)

Foi criado também um .env para as variáveis de ambiente.

```
SERVICE_API_KEY=tm_key_112...
AWS_DYNAMODB_ENDPOINT: http://dynamodb:8000
AWS_DYNAMODB_TABLE="ToggleMasterAnalytics"
aws_region=us-east-1
AWS_SQS_URL=https://sqs.us-east-1.amazonaws.com/XXXXX.../togglemaster-events
aws_access_key_id=ASI
aws_secret_access_key=aBrt...
aws_session_token=IQoJ...
```

No docker-compose, foram colocadas as dependências com os outros serviços e o redis:

```
  evaluation-service:
    build: ./evaluation-service-main
    ports:
      - "8004:8004"
    environment:
      PORT: 8004
      REDIS_URL: redis://redis:6379
      FLAG_SERVICE_URL: http://flag-service:8002
      TARGETING_SERVICE_URL: http://targeting-service:8003
      SERVICE_API_KEY: ${SERVICE_API_KEY}
      AWS_ACCESS_KEY_ID: ${aws_access_key_id}
      AWS_SECRET_ACCESS_KEY: ${aws_secret_access_key}
      AWS_SESSION_TOKEN: ${aws_session_token}
      AWS_REGION: ${aws_region}
      AWS_SQS_URL: ${AWS_SQS_URL}
    depends_on:
      redis:
        condition: service_healthy
      flag-service:
        condition: service_started
      targeting-service:
        condition: service_started
        
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5
```
### 3.5 analytics-service

Aplicação em Python conectada ao DynamoDB Local e consumindo a fila SQS.

Durante a importação das bibliotecas, verificamos erros de versão do Flask.

O requirements.txt foi ajustado para:

```
Flask==3.0.0
gunicorn==20.1.0
python-dotenv==0.21.0
boto3>=1.34.0
```

Para uso com o DynamoDB Local no lugar do Dynamo da AWS, foi necessária a criação de uma variável de ambiente e ajustado o código da aplicação: AWS_DYNAMODB_ENDPOINT

Caso não tenha essa variável, ele vai olhar para o Synamo na AWS.

```
# --- Configuração ---
AWS_REGION = os.getenv("AWS_REGION")
SQS_QUEUE_URL = os.getenv("AWS_SQS_URL")
DYNAMODB_TABLE_NAME = os.getenv("AWS_DYNAMODB_TABLE")
DYNAMODB_ENDPOINT = os.getenv("AWS_DYNAMODB_ENDPOINT") #alteração para uso local <----

if not all([AWS_REGION, SQS_QUEUE_URL, DYNAMODB_TABLE_NAME]):
    log.critical("Erro: AWS_REGION, AWS_SQS_URL, e AWS_DYNAMODB_TABLE devem ser definidos.")
    sys.exit(1)

# --- Clientes Boto3 ---
# Criamos a sessão uma vez
try:
    session = boto3.Session(region_name=AWS_REGION)
    sqs_client = session.client("sqs")
    
    #alteração para uso local tb ------>
    
    #dynamodb_client = session.client("dynamodb")

    if DYNAMODB_ENDPOINT:
        log.info(f"Usando DynamoDB Local: {DYNAMODB_ENDPOINT}")

        dynamodb_client = session.client(
            "dynamodb",
            endpoint_url=DYNAMODB_ENDPOINT,
            aws_access_key_id="dummy",
            aws_secret_access_key="dummy",
        )
    else:
        log.info("Usando DynamoDB AWS")

        dynamodb_client = session.client("dynamodb")
    
    # fim da alteração --------

    log.info(f"Clientes Boto3 inicializados na região {AWS_REGION}")


except NoCredentialsError:
    log.critical("Credenciais da AWS não encontradas. Verifique seu ambiente.")
    sys.exit(1)
except Exception as e:
    log.critical(f"Erro ao inicializar o Boto3: {e}")
    sys.exit(1)

```

Foi necessário subir o Dynamo e criar a tabela previamente para a primeira execução:

```
aws dynamodb create-table \
  --table-name ToggleMasterAnalytics \
  --attribute-definitions AttributeName=event_id,AttributeType=S \
  --key-schema AttributeName=event_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --endpoint-url http://localhost:8000 \
  --region us-east-1
```

E validar se a tabela foi criada:

```
aws dynamodb list-tables \
  --endpoint-url http://localhost:8000 \
  --region us-east-1
```

Dockerfile:

Apesar do Python não precisar compilar, colocamos 2 estágios para poder deixar a imagem final menor copiando apenas o necessário, com uma redução de 747M para 248M = 67%

```
# ==========================
# Build Stage
# ==========================
FROM python:3.11-slim AS builder

ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Instala as dependências necessárias para build
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

# Instala as dependências em um diretório separado
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ==========================
# Runtime Stage
# ==========================
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Copia as dependências já instalada
COPY --from=builder /install /usr/local

# Copia o código da aplicação
COPY app.py .

EXPOSE 8005

CMD ["gunicorn", "--bind", "0.0.0.0:8005", "app:app"]
```
[Dockerfile](docker/analytics-service-main/Dockerfile)

[ReadMe do Analytics Service](docker/analytics-service-main/README.md)

No docker-compose, foram colocadas as dependências com os outros serviços e as variáveis de ambiente:

```
  analytics-service:
    build: ./analytics-service-main
    ports:
      - "8005:8005"
    environment:
      AWS_DYNAMODB_TABLE: ToggleMasterAnalytics
      AWS_DYNAMODB_ENDPOINT: http://dynamodb:8000
      AWS_ACCESS_KEY_ID: ${aws_access_key_id}
      AWS_SECRET_ACCESS_KEY: ${aws_secret_access_key}
      AWS_SESSION_TOKEN: ${aws_session_token}
      AWS_REGION: ${aws_region}
      AWS_SQS_URL: ${AWS_SQS_URL}
    depends_on:
          flag-service:
            condition: service_started
          targeting-service:
            condition: service_started
            
  dynamodb:
    image: amazon/dynamodb-local:latest
    container_name: dynamodb-local
    command: "-jar DynamoDBLocal.jar -sharedDb -dbPath /data"
    ports:
      - "8000:8000"
    volumes:
      - dynamodb_data:/data
    user: "root"
```

O dynamodb precisa rodar com o user: root senão não persiste os dados no banco, porque o SQLite falha.



### 3.6 Testes Locais

Para o teste local, foi criado um dockercompose e uma rede local, assim como volumes para o auth, flags e targeting services.

[docker-compose](./docker/docker-compose.yml)

Foi criado um plano de teste em bash para testar os serviços: auth, flags, targeting e evaluation.

Esse teste pode ser usado depois para Produção, só trocando as urls de acesso.

[Plano de Teste](./test.sh)

##### Ajustes

Ao startar o lab é necessário pegar as novas credenciais e colocar no .env

##### Ativando o docker-compose:

![image-20260628150820249](./img/image-20260628150820249.png)

##### Rodando o teste automatizado

No terminal do projeto: $./test.sh

```
========================================
AMBIENTE DE TESTE
========================================
AUTH      : http://localhost:8001
FLAG      : http://localhost:8002
TARGETING : http://localhost:8003
EVALUATION : http://localhost:8004
ANALYTICS : http://localhost:8005

========================================
1. Health Check
========================================
{"status":"ok"}


{"status":"ok"}


{"status":"ok"}


{"status":"ok"}


{"status":"ok"}



========================================
2. Criando API Key
========================================
API KEY:
tm_key_b7b0a93428b7134960b11077461b941d4d93b2913b22fbe6d57b3524589e7348


========================================
3. Criando Flag
========================================
{"created_at":"Sun, 28 Jun 2026 18:29:37 GMT","description":"Teste automatizado","id":24,"is_enabled":true,"name":"enable-new-dashboard-1782671375","updated_at":"Sun, 28 Jun 2026 18:29:37 GMT"}


========================================
4. Listando Flags
========================================
Flags encontradas:
enable-new-dashboard-1780855960
enable-new-dashboard-1782671375


========================================
5. Consultando Flag
========================================
{"created_at":"Sun, 28 Jun 2026 18:29:37 GMT","description":"Teste automatizado","id":24,"is_enabled":true,"name":"enable-new-dashboard-1782671375","updated_at":"Sun, 28 Jun 2026 18:29:37 GMT"}


========================================
6. Atualizando Flag
========================================
{"created_at":"Sun, 28 Jun 2026 18:29:37 GMT","description":"Teste automatizado","id":24,"is_enabled":false,"name":"enable-new-dashboard-1782671375","updated_at":"Sun, 28 Jun 2026 18:29:37 GMT"}


========================================
7. Criando Regra de Targeting
========================================
{"created_at":"Sun, 28 Jun 2026 18:29:37 GMT","flag_name":"enable-new-dashboard-1782671375","id":24,"is_enabled":true,"rules":{"type":"PERCENTAGE","value":50},"updated_at":"Sun, 28 Jun 2026 18:29:37 GMT"}


========================================
8. Consultando Regra
========================================
{"created_at":"Sun, 28 Jun 2026 18:29:37 GMT","flag_name":"enable-new-dashboard-1782671375","id":24,"is_enabled":true,"rules":{"type":"PERCENTAGE","value":50},"updated_at":"Sun, 28 Jun 2026 18:29:37 GMT"}


========================================
9. Atualizando Regra
========================================
{"created_at":"Sun, 28 Jun 2026 18:29:37 GMT","flag_name":"enable-new-dashboard-1782671375","id":24,"is_enabled":true,"rules":{"type":"PERCENTAGE","value":75},"updated_at":"Sun, 28 Jun 2026 18:29:37 GMT"}


========================================
10. Testando a fila SQS e o processamento
========================================
user 1 - user-1782671375
=== Request 1 ===
{"flag_name":"enable-new-dashboard-1782671375","user_id":"user-1782671375","result":false}


=== Request 2 ===
{"flag_name":"enable-new-dashboard-1782671375","user_id":"user-1782671375","result":false}




user 2 - user-1782671377
=== Request 1 ===
{"flag_name":"enable-new-dashboard-1780855960","user_id":"user-1782671377","result":false}


=== Request 2 ===
{"flag_name":"enable-new-dashboard-1780855960","user_id":"user-1782671377","result":false}




========================================
11. Deletando Flag
========================================
FLAG_NAME=enable-new-dashboard-1782671375
Flag removida com sucesso.


TESTE FINALIZADO COM SUCESSO
```

##### Verificando os logs dos Serviços

![image-20260628153031445](./img/image-20260628153031445.png)

Tabela do Dynamo Local

![image-20260628153300362](./img/image-20260628153300362.png)


##### Verificando na AWS

E no SQS aparece vazio.

Porque o Analytics apaga da fila após o processamento.

<img src="./img/image-20260614124825626.png" alt="image-20260614124825626" style="zoom:150%;" />

O Fluxo está rodando corretamente:

<img src="./img/image-20260614124731715.png" alt="image-20260614124731715" style="zoom:150%;" />

![image-20260712145620620](./img/image-20260712145620620.png)



### 3.7 Deploy do Repositório e Teste Local

Depois do clone do Repositório, é preciso criar um .env com os seguintes dados:

- SERVICE_API_KEY

- AWS_DYNAMODB_TABLE="ToggleMasterAnalytics"

- AWS_DYNAMODB_ENDPOINT=http://dynamodb-local:8000

- aws_region=us-east-1

- AWS_SQS_URL

- aws_access_key_id

- aws_secret_access_key

- aws_session_token



Como o SQS fica na AWS, os dados de:

- aws_access_key_id

- aws_secret_access_key

- aws_session_token

Caso esteja usando o Lab, esses dados são obtidos em: AWS Details/AWS CLI/show

![image-20260628155338416](./img/image-20260628155338416.png)



E é necessário criar uma fila SQS na AWS e colocar a url no AWS_SQS_URL



Para a primeira execução é necessário:

- Subir o auth com seu banco e criar um a API_KEY essa API_Key será usada no .env como SERVICE_API_KEY.

- Subir o dynamo e criar a tabela "ToggleMasterAnalytics".



Na sequencia, dar o comando: docker compose down e, depois um docker compose up.

## 4. Infraestrutura na Nuvem (Console AWS e eksctl)

**Resumo da Infraestrutura AWS – Toggle Master Microservices**

**Região AWS**

AWS_REGION=us-east-1

###  4.1 Configuração do Cluster e da Escalabilidade dos Nós

![27a11a8f-aa29-480e-8dd5-19e9c6fbcc51](./img/27a11a8f-aa29-480e-8dd5-19e9c6fbcc51.png)

Por usar nodes t3-micro (free tier), tivemos dificuldade com a instalação do nginx com a quantidade de pods que cabe nos nodes (apenas 4 por node). 

**Dessa forma alteramos a escalabilidade do projeto para 6,8 e 12 nodes.**

![image-20260712131617632](./img/image-20260712131617632.png)

![image-20260712131636818](./img/image-20260712131636818.png)

#### Ativação das Métricas

![image-20260712131656084](./img/image-20260712131656084.png)

Observações: 

- Para o Evaluation estamos usando o método HPA
- Para o Analytics o KEDA

#### Nginx Ingress Controller

A ativação do Nginx foi através de comandos:

```
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.service.type=LoadBalancer \
  --set controller.publishService.enabled=true \
  --set controller.admissionWebhooks.enabled=false
```

![image-20260712131715372](./img/image-20260712131715372.png)

### 4.2 Registro dos Containers (ECR)

Foram criados os seguintes repositórios para armazenamento das imagens Docker dos microsserviços:

| **Microsserviço**  | **Repositório ECR** | **URI**                                                      |
| ------------------ | ------------------- | ------------------------------------------------------------ |
| auth-service       | auth-service        | [708993007071.dkr.ecr.us-east-1.amazonaws.com/auth-service](http://708993007071.dkr.ecr.us-east-1.amazonaws.com/auth-service) |
| flag-service       | flag-service        | [708993007071.dkr.ecr.us-east-1.amazonaws.com/flag-service](http://708993007071.dkr.ecr.us-east-1.amazonaws.com/flag-service) |
| targeting-service  | targeting-service   | [708993007071.dkr.ecr.us-east-1.amazonaws.com/targeting-service](http://708993007071.dkr.ecr.us-east-1.amazonaws.com/targeting-service) |
| evaluation-service | evaluation-service  | [708993007071.dkr.ecr.us-east-1.amazonaws.com/evaluation-service](http://708993007071.dkr.ecr.us-east-1.amazonaws.com/evaluation-service) |
| analytics-service  | analytics-service   | [708993007071.dkr.ecr.us-east-1.amazonaws.com/analytics-service](http://708993007071.dkr.ecr.us-east-1.amazonaws.com/analytics-service) |

Para subir as imagens foi feito o push de cada uma.

![image-20260712131729429](./img/image-20260712131729429.png)

![image-20260712131758844](./img/image-20260712131758844.png)

![image-20260712131813549](./img/image-20260712131813549.png)

### 4.3 Criação dos Bancos RDS, Dynamo, SQS e  Redis

Criando os bancos RDS e o Redis dentro da mesma VPC do cluster

VPC Cluster: "vpc-0fc2987e3d0de4c7c"

**DB-subnet Group**

```
aws rds create-db-subnet-group \
  --db-subnet-group-name toggle-prod-db-subnet-group \
  --db-subnet-group-description "Subnet group for ToggleMaster production databases" \
  --subnet-ids \
    subnet-05b043efc02142437 \
    subnet-0a4b8a833c180a8b3 \
    subnet-0b6d71475b7a04865 \
    subnet-09744adccb3f6691c \
  --region us-east-1 \
  --profile prod
```

![image-20260712131835121](./img/image-20260712131835121.png)

**Security group**

Criar e vincular ao sg do cluster

- VPC: `vpc-0fc2987e3d0de4c7c`
- Subnet Group: `toggle-prod-db-subnet-group`
- SG: `sg-028b6a777708d9e14`

![image-20260712131901945](./img/image-20260712131901945.png)

Criação dos Bancos RDS via CLI:

```
aws rds create-db-instance \
  --db-instance-identifier auth-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 16 \
  --allocated-storage 20 \
  --storage-type gp3 \
  --master-username postgres \
  --master-user-password 'SenhaForte123!' \
  --db-subnet-group-name toggle-prod-db-subnet-group \
  --vpc-security-group-ids sg-028b6a777708d9e14 \
  --no-publicly-accessible \
  --backup-retention-period 0 \
  --region us-east-1 \
  --profile prod
```

Arquitetura

![image-20260712131931602](./img/image-20260712131931602.png)

#### **Amazon RDS (PostgreSQL)**

**Auth Service**

- **Instância:** auth-db
- **Banco:** auth-db
- **Engine:** PostgreSQL
- **Endpoint:** [auth-db.cs5ayiqio5aa.us-east-1.rds.amazonaws.com](http://auth-db.cs5ayiqio5aa.us-east-1.rds.amazonaws.com/)
- **String de Conexão:** postgres://postgres:SENHA@auth-db.cs5ayiqio5aa.us-east-1.rds.amazonaws.com:5432/auth-db?sslmode=require
- **Porta:** 5432
- **Status:** available

criando o banco e as tabelas:

postgres=> CREATE DATABASE "auth-db";

![image-20260712132000005](./img/image-20260712132000005.png)

E a tabela, conforme comando do init.sql do microserviço auth-service

![image-20260712132016319](./img/image-20260712132016319.png)

⸻

**Flag Service**

- **Instância:** flag-db
- **Banco:** flag-db
- **Engine:** PostgreSQL
- **Endpoint:** [flag-db.cs5ayiqio5aa.us-east-1.rds.amazonaws.com](http://flag-db.cs5ayiqio5aa.us-east-1.rds.amazonaws.com/)
- **String de Conexão:** postgres://postgres:SenhaForte123!@flag-db.cs5ayiqio5aa.us-east-1.rds.amazonaws.com:5432/flag-db?sslmode=require
- **Porta:** 5432
- **Status:** available

criando o banco e as tabelas

![image-20260712132040481](./img/image-20260712132040481.png)

⸻

**Targeting Service**

Devido à limitação de quota da conta AWS (máximo de instâncias RDS permitidas), o banco do **targeting-service** foi criado como um banco separado dentro da instância **flag-db**.

**Database:** targeting_db

![image-20260712132100554](./img/image-20260712132100554.png)

Criando o banco e as tabelas:

![image-20260712132126215](./img/image-20260712132126215.png)

**String de conexão:**

postgres://postgres:SenhaForte123!@flag-db.cs5ayiqio5aa.us-east-1.rds.amazonaws.com:5432/targeting-db?sslmode=require

Credenciais:
--master-username postgres 
--master-user-password 'SenhaForte123!'

Observação:

Para a criação dos bancos e tabelas, subimos um pod temporário postgres-client dentro do cluster e usamos para acessar os bancos postgres:

```
kubectl run postgres-client \
  --image=postgres:18 \
  -n toggle-prod \
  --rm -it \
  -- bash
E dentro do terminal do pod, acessar os bancos via psql:
psql \
-h auth-db.cs5ayiqio5aa.us-east-1.rds.amazonaws.com \
-U postgres \
-d postgres \
-p 5432
```

⸻

**Amazon ElastiCache (Redis)**

Criando o SG e vinculando com o cluster.

![image-20260712132147410](./img/image-20260712132147410.png)

Criando a subnet

```
aws elasticache create-cache-subnet-group \
  --cache-subnet-group-name toggle-prod-redis-subnet-group \
  --cache-subnet-group-description "Redis subnet group for ToggleMaster production" \
  --subnet-ids \
    subnet-05b043efc02142437 \
    subnet-0a4b8a833c180a8b3 \
    subnet-0b6d71475b7a04865 \
    subnet-09744adccb3f6691c \
  --region us-east-1 \
  --profile prod
```

![image-20260712132532612](./img/image-20260712132532612.png)

E criando o Redis:

```
aws elasticache create-cache-cluster \
  --cache-cluster-id evaluation-service-redis \
  --engine redis \
  --engine-version 7.1 \
  --cache-node-type cache.t3.micro \
  --num-cache-nodes 1 \
  --cache-subnet-group-name toggle-prod-redis-subnet-group \
  --security-group-ids sg-01a955339afbd9825 \
  --region us-east-1 \
  --profile prod
```

![image-20260712132550688](./img/image-20260712132550688.png)

**Cluster:** evaluation-service-redis

**Endpoint:** [evaluation-service-redis.yumvds.0001.use1.cache.amazonaws.com](http://evaluation-service-redis.yumvds.0001.use1.cache.amazonaws.com/)

**Porta:** 6379

**Utilizado pelo:** evaluation-service

⸻

**Amazon DynamoDB**

**Tabela:** ToggleMasterAnalytics

**Partition Key:** event_id

**Tipo:** String (S)

**ARN:** arn:aws:dynamodb:us-east-1:708993007071:table/ToggleMasterAnalytics

**Status:** ACTIVE

⸻

**Amazon SQS**

**Nome da fila:** evaluation-analytics-queue

**Tipo:** Standard

**URL:** https://sqs.us-east-1.amazonaws.com/708993007071/evaluation-analytics-queue

**ARN:** arn:aws:sqs:us-east-1:708993007071:evaluation-analytics-queue

**Utilização**

**Produtor**

- evaluation-service

**Consumidor**

- analytics-service

Fluxo:

evaluation-service

​    │

​    ▼

Amazon SQS

​    │

​    ▼

analytics-service

​    │

​    ▼

Amazon DynamoDB

⸻

#### **Variáveis de Ambiente**

**auth-service**

AWS_REGION=us-east-1

DATABASE_URL=postgres://postgres:SenhaForte123!@auth-db.cs5ayiqio5aa.us-east-1.rds.amazonaws.com:5432/auth-db?sslmode=require

Master Key: `admin-secreto-123`

⸻

**flag-service**

AWS_REGION=us-east-1

DATABASE_URL=postgres://postgres:SenhaForte123!@flag-db.cs5ayiqio5aa.us-east-1.rds.amazonaws.com:5432/flag-db?sslmode=require

⸻

**targeting-service**

AWS_REGION=us-east-1

DATABASE_URL=postgres://postgres:SenhaForte123!@flag-db.cs5ayiqio5aa.us-east-1.rds.amazonaws.com:5432/targeting-db?sslmode=require

⸻

**evaluation-service**

AWS_REGION=us-east-1

REDIS_HOST=[evaluation-service-redis.yumvds.0001.use1.cache.amazonaws.com](http://evaluation-service-redis.yumvds.0001.use1.cache.amazonaws.com/)

REDIS_PORT=6379

AWS_SQS_URL=https://sqs.us-east-1.amazonaws.com/708993007071/evaluation-analytics-queue

⸻

**analytics-service**

AWS_REGION=us-east-1

AWS_SQS_URL=https://sqs.us-east-1.amazonaws.com/708993007071/evaluation-analytics-queue

AWS_DYNAMODB_TABLE=ToggleMasterAnalytics

⸻

**Recursos Provisionados**

| **Serviço AWS**    | **Recurso**                                         |
| ------------------ | --------------------------------------------------- |
| Amazon ECR         | 5 repositórios                                      |
| Amazon RDS         | 2 instâncias PostgreSQL + 1 database (targeting_db) |
| Amazon ElastiCache | 1 cluster Redis                                     |
| Amazon DynamoDB    | 1 tabela (ToggleMasterAnalytics)                    |
| Amazon SQS         | 1 fila Standard (evaluation-analytics-queue)        |

⸻

**Strings de Conexão Utilizadas na Próxima Etapa**

**auth-db**

postgres://postgres:SenhaForte123!@auth-db.cs5ayiqio5aa.us-east-1.rds.amazonaws.com:5432/auth-db?sslmode=require

**flag-db**

postgres://postgres:SenhaForte123!@flag-db.cs5ayiqio5aa.us-east-1.rds.amazonaws.com:5432/flag-db?sslmode=require

**targeting-db**

postgres://postgres:SenhaForte123!@flag-db.cs5ayiqio5aa.us-east-1.rds.amazonaws.com:5432/targeting-db?sslmode=require

**Redis**

"[evaluation-service-redis.yumvds.0001.use1.cache.amazonaws.com](http://evaluation-service-redis.yumvds.0001.use1.cache.amazonaws.com/)"

**DynamoDB**

Tabela: ToggleMasterAnalytics

ARN: arn:aws:dynamodb:us-east-1:708993007071:table/ToggleMasterAnalytics

**Amazon SQS**

**URL:** https://sqs.us-east-1.amazonaws.com/708993007071/evaluation-analytics-queue

**ARN:** arn:aws:sqs:us-east-1:708993007071:evaluation-analytics-queue

⸻

**Observação:**

A limitação da conta AWS impediu a criação de uma terceira instância RDS. Como alternativa, foi criado o banco targeting_db dentro da instância flag-service-db, mantendo o isolamento lógico entre os serviços e permitindo a continuidade do deployment.

Esse documento já está completo e pode ser usado como referência para a próxima etapa de configuração e deployment dos microsserviços na AWS.

## 5 Escalabilidade Horizonal

Foram utilizadas duas estratégias de escalabilidade.

**HPA (Horizontal Pod Autoscaler)**

- evaluation-service

Escala baseado na utilização de CPU.

**KEDA**

- analytics-service

Escala automaticamente baseado na quantidade de mensagens existentes na fila SQS.

Dessa forma o Analytics permanece com apenas uma réplica em momentos sem carga e aumenta automaticamente durante os testes.

Foi instalado o Keda para uso no Analytics

![image-20260712132637050](./img/image-20260712132637050.png)

Pods do KEDA:

![image-20260712132720807](./img/image-20260712132720807.png)

Componentes:

![image-20260712132738172](./img/image-20260712132738172.png)

E para o Evaluation foi usado o HPA

![image-20260712132751674](./img/image-20260712132751674.png)

## 6 Orquestração e Implantação (Manifestos)

Para ter um único ingress e uma unica url de saída, foi usado um único namespace.

Por questão de economia de nodes, decidimos usar apenas 1 replica para cada microserviço, e no caso do Evaluation e Analitics em case de sobrecarga, pode escalar até 5.

### Namespace.yaml

```
apiVersion: v1
kind: Namespace
metadata:
  name: toggle-prod
```

[namespace.yaml](k8s/namespace.yaml)

Deploy:

kubectl apply -f k8s/namespace.yaml

### Ingress/Ingress.yaml

```
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: togglemaster-ingress
  namespace: toggle-prod
  annotations:
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  rules:
    - http:
        paths:
          - path: /auth(/|$)(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: auth-service
                port:
                  number: 8001
          - path: /flags(/|$)(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: flag-service
                port:
                  number: 8002
          - path: /targeting(/|$)(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: targeting-service
                port:
                  number: 8003
          - path: /evaluation(/|$)(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: evaluation-service
                port:
                  number: 8004
          - path: /analytics(/|$)(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: analytics-service
                port:
                  number: 8005
```

[ingress.yaml](k8s/ingress/ingress.yaml)

#### Deploy:

![image-20260712132854747](./img/image-20260712132854747.png)

![image-20260712132908679](./img/image-20260712132908679.png)

### cluster-autoscaler.yaml

```
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    deployment.kubernetes.io/revision: "1"
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"apps/v1","kind":"Deployment","metadata":{"annotations":{},"labels":{"app":"cluster-autoscaler"},"name":"cluster-autoscaler","namespace":"kube-system"},"spec":{"replicas":1,"selector":{"matchLabels":{"app":"cluster-autoscaler"}},"template":{"metadata":{"annotations":{"prometheus.io/port":"8085","prometheus.io/scrape":"true"},"labels":{"app":"cluster-autoscaler"}},"spec":{"containers":[{"command":["./cluster-autoscaler","--v=4","--stderrthreshold=info","--cloud-provider=aws","--skip-nodes-with-local-storage=false","--expander=least-waste","--node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/feature-flags-cluster","--balance-similar-node-groups","--skip-nodes-with-system-pods=false"],"image":"registry.k8s.io/autoscaling/cluster-autoscaler:v1.28.2","imagePullPolicy":"Always","name":"cluster-autoscaler","resources":{"limits":{"cpu":"100m","memory":"600Mi"},"requests":{"cpu":"100m","memory":"600Mi"}},"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true},"volumeMounts":[{"mountPath":"/etc/ssl/certs/ca-certificates.crt","name":"ssl-certs","readOnly":true}]}],"nodeSelector":{"kubernetes.io/os":"linux"},"priorityClassName":"system-cluster-critical","securityContext":{"fsGroup":65534,"runAsNonRoot":true,"runAsUser":65534,"seccompProfile":{"type":"RuntimeDefault"}},"serviceAccountName":"cluster-autoscaler","volumes":[{"hostPath":{"path":"/etc/ssl/certs/ca-bundle.crt"},"name":"ssl-certs"}]}}}}
  creationTimestamp: "2026-07-11T17:27:00Z"
  generation: 1
  labels:
    app: cluster-autoscaler
  name: cluster-autoscaler
  namespace: kube-system
  resourceVersion: "2784060"
  uid: a170d36d-254a-432b-a5f4-1c3bbecdf87b
spec:
  progressDeadlineSeconds: 600
  replicas: 1
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      app: cluster-autoscaler
  strategy:
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 25%
    type: RollingUpdate
  template:
    metadata:
      annotations:
        prometheus.io/port: "8085"
        prometheus.io/scrape: "true"
      labels:
        app: cluster-autoscaler
    spec:
      containers:
      - command:
        - ./cluster-autoscaler
        - --v=4
        - --stderrthreshold=info
        - --cloud-provider=aws
        - --skip-nodes-with-local-storage=false
        - --expander=least-waste
        - --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/feature-flags-cluster
        - --balance-similar-node-groups
        - --skip-nodes-with-system-pods=false
        image: registry.k8s.io/autoscaling/cluster-autoscaler:v1.28.2
        imagePullPolicy: Always
        name: cluster-autoscaler
        resources:
          limits:
            cpu: 100m
            memory: 512Mi
          requests:
            cpu: 100m
            memory: 256Mi
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
          readOnlyRootFilesystem: true
        terminationMessagePath: /dev/termination-log
        terminationMessagePolicy: File
        volumeMounts:
        - mountPath: /etc/ssl/certs/ca-certificates.crt
          name: ssl-certs
          readOnly: true
      dnsPolicy: ClusterFirst
      nodeSelector:
        kubernetes.io/os: linux
      priorityClassName: system-cluster-critical
      restartPolicy: Always
      schedulerName: default-scheduler
      securityContext:
        fsGroup: 65534
        runAsNonRoot: true
        runAsUser: 65534
        seccompProfile:
          type: RuntimeDefault
      serviceAccount: cluster-autoscaler
      serviceAccountName: cluster-autoscaler
      terminationGracePeriodSeconds: 30
      volumes:
      - hostPath:
          path: /etc/ssl/certs/ca-bundle.crt
          type: ""
        name: ssl-certs
status:
  conditions:
  - lastTransitionTime: "2026-07-11T17:27:00Z"
    lastUpdateTime: "2026-07-11T17:27:00Z"
    message: Deployment does not have minimum availability.
    reason: MinimumReplicasUnavailable
    status: "False"
    type: Available
  - lastTransitionTime: "2026-07-11T17:37:01Z"
    lastUpdateTime: "2026-07-11T17:37:01Z"
    message: ReplicaSet "cluster-autoscaler-555d4dbcb7" has timed out progressing.
    reason: ProgressDeadlineExceeded
    status: "False"
    type: Progressing
  observedGeneration: 1
  replicas: 1
  terminatingReplicas: 0
  unavailableReplicas: 1
  updatedReplicas: 1
```

[cluster-autoscaler.yaml](k8s/cluster-autoscaler.yaml)

### Auth-Service

[Auth-Service](k8s/auth-service/)

#### Configmap.yaml

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: auth-config
  namespace: toggle-prod
data:
  PORT: "8001"
```

#### Deployment.yaml

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-service
  namespace: toggle-prod
spec:
  replicas: 1
  selector:
    matchLabels:
      app: auth-service
  template:
    metadata:
      labels:
        app: auth-service
    spec:
      containers:
        - name: auth-service
          image: 708993007071.dkr.ecr.us-east-1.amazonaws.com/auth-service:latest
          imagePullPolicy: Always
          ports:
            - containerPort: 8001
          envFrom:
            - configMapRef:
                name: auth-config
            - secretRef:
                name: auth-secret
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "250m"
              memory: "256Mi"
          readinessProbe:
            httpGet:
              path: /health
              port: 8001
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /health
              port: 8001
            initialDelaySeconds: 30
            periodSeconds: 10
```

#### secret.yaml

```
apiVersion: v1
kind: Secret
metadata:
  name: auth-secret
  namespace: toggle-prod
type: Opaque
data:
  DATABASE_URL: cG9zdGdyZXM6Ly9wb3N0Z3JlczpTZW5oYUZvcnRlMTIzIUBhdXRoLWRiLmNzNWF5aXFpbzVhYS51cy1lYXN0LTEucmRzLmFtYXpvbmF3cy5jb206NTQzMi9hdXRoLWRiP3NzbG1vZGU9cmVxdWlyZQ==
  MASTER_KEY: YWRtaW4tc2VjcmV0by0xMjM=
```

#### service.yaml

```
apiVersion: v1
kind: Service
metadata:
  name: auth-service
  namespace: toggle-prod
spec:
  type: ClusterIP
  selector:
    app: auth-service
  ports:
    - port: 8001
      targetPort: 8001
      protocol: TCP
```

Deploy:

```
kubectl apply -f k8s/auth-service/configmap.yaml
kubectl apply -f k8s/auth-service/secret.yaml
kubectl apply -f k8s/auth-service/service.yaml
kubectl apply -f k8s/auth-service/deployment.yaml
```

![image-20260712133839400](./img/image-20260712133839400.png)

Teste realizado:

![image-20260712133906470](./img/image-20260712133906470.png)

### Flag-Service

[Flag-Service](k8s/flag-service/)

#### Configmap.yaml

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: flag-config
  namespace: toggle-prod
data:
  PORT: "8002"
  AUTH_SERVICE_URL: http://auth-service:8001
```

#### Deployment.yaml

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flag-service
  namespace: toggle-prod
spec:
  replicas: 1
  selector:
    matchLabels:
      app: flag-service
  template:
    metadata:
      labels:
        app: flag-service
    spec:
      containers:
        - name: flag-service
          image: 708993007071.dkr.ecr.us-east-1.amazonaws.com/flag-service:latest
          imagePullPolicy: Always
          ports:
            - containerPort: 8002
          envFrom:
            - configMapRef:
                name: flag-config
            - secretRef:
                name: flag-secret
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "250m"
              memory: "256Mi"
          readinessProbe:
            httpGet:
              path: /health
              port: 8002
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /health
              port: 8002
            initialDelaySeconds: 30
            periodSeconds: 10
```

#### secret.yaml

```
apiVersion: v1
kind: Secret
metadata:
  name: flag-secret
  namespace: toggle-prod
type: Opaque
data:
  DATABASE_URL: 
```

#### service.yaml

```
apiVersion: v1
kind: Secret
metadata:
  name: flag-secret
  namespace: toggle-prod
type: Opaque
data:
  DATABASE_URL: 
```

Deploy:

```
kubectl apply -f k8s/flag-service/flag-configmap.yaml
kubectl apply -f k8s/flag-service/flag-secret.yaml
kubectl apply -f k8s/flag-service/flag-service.yaml
kubectl apply -f k8s/flag-service/flag-deployment.yaml
```

![image-20260712134655600](./img/image-20260712134655600.png)

Teste:

![image-20260712134712851](./img/image-20260712134712851.png)

![image-20260712134737136](./img/image-20260712134737136.png)

### **Targeting-Service**

[Targeting-Service](k8s/targeting-service/)

#### Configmap.yaml

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: evaluation-config
  namespace: toggle-prod
data:
  PORT: "8004"
  REDIS_URL: "redis://evaluation-service-redis.yumvds.0001.use1.cache.amazonaws.com:6379"
  FLAG_SERVICE_URL: "http://flag-service:8002"
  TARGETING_SERVICE_URL: "http://targeting-service:8003"
  AWS_REGION: "us-east-1"
```

#### Deployment.yaml

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: targeting-service
  namespace: toggle-prod
spec:
  replicas: 1
  selector:
    matchLabels:
      app: targeting-service
  template:
    metadata:
      labels:
        app: targeting-service
    spec:
      containers:
        - name: targeting-service
          image: 708993007071.dkr.ecr.us-east-1.amazonaws.com/targeting-service:latest
          imagePullPolicy: Always
          ports:
            - containerPort: 8003
          envFrom:
            - configMapRef:
                name: targeting-config
            - secretRef:
                name: targeting-secret
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "250m"
              memory: "256Mi"
          readinessProbe:
            httpGet:
              path: /health
              port: 8003
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /health
              port: 8003
            initialDelaySeconds: 30
            periodSeconds: 10
```

#### secret.yaml

```
apiVersion: v1
kind: Secret
metadata:
  name: tar-secret
  namespace: toggle-prod
type: Opaque
data:
  DATABASE_URL: 
```

#### service.yaml

```
apiVersion: v1
kind: Service
metadata:
  name: targeting-service
  namespace: toggle-prod
spec:
  type: ClusterIP
  selector:
    app: targeting-service
  ports:
    - port: 8003
      targetPort: 8003
      protocol: TCP
```

Deploy:

```
kubectl apply -f k8s/targeting-service/configmap.yaml
kubectl apply -f k8s/targeting-service/secret.yaml
kubectl apply -f k8s/targeting-service/service.yaml
kubectl apply -f k8s/targeting-service/deployment.yaml
```

Teste:

![image-20260712134851098](./img/image-20260712134851098.png)

### Evaluation-Service

[Evaluation-Service](k8s/evaluation-service/)

#### Configmap.yaml

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: evaluation-config
  namespace: toggle-prod
data:
  PORT: "8004"
  REDIS_URL: "redis://evaluation-service-redis.yumvds.0001.use1.cache.amazonaws.com:6379"
  FLAG_SERVICE_URL: "http://flag-service:8002"
  TARGETING_SERVICE_URL: "http://targeting-service:8003"
  AWS_REGION: "us-east-1"
```

#### Deployment.yaml

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: evaluation-service
  namespace: toggle-prod
spec:
  replicas: 1
  selector:
    matchLabels:
      app: evaluation-service
  template:
    metadata:
      labels:
        app: evaluation-service
    spec:
      containers:
        - name: evaluation-service
          image: 708993007071.dkr.ecr.us-east-1.amazonaws.com/evaluation-service:latest
          imagePullPolicy: Always
          ports:
            - containerPort: 8004
          envFrom:
            - configMapRef:
                name: evaluation-config
            - secretRef:
                name: evaluation-secret
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "250m"
              memory: "256Mi"
          readinessProbe:
            httpGet:
              path: /health
              port: 8004
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /health
              port: 8004
            initialDelaySeconds: 30
            periodSeconds: 10
```

#### secret.yaml

```
apiVersion: v1
kind: Secret
metadata:
  name: evaluation-secret
  namespace: toggle-prod
type: Opaque
data:
  SERVICE_API_KEY: 
  AWS_ACCESS_KEY_ID: 
  AWS_SECRET_ACCESS_KEY: 
  AWS_SQS_URL: 
```

#### service.yaml

```
apiVersion: v1
kind: Service
metadata:
  name: evaluation-service
  namespace: toggle-prod
spec:
  type: ClusterIP
  selector:
    app: evaluation-service
  ports:
    - port: 8004
      targetPort: 8004
      protocol: TCP
```

#### hpa.yaml

```
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: evaluation-service-hpa
  namespace: toggle-prod
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: evaluation-service
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
```

#### Deploy:

```
kubectl apply -f k8s/evaluation-service/configmap.yaml
kubectl apply -f k8s/evaluation-service/secret.yaml
kubectl apply -f k8s/evaluation-service/service.yaml
kubectl apply -f k8s/evaluation-service/deployment.yaml
kubectl apply -f k8s/evaluation-service/hpa.yaml
```

#### Teste:

Rodando o teste:

![image-20260712135014583](./img/image-20260712135014583.png)

Analisando o log:

![image-20260712135036920](./img/image-20260712135036920.png)

Dados no sqs:

![image-20260712135112436](./img/image-20260712135112436.png)

![image-20260712135132864](./img/image-20260712135132864.png)

### **Analytics-Service**

[Analytics-Service](k8s/analytics-service/)

#### Configmap.yaml

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: analytics-config
  namespace: toggle-prod
data:
  AWS_DYNAMODB_TABLE: "ToggleMasterAnalytics"
  AWS_REGION: "us-east-1"
  AWS_SQS_URL: "https://sqs.us-east-1.amazonaws.com/708993007071/evaluation-analytics-queue"
```

#### Deployment.yaml

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: analytics-service
  namespace: toggle-prod
spec:
  replicas: 1
  selector:
    matchLabels:
      app: analytics-service
  template:
    metadata:
      labels:
        app: analytics-service
    spec:
      containers:
        - name: analytics-service
          image: 708993007071.dkr.ecr.us-east-1.amazonaws.com/analytics-service:latest
          imagePullPolicy: Always
          ports:
            - containerPort: 8005
          envFrom:
            - configMapRef:
                name: analytics-config
            - secretRef:
                name: analytics-secret
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "250m"
              memory: "256Mi"
          readinessProbe:
            httpGet:
              path: /health
              port: 8005
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /health
              port: 8005
            initialDelaySeconds: 30
            periodSeconds: 10
```

#### secret.yaml

```
apiVersion: v1
kind: Secret
metadata:
  name: evaluation-secret
  namespace: toggle-prod
type: Opaque
data:
  AWS_ACCESS_KEY_ID: 
  AWS_SECRET_ACCESS_KEY: 
```

#### service.yaml

```
apiVersion: v1
kind: Service
metadata:
  name: analytics-service
  namespace: toggle-prod
spec:
  type: ClusterIP
  selector:
    app: analytics-service
  ports:
    - port: 8005
      targetPort: 8005
      protocol: TCP
```

#### keda.yaml

```
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: analytics-aws-auth
  namespace: toggle-prod
spec:
  secretTargetRef:
  - parameter: awsAccessKeyID
    name: analytics-secret
    key: AWS_ACCESS_KEY_ID
  - parameter: awsSecretAccessKey
    name: analytics-secret
    key: AWS_SECRET_ACCESS_KEY
```

#### scaledobject.yaml

```
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: analytics-sqs-scaler
  namespace: toggle-prod
spec:
  scaleTargetRef:
    name: analytics-service
  minReplicaCount: 1
  maxReplicaCount: 5
  pollingInterval: 15
  cooldownPeriod: 60
  triggers:
  - type: aws-sqs-queue
    metadata:
      queueURL: https://sqs.us-east-1.amazonaws.com/708993007071/evaluation-analytics-queue
      queueLength: "5"
      awsRegion: us-east-1
    authenticationRef:
      name: analytics-aws-auth
```

Deploy:

```
kubectl apply -f k8s/analytics-service/configmap.yaml
kubectl apply -f k8s/analytics-service/secret.yaml
kubectl apply -f k8s/analytics-service/service.yaml
kubectl apply -f k8s/analytics-service/deployment.yaml
kubectl apply -f k8s/analytics-service/keda-auth.yaml
kubectl apply -f k8s/analytics-service/scaledobject.yaml
```

Teste:

Logs do Processamento ao rodar o teste automatico.

![image-20260712135409200](./img/image-20260712135409200.png)

Dados da tabela:

![image-20260712135436864](./img/image-20260712135436864.png)



### Testes da Aplicação no Cloud e Escalabilidade

#### Status do Ambiente:

##### Pods Ativos

![image-20260712151736796](./img/image-20260712151736796.png)

##### Nodes ativos

![image-20260712151831577](./img/image-20260712151831577.png)

#### Script de Teste

Para os testes foi usado um script em Bash, tanto para os microserviços quanto para a carga.

[test2.sh](test2.sh)

```
#!/bin/bash

########################################
# CONFIGURAÇÃO
########################################

BASE_URL_AUTH=${BASE_URL_AUTH:-http://acc28ae7dcc21487e87cdd1a2bbeb3d2-106617744.us-east-1.elb.amazonaws.com/auth}
BASE_URL_FLAG=${BASE_URL_FLAG:-http://acc28ae7dcc21487e87cdd1a2bbeb3d2-106617744.us-east-1.elb.amazonaws.com/flags}
BASE_URL_TARGETING=${BASE_URL_TARGETING:-http://acc28ae7dcc21487e87cdd1a2bbeb3d2-106617744.us-east-1.elb.amazonaws.com/targeting}
BASE_URL_EVALUATION=${BASE_URL_EVALUATION:-http://acc28ae7dcc21487e87cdd1a2bbeb3d2-106617744.us-east-1.elb.amazonaws.com/evaluation}
BASE_URL_ANALYTICS=${BASE_URL_ANALYTICS:-http://acc28ae7dcc21487e87cdd1a2bbeb3d2-106617744.us-east-1.elb.amazonaws.com/analytics}

MASTER_KEY=${MASTER_KEY:-admin-secreto-123}

FLAG_NAME="enable-new-dashboard-$(date +%s)"

USER_NAME1="user-$(date +%s)"
sleep 2
USER_NAME2="user-$(date +%s)"

echo ""
echo "========================================"
echo "AMBIENTE DE TESTE"
echo "========================================"
echo "AUTH      : $BASE_URL_AUTH"
echo "FLAG      : $BASE_URL_FLAG"
echo "TARGETING : $BASE_URL_TARGETING"
echo "EVALUATION : $BASE_URL_EVALUATION"
echo "ANALYTICS : $BASE_URL_ANALYTICS"

echo ""

########################################
# HEALTH CHECK
########################################

echo "========================================"
echo "1. Health Check"
echo "========================================"

curl "$BASE_URL_AUTH/health"
echo
echo


curl "$BASE_URL_FLAG/health"
echo
echo


curl "$BASE_URL_TARGETING/health"
echo
echo

curl "$BASE_URL_EVALUATION/health"
echo
echo

curl "$BASE_URL_ANALYTICS/health"
echo
echo

########################################
# CRIAR API KEY
########################################

echo ""
echo "========================================"
echo "2. Criando API Key"
echo "========================================"

HTTP_CODE=$(curl -s -o response.json -w "%{http_code}" \
-X POST "$BASE_URL_AUTH/admin/keys" \
-H "Content-Type: application/json" \
-H "Authorization: Bearer admin-secreto-123" \
-d '{"name":"teste-automacao"}')

if [ "$HTTP_CODE" != "201" ]; then
    echo "ERRO ao criar API Key (HTTP $HTTP_CODE)"
    cat response.json
    exit 1
fi

API_KEY=$(grep -o '"key":"[^"]*' response.json | cut -d'"' -f4)

echo "API KEY:"
echo "$API_KEY"
echo ""
echo ""


########################################
# CRIAR FLAG
########################################

echo "========================================"
echo "3. Criando Flag"
echo "========================================"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
-X POST "$BASE_URL_FLAG/flags" \
-H "Content-Type: application/json" \
-H "Authorization: Bearer $API_KEY" \
-d "{
    \"name\":\"$FLAG_NAME\",
    \"description\":\"Teste automatizado\",
    \"is_enabled\":true
}")

if [ "$HTTP_CODE" != "201" ]; then
    echo "ERRO ao criar Flag (HTTP $HTTP_CODE)"
    cat response.json
    exit 1
fi
cat response.json

echo ""
echo ""


echo "========================================"
echo "4. Listando Flags"
echo "========================================"

HTTP_CODE=$(curl -s -o response.json -w "%{http_code}" \
-H "Authorization: Bearer $API_KEY" \
"$BASE_URL_FLAG/flags")

if [ "$HTTP_CODE" != "200" ]; then
    echo "ERRO ao listar flags (HTTP $HTTP_CODE)"
    cat response.json
    exit 1
fi

echo "Flags encontradas:"
grep -o '"name":"[^"]*"' response.json | cut -d'"' -f4

echo ""
echo ""

echo "========================================"
echo "5. Consultando Flag"
echo "========================================"

HTTP_CODE=$(curl -s -o response.json -w "%{http_code}" \
"$BASE_URL_FLAG/flags/$FLAG_NAME" \
-H "Authorization: Bearer $API_KEY")

if [ "$HTTP_CODE" != "200" ]; then
    echo "ERRO ao consultar flag (HTTP $HTTP_CODE)"
    cat response.json
    exit 1
fi
cat response.json

echo ""
echo ""

echo "========================================"
echo "6. Atualizando Flag"
echo "========================================"

HTTP_CODE=$(curl -s -o response.json -w "%{http_code}" \
-X PUT "$BASE_URL_FLAG/flags/$FLAG_NAME" \
-H "Content-Type: application/json" \
-H "Authorization: Bearer $API_KEY" \
-d '{
  "is_enabled": false
}')

if [ "$HTTP_CODE" != "200" ]; then
    echo "ERRO ao atualizar flag (HTTP $HTTP_CODE)"
    cat response.json
    exit 1
fi

cat response.json

echo ""
echo "========================================"
echo "7. Criando Regra de Targeting"
echo "========================================"

HTTP_CODE=$(curl -s -o response.json -w "%{http_code}" \
-X POST "$BASE_URL_TARGETING/rules" \
-H "Content-Type: application/json" \
-H "Authorization: Bearer $API_KEY" \
-d "{
  \"flag_name\":\"$FLAG_NAME\",
  \"is_enabled\":true,
  \"rules\":{
      \"type\":\"PERCENTAGE\",
      \"value\":50
  }
}")

if [ "$HTTP_CODE" != "201" ]; then
    echo "ERRO ao criar regra (HTTP $HTTP_CODE)"
    cat response.json
    exit 1
fi

cat response.json

echo ""
echo ""

echo "========================================"
echo "8. Consultando Regra"
echo "========================================"

HTTP_CODE=$(curl -s -o response.json -w "%{http_code}" \
"$BASE_URL_TARGETING/rules/$FLAG_NAME" \
-H "Authorization: Bearer $API_KEY")

if [ "$HTTP_CODE" != "200" ]; then
    echo "ERRO ao consultar regra (HTTP $HTTP_CODE)"
    cat response.json
    exit 1
fi
cat response.json

echo ""
echo ""

echo "========================================"
echo "9. Atualizando Regra"
echo "========================================"

HTTP_CODE=$(curl -s -o response.json -w "%{http_code}" \
-X PUT "$BASE_URL_TARGETING/rules/$FLAG_NAME" \
-H "Content-Type: application/json" \
-H "Authorization: Bearer $API_KEY" \
-d '{
  "rules":{
      "type":"PERCENTAGE",
      "value":75
  }
}')

if [ "$HTTP_CODE" != "200" ]; then
    echo "ERRO ao atualizar regra (HTTP $HTTP_CODE)"
    exit 1
fi

cat response.json

echo ""
echo ""

echo "========================================"
echo "10. Testando a fila SQS e o processamento"
echo "========================================"

echo "user 1 - $USER_NAME1"

for i in 1 2
do
  echo "=== Request $i ==="

  HTTP_CODE=$(curl -s -o response.json -w "%{http_code}" \
    "$BASE_URL_EVALUATION/evaluate?user_id=$USER_NAME1&flag_name=$FLAG_NAME" \
    )

  if [ "$HTTP_CODE" != "200" ]; then
      echo "ERRO na tentativa $i (HTTP $HTTP_CODE)"
      cat response.json
      exit 1
  fi
  cat response.json

  echo -e "\n"
done

echo ""
echo ""

echo "user 2 - $USER_NAME2"

for i in 1 2
do
  echo "=== Request $i ==="

  HTTP_CODE=$(curl -s -o response.json -w "%{http_code}" \
    "$BASE_URL_EVALUATION/evaluate?user_id=$USER_NAME2&flag_name=enable-new-dashboard-1780855960" \
    )


  if [ "$HTTP_CODE" != "200" ]; then
      echo "ERRO na tentativa $i (HTTP $HTTP_CODE)"
      cat response.json
      exit 1
  fi
  cat response.json

  echo -e "\n"
done

echo ""
echo ""

echo "========================================"
echo "11. Teste de Carga"
echo "========================================"

for i in $(seq 1 1000)
do
  (
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
      "$BASE_URL_EVALUATION/evaluate?user_id=user-$i&flag_name=enable-new-dashboard-1783784225"
    )

    if [ "$HTTP_CODE" != "200" ]; then
        echo "ERRO na tentativa $i (HTTP $HTTP_CODE)"
    else
        echo "Request $i OK"
    fi
  ) &

  # limita concorrência
  if (( i % 50 == 0 )); then
      wait
  fi
done

wait

echo ""
echo "Teste de carga finalizado"

echo "========================================"
echo "12. Deletando Flag"
echo "========================================"

echo "FLAG_NAME=$FLAG_NAME"

HTTP_CODE=$(curl -s -o response.json -w "%{http_code}" \
-X DELETE \
"$BASE_URL_FLAG/flags/$FLAG_NAME" \
-H "Authorization: Bearer $API_KEY")

if [ "$HTTP_CODE" != "204" ]; then
    echo "ERRO ao deletar flag (HTTP $HTTP_CODE)"
    exit 1
fi

echo "Flag removida com sucesso."

echo ""
echo ""
echo "TESTE FINALIZADO COM SUCESSO"
```

Resultados do Teste sem a etapa de carga:

![image-20260712144551447](./img/image-20260712144551447.png)

![image-20260712144616010](./img/image-20260712144616010.png)

Validando o processamento do evaluation:

kubectl logs deployment/evaluation-service -n toggle-prod

![image-20260712144918502](./img/image-20260712144918502.png)

Validando o processamento dentro do Analytics:

kubectl logs deployment/analytics-service -n toggle-prod

![image-20260712145030465](./img/image-20260712145030465.png)

#### Testes de Escalabilidade:

##### Preparação

Desativamos o pod do Analytics para que acumule fila no sqs e escale ao iniciar.

```
kubectl scale deployment analytics-service \
-n toggle-prod \
--replicas=0
```

##### Estado inicial:

![image-20260712135959720](./img/image-20260712135959720.png)

Rodamos o test2.sh com a etapa de carga

##### Resultados e Monitoramento

watch kubectl get pods -n toggle-prod -o wide

![image-20260712140027189](./img/image-20260712140027189.png)

watch kubectl get nodes

![image-20260712140045515](./img/image-20260712140045515.png)

watch kubectl get hpa -n toggle-prod

![image-20260712140112711](./img/image-20260712140112711.png)

## 7 Arquitetura e Desafios Encontrados

### 7.1 Criação das Imagens

Para os dockerfiles foi necessário criar com 2 estágios de forma a diminuir o tamanho para os serviços em Python e fazer a compilação para os desenvolvidos em Golang.

| Serviço            | Stage Único | Multistage |
| :----------------- | :---------- | :--------- |
| auth-service       | 30 MB       | 30 MB      |
| evaluation-service | 36 MB       | 36 MB      |
| flag-service       | 541 MB      | **210 MB** |
| targeting-service  | 529 MB      | **210 MB** |
| analytics-service  | 747 MB      | **248 MB** |

Com redução do tamanho das imagens Python de 60%.

### 7.2 Escalabilidade do Cluster

Identificamos uma limitação no node t3.micro usado no free tier de apenas 4 pods/node. O limite de pods por nó imposto pelo VPC CNI utilizado no EKS.

Dessa forma, foi necessário deixar as aplicações com apenas 1 replica e apenas o Analytics e o Evaluation com a escalabilidade para até 5 pods.

E aumentar a quantidade e escalabilidade do Auto Scaling Group para: 

- Minimo: 6
- Desejável: 8
- Máximo:12

Foi necessária a implantação manual do Cluster Autoscaler utilizando IAM Roles for Service Accounts (IRSA).

Durante os testes foram encontrados alguns problemas:

- o autoscaler não conseguia ser agendado por solicitar memória excessiva;
- foi necessário reduzir os recursos do próprio Deployment do Cluster Autoscaler;

Após o ajuste o Cluster Autoscaler passou a criar automaticamente novos nós quando os pods não conseguiam ser agendados.

### 7.3 Ajuste dos Requests e Limits

Inicialmente os microserviços utilizavam requests e limits relativamente altos, fazendo com que os nós aparentassem estar sem memória disponível.

Após análise foi possível reduzir significativamente os recursos reservados:

```
requests:
  cpu: 50m
  memory: 64Mi

limits:
  cpu: 250m
  memory: 256Mi
```

Essa alteração permitiu melhor utilização dos nós e maior densidade de pods.

### 7.4 Redes, SG e Subnets

Os Bancos RDS e Redis precisaram estar dentro da mesma VPC, com conexão via Security group para acesso interno.

### 7.5 Configuração dos Bancos e Tabelas

Por ser free tier, houve uma limitação de apenas 2 RDS Postgres.

Foram criados apenas 2 RDS, devido à limitação de quota da conta AWS (máximo de instâncias RDS permitidas), e o banco do **targeting-service** foi criado como um banco separado dentro da instância **flag-db**.

RDS: auth-db

- banco auth-db;

RDS: flag-db

- banco flag-db
- banco targeting-db 

Para a criação dos bancos e tabelas, subimos um pod temporário postgres-client dentro do cluster e usamos para acessar os bancos postgres dentro do cluster:

```
 kubectl run postgres-client \
  --image=postgres:18 \
  -n toggle-prod \
  --rm -it \
  -- bash

E dentro do terminal do pod, acessar os bancos via psql:

psql \
-h auth-db.cs5ayiqio5aa.us-east-1.rds.amazonaws.com \
-U postgres \
-d postgres \
-p 5432
```

### 7.6 Ingress

Foi utilizado o NGINX Ingress Controller para centralizar o acesso às APIs.

Toda a comunicação externa ocorre através de um único endpoint, que distribui as requisições para os respectivos serviços internos conforme as rotas configuradas.

Foi definido apenas um namespace para os 5 microserviçoes de forma a simplificar a configração do ingress, e ter apenas um ingress.yaml e uma url para as API's

### 7.7 Arquitetura

<img width="1086" height="873" alt="image" src="https://github.com/user-attachments/assets/0fc3f7f8-fffd-4c32-9e7c-5355ab70daff" />



## 8 Diferença de Bancos

PostgreSQL (RDS) usado nos serviços que precisam de dados críticos e relacionais (auth, flag, targeting).

Redis (ElastiCache) usado no serviço que precisa de velocidade máxima (evaluation).

SQS + DynamoDB usados no serviço que precisa lidar com grande volume de eventos e escalar horizontalmente (analytics).

**Justificativa por serviço**

**auth-service → RDS PostgreSQL (auth-db)**

  Precisa armazenar usuários, credenciais e chaves de API.
  
  Esses dados são críticos e relacionais (usuário ↔ chave ↔ permissões).
  
  O PostgreSQL garante consistência forte (ACID), ideal para autenticação.

**flag-service → RDS PostgreSQL (flag-db)**

  Gerencia feature flags (ativadas/desativadas).
  
  Flags podem ter relacionamentos complexos (ex.: flag ligada a um produto ou versão).
  
  O modelo relacional facilita consultas e garante integridade.

**targeting-service → RDS PostgreSQL (targeting-db)**

  Define regras de segmentação (ex.: “usuários do Brasil recebem a flag X”).
  
  Essas regras são estruturadas e relacionais, exigindo consistência.
  
  PostgreSQL é ideal para armazenar e consultar regras com filtros complexos.

**evaluation-service → ElastiCache Redis**

  Precisa responder muito rápido se uma flag está ativa ou não.
  
  Redis guarda dados em memória, com latência baixíssima.
  
  Não é usado para persistência, mas sim como cache para decisões instantâneas.

**analytics-service → Amazon SQS + DynamoDB**
  Recebe eventos massivos (ex.: quantas vezes uma flag foi avaliada).
  
  O SQS desacopla produtores e consumidores, garantindo que nenhum evento se perca.
  
  O DynamoDB armazena milhões de registros de forma escalável e distribuída, ideal para análises.



## 9 Vídeo de Apresentação
https://youtu.be/oh_k-U3Ucrc?si=cC_PCK49gd3XZ-vo
