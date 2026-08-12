# Service Relationship Flow

```mermaid
flowchart TD
    Client[Client / API Consumer] --> Auth[auth-service]
    Client --> Eval[evaluation-service]

    Auth --> AuthDB[(PostgreSQL - auth DB)]

    Flag[flag-service] --> FlagDB[(PostgreSQL - flags DB)]
    Targeting[targeting-service] --> TargetingDB[(PostgreSQL - targeting DB)]

    Flag --> Auth
    Targeting --> Auth

    Eval --> Flag
    Eval --> Targeting
    Eval --> Redis[(Redis Cache)]

    Eval --> SQS[(AWS SQS)]
    Analytics[analytics-service] --> SQS
    Analytics --> DynamoDB[(AWS DynamoDB)]

    classDef svc fill:#e8f0fe,stroke:#1a73e8,color:#0b57d0;
    class Auth,Flag,Targeting,Eval,Analytics svc;
```

## CI/CD Pipeline Flow

```mermaid
flowchart TD
    A[Push or pull request affecting service paths] --> B{Which service workflow?}
    B --> C[ci-analytics.yml]
    B --> D[ci-auth.yml]
    B --> E[ci-evaluation.yml]
    B --> F[ci-flag.yml]
    B --> G[ci-targeting.yml]

    C --> H[Reusable CI workflow]
    D --> H
    E --> H
    F --> H
    G --> H

    H --> I[Prepare: checkout, set context and image tag]
    I --> J1[Setup language environment & dependencies]
    J1 --> J2[Security static analysis / linting]
    J2 --> J3{Unit tests pass?}
    
    J3 -->|No| R[Fail Pipeline]
    J3 -->|Yes| K[Build Docker image]
    
    K --> L[Trivy container scan]
    L --> M{Push enabled?}
    M -->|Yes| N[Configure AWS credentials]
    N --> O[Login to Amazon ECR]
    O --> P[Tag and push image]
    M -->|No| Q[Pipeline ends]
    P --> Q

    classDef step fill:#f3e8ff,stroke:#8b5cf6,color:#6d28d9;
    classDef fail fill:#fee2e2,stroke:#ef4444,color:#991b1b;
    class H,I,J1,J2,K,L,N,O,P,Q step;
    class R fail;
```

```mermaid
graph TD
    %% Estilos de Subgrafos
    classDef repoStyle fill:#f9f9f9,stroke:#333,stroke-width:2px,stroke-dasharray: 5 5;
    classDef infraStyle fill:#e6f3ff,stroke:#0066cc,stroke-width:2px;
    classDef clusterStyle fill:#f2e6ff,stroke:#6600cc,stroke-width:2px;

    %% Ação do Desenvolvedor
    Dev[🧑‍💻 Desenvolvedor] -->|1. Git Push Código| RepoApp

    %% Fluxo do Aplicativo
    subgraph RepoApp [📦 REPO 1: Aplicativo & CI]
        direction TB
        Code[Código Fonte Python/Node]
        CI[⚙️ Pipeline de CI <br> GitHub Actions / GitLab CI]
        Code --> CI
    end
    class RepoApp repoStyle;

    %% Execução do CI
    CI -->|2. Roda Testes & <br> Constrói Imagem Docker| CI
    CI -->|3. Docker Push| Registry[(🐳 Registro Imagem <br> AWS ECR / Docker Hub)]
    CI -->|4. Altera Tag & <br> Git Push Automatizado| RepoGitOps

    %% Fluxo de GitOps
    subgraph RepoGitOps [📂 REPO 2: GitOps Manifestos]
        YAML[📄 k8s/deployment.yaml <br> Tag atualizada]
    end
    class RepoGitOps repoStyle;

    %% Monitoramento do ArgoCD
    ArgoCD[🐙 Argo CD <br> Dentro do Cluster] -->|5. Monitoramento / Polling| RepoGitOps
    ArgoCD -->|6. Detecta Mudança <br> Out of Sync| K8sCluster

    %% Aplicação no Cluster
    subgraph K8sCluster [☸️ CLUSTER KUBERNETES]
        Pods[Pods Atualizados <br> Nova Versão em Produção]
    end
    class K8sCluster clusterStyle;

    K8sCluster -->|7. Puxa Nova Imagem| Registry

    %% Fluxo Paralelo do Terraform
    subgraph RepoTerraform [🌍 REPO 3: Infraestrutura]
        TF[🛠️ Código Terraform]
    end
    class RepoTerraform infraStyle;

    TF -->|Aplica Uma Vez / Cria a Base| K8sCluster
    TF -->|Cria o Registro| Registry

    %% Notas Visuais
    style Dev fill:#fff,stroke:#333,stroke-width:1px
    style Registry fill:#fff,stroke:#1d9bf0,stroke-width:2px
    style ArgoCD fill:#fff,stroke:#ff5500,stroke-width:2px
```