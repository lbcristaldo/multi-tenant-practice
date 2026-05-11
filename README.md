# Arquitectura Multi-Tenant en AWS

Diseño de infraestructura para plataforma multi-tenant con aislamiento por cliente, roles organizacionales (QA, WebDev, AI Engineer) y observabilidad.

---

## Descripción

1. **IAM + Roles organizacionales**: QA, WebDev y AI Engineers con permisos acotados por tenant y ambiente 
2. **EKS + IRSA**: Pods que asumen roles IAM específicos por tenant con aislamiento en red 
3. **Networking + Security Groups** Aislamiento entre tenants dentro de una misma VPC 
4. **Observabilidad**: Monitoreo de 4000 imágenes/día por cliente con alertas personalizadas 

---

## Diagramas de arquitectura

### 1. IAM + Roles por tenant

```mermaid
graph TB
    Users[Usuarios] --> Roles[Roles: QA / WebDev / AI]
    Roles --> Policies[Políticas IAM]
    Policies --> Condition[Condición: tenant_id tag]
    Condition --> Resources[Recursos del tenant: S3 / KMS / Secrets]
```

### 2. EKS + IRSA

```mermaid
graph TB
    subgraph "Cluster EKS"
        NS1[Namespace: tenant-alfa]
        NS2[Namespace: tenant-beta]

        NS1 --> SA1[ServiceAccount: sa-alfa]
        SA1 --> IRSA1[IRSA Role: arn:aws:iam::xxx:role/alfa]
        IRSA1 --> Policy1[Policy: S3 / Secrets / SQS para alfa]

        NS2 --> SA2[ServiceAccount: sa-beta]
        SA2 --> IRSA2[IRSA Role: arn:aws:iam::xxx:role/beta]
        IRSA2 --> Policy2[Policy: S3 / Secrets / SQS para beta]

        NP[Network Policy: deny cross-namespace]
    end
```

### 3. Networking + Security Groups

```mermaid
graph TB
    subgraph "VPC 10.0.0.0/16"
        IGW[Internet Gateway] --> PublicSubnet[Subnet Pública]
        PublicSubnet --> NAT[NAT Gateway]
        NAT --> PrivateSubnet[Subnet Privada]

        PrivateSubnet --> EKS[EKS Pods]
        PrivateSubnet --> RDS[RDS PostgreSQL]

        SG1[SG: tenant-alfa] --> EKS
        SG2[SG: tenant-beta] --> EKS
        SGRDS[SG: RDS] --> RDS
        SGRDS --> SG1
        SGRDS --> SG2

        VPE_S3[VPC Endpoint: S3]
        VPE_DDB[VPC Endpoint: DynamoDB]
        PrivateSubnet --> VPE_S3
        PrivateSubnet --> VPE_DDB
    end
```

### 4. Observabilidad

```mermaid
graph LR
    App[Aplicación] -->|Embedded Metrics| CWLogs[CloudWatch Logs]
    CWLogs --> Metrics[Métricas: ImagesProcessed / ErrorRate / Latency]
    Metrics --> Dashboard1[Dashboard por tenant]
    Metrics --> Dashboard2[Dashboard global]
    Metrics --> Alarm1[Alarma: ErrorRate > 1%]
    Metrics --> Alarm2[Alarma: Latencia > 30s]
    Metrics --> Alarm3[Alarma: QueueDepth > 500]
    Metrics --> Alarm4[Alarma: NoImages > 2h]
    Alarm1 --> SNS[SNS Topic]
    Alarm2 --> SNS
    Alarm3 --> SNS
    Alarm4 --> SNS
    SNS --> Email[Email]
    SNS --> Slack[Slack]
```

---

## Decisiones y tradeoffs

| Área | Decisión | Tradeoff |
|------|----------|----------|
| Cuentas AWS | Única | Simplicidad vs. aislamiento extremo |
| Seguridad | Security Group por tenant | Claridad vs. límite de 60 SGs |
| K8s permisos | IRSA | Seguro vs. setup inicial complejo |
| Métricas | Por imagen con Embedded Metrics | Detalle vs. costo a escala |

---

## Stack tecnológico

| Categoría | Tecnologías |
|-----------|-------------|
| **AWS** | IAM, EKS, VPC, RDS, S3, KMS, CloudWatch, SNS |
| **Kubernetes** | Namespaces, Network Policies, IRSA |
| **Infra as Code** | Terraform + LocalStack (validación sin costo) |
| **Base de datos** | PostgreSQL con Row Level Security (RLS) |

---

## Estructura del proyecto

```
terraform/
├── 01-multi-tenant/     # IAM + roles + S3 + KMS
├── 02-eks/              # EKS cluster + IRSA + SQS
├── 03-networking/       # VPC + Security Groups + RDS
├── 04-observability/    # CloudWatch dashboards + alarmas
└── policies/            # JSON de políticas IAM
```

---

## Validación local con LocalStack

```bash
# 1. Levantar LocalStack (emulador de AWS sin costo)
docker run -d --rm -p 4566:4566 localstack/localstack

# 2. Configurar credenciales fake
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test

# 3. Validar Terraform
cd 01-multi-tenant
terraform init
terraform plan
```