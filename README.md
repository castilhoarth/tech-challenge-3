# Resumo do Projeto

## Microsserviços identificados

- Auth Service
  - Nome: auth
  - Linguagem: Go
  - Caminho no repositório: services/auth-service-main
  - Possui Dockerfile: Sim
  - Testes unitários: Não possuem

- Flag Service
  - Nome: flag
  - Linguagem: Python
  - Caminho no repositório: services/flag-service-main
  - Possui Dockerfile: Sim
  - Testes unitários: Não possuem

- Targeting Service
  - Nome: targeting
  - Linguagem: Go
  - Caminho no repositório: services/targeting-service-main
  - Possui Dockerfile: Sim
  - Testes unitários: Não possuem

- Evaluation Service
  - Nome: evaluation
  - Linguagem: Go
  - Caminho no repositório: services/evaluation-service-main
  - Possui Dockerfile: Sim
  - Testes unitários: Não possuem

- Analytics Service
  - Nome: analytics
  - Linguagem: Python
  - Caminho no repositório: services/analytics-service-main
  - Possui Dockerfile: Sim
  - Testes unitários: Não possuem

## Estrutura do repositório

- Modelo: Monorepo
- Repositório raiz: tech-challenge-3

## Infraestrutura e deployment

- Região AWS utilizada: us-east-1
- Repositórios ECR: a criar
- Secrets necessários no GitHub Actions: a definir, com base nos segredos de acesso AWS e registro ECR necessários para o pipeline de build/deploy

## Decisões definidas

Modelo de workflow
Escolha: workflow reutilizável, com parâmetros por serviço.
Motivo: centraliza a regra do pipeline e mantém a implementação escalável.

Padrão de nome da imagem Docker
Usar o nome do serviço em letras minúsculas e hífen, por exemplo:
auth-service
flag-service
evaluation-service
O nome deve ser consistente com os repositórios ECR e com os deployments do Kubernetes.
Padrão de tag da imagem
Usar sha-<shortsha> para cada build.
Exemplo: sha-a1b2c3d
Opcionalmente, manter latest apenas para builds da branch principal.
Trigger por mudanças em pastas específicas
Sim, o pipeline deve rodar apenas quando houver alterações relevantes.
Exemplos de gatilho:
services/auth-service-main/**
services/flag-service-main/**
services/evaluation-service-main/**
services/targeting-service-main/**
services/analytics-service-main/**
arquivos compartilhados como docker-compose, k8s/** e o próprio workflow
Ordem dos jobs
build

test

lint

security-scan

docker-build

container-scan

push-ecr

Importante: o push para ECR deve ocorrer somente se todos os passos anteriores passarem e a execução for válida para a branch de destino.