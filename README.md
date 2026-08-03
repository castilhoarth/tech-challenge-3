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
