# Arquitectura Multi-Tenant en AWS

Diseño de infraestructura para plataforma multi-tenant con aislamiento por cliente, roles organizacionales (QA, WebDev, AI Engineer) y observabilidad.

---

## Descripción

1. **IAM + Roles organizacionales**: QA, WebDev y AI Engineers con permisos acotados por tenant y ambiente
2. **EKS + IRSA**: Pods que asumen roles IAM específicos por tenant con aislamiento en red
3. **Networking + Security Groups**: Aislamiento entre tenants dentro de una misma VPC (ahorro consciente y simplicidad operativa)
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

---

## Disclaimer: Profundización del diseño (diagramas adicionales)

> Los diagramas que siguen corresponden a una **profundización del diseño original**. No reemplazan ni contradicen los diagramas anteriores. Representan el mismo diseño pero con mayor nivel de detalle en áreas específicas: IAM Conditions, EKS + IRSA mapping, Network Policies, permisos por combinación, seguridad en el pipeline (Cosign + SBOM), escalado con KEDA y observabilidad completa. A su vez, se presume un enfoque distinto respecto a quiénes utilizarán el diseño, siendo este inclinado enteramente a la iteración propia de tareas de desarrollo para los tres perfiles.

---

### 5. IAM + Condition con PrincipalTag

```mermaid
graph LR
    subgraph "IAM Estructura"
        User["IAM User<br/>dev@empresa.com"] -->|Switch Role| Role["IAM Role<br/>qa-role / ai-role / webdev-role"]
        Role --> Policy[IAM Policy]
        Policy --> Condition["Condition:<br/>StringEquals + PrincipalTag"]
        Condition --> S3["S3: {aws:PrincipalTag/tenant-data/*}"]
        Condition --> KMS["KMS: {key/$aws:PrincipalTag/tenant}"]
        Condition --> RDS["RDS: {tenant_id = $aws:PrincipalTag/tenant}"]
    end

    subgraph "Tags asignados al asumir rol"
        Tag1[tenant: qa]
        Tag2[tenant: ai]
        Tag3[tenant: webdev]
        Tag4[environment: dev/stage/prod]
    end
```
### 6. EKS + IRSA mapping detallado (tenants: qa, ai, webdev)

```mermaid
graph TB
    subgraph "Cluster EKS"
        subgraph "Namespace: tenant-qa"
            SA_QA_DEV[ServiceAccount: sa-qa-dev]
            SA_QA_STAGE[ServiceAccount: sa-qa-stage]
            SA_QA_PROD[ServiceAccount: sa-qa-prod]
        end

        subgraph "Namespace: tenant-ai"
            SA_AI_DEV[ServiceAccount: sa-ai-dev]
            SA_AI_STAGE[ServiceAccount: sa-ai-stage]
            SA_AI_PROD[ServiceAccount: sa-ai-prod]
        end

        subgraph "Namespace: tenant-webdev"
            SA_WD_DEV[ServiceAccount: sa-webdev-dev]
            SA_WD_STAGE[ServiceAccount: sa-webdev-stage]
            SA_WD_PROD[ServiceAccount: sa-webdev-prod]
        end
    end

    subgraph "IAM"
        IRSA_QA[IRSA Role: qa-role<br/>assume_role_with_webidentity]
        IRSA_AI[IRSA Role: ai-role]
        IRSA_WD[IRSA Role: webdev-role]
    end

    SA_QA_DEV -.->|annotation| IRSA_QA
    SA_QA_STAGE -.-> IRSA_QA
    SA_QA_PROD -.-> IRSA_QA
    SA_AI_DEV -.-> IRSA_AI
    SA_AI_STAGE -.-> IRSA_AI
    SA_AI_PROD -.-> IRSA_AI
    SA_WD_DEV -.-> IRSA_WD
    SA_WD_STAGE -.-> IRSA_WD
    SA_WD_PROD -.-> IRSA_WD
```

### 7. Network Policies: deny-all entre namespaces

```mermaid
graph TB
    subgraph "Network Policies"
        NP_DENY[Deny-all cross-namespace]
    end

    subgraph "Namespace tenant-qa"
        POD1[Pod QA<br/>labels: tenant=qa, environment=dev]
        POD2[Pod QA<br/>environment=stage]
    end

    subgraph "Namespace tenant-ai"
        POD3[Pod AI<br/>tenant=ai]
    end

    subgraph "Namespace tenant-webdev"
        POD4[Pod WebDev<br/>tenant=webdev]
    end

    POD1 <-->|✅ Permitido| POD2
    POD1 -.-x|❌ Denegado| POD3
    POD1 -.-x|❌ Denegado| POD4
    POD3 -.-x|❌ Denegado| POD4

    NP_DENY -.->|aplica a| POD1
    NP_DENY -.->|aplica a| POD3
    NP_DENY -.->|aplica a| POD4
```

### 8. Permisos por combinación (ambiente + perfil + objeto)

```mermaid
graph LR
    subgraph "Permiso generado dinámicamente"
        Direction[Acceso solicitado] --> Combo[Combinación]
        Combo --> Env[Ambiente: dev/stage/prod]
        Combo --> Profile[Perfil: qa/ai/webdev]
        Combo --> Object[Objeto: bucket/table/key]
    end

    subgraph "Ejemplo"
        Example[AI en stage escribe en bucket] --> Check{¿Permiso válido?}
        Check -->|Sí| Allow[✅ Permiso concedido]
        Check -->|No| Deny[❌ Denegado + auditoría]
    end

    subgraph "Registro"
        Allow --> Log[CloudTrail / CloudWatch Logs]
        Deny --> Log
        Log --> Alert[Alerta si patrón sospechoso]
    end
```

### 9. CI/CD + Seguridad en ECR (Cosign + SBOM + Kyverno)

```mermaid
flowchart TB
    subgraph "Dev environment"
        DEV[Developer<br/>push a dev branch] --> BUILD[Build local]
        BUILD --> DEV_ECR[ECR dev]
    end

    subgraph "Stage environment"
        STAGE[Promote to stage] --> SCAN[Escaneo estático<br/>trivy / snyk]
        SCAN -->|pass| SIGN[Firmar con Cosign]
        SIGN --> SBOM[Generar SBOM<br/>syft / bom]
        SBOM --> STAGE_ECR[ECR stage]
    end

    subgraph "Prod environment"
        PROD[Promote to prod] --> VERIFY[Verificar firma Cosign]
        VERIFY -->|valid| VERIFY_SBOM[Verificar SBOM<br/>no dependencias maliciosas]
        VERIFY_SBOM -->|pass| PROD_ECR[ECR prod]
        PROD_ECR --> DEPLOY[Deploy a EKS prod]
    end

    subgraph "IAM + Kyverno"
        POLICY[Kyverno ClusterPolicy:<br/>solo imágenes firmadas]
        DEPLOY --> POLICY
        POLICY -->|allow| RUN[Pod corre]
        POLICY -->|deny| REJECT[❌ Rechazado + alerta]
    end
```

### 10. Escalado: Taints + Tolerations + KEDA

```mermaid
graph TB
    subgraph "Node Group A - General"
        NODE1[t3.medium<br/>No taints]
        NODE2[t3.medium<br/>No taints]
    end

    subgraph "Node Group B - AI Heavy"
        NODE_AI[c5.xlarge<br/>Taint: ai-workload=true:NoSchedule]
    end

    subgraph "Pods"
        QA_POD[Pod QA<br/>Sin toleration] --> NODE1
        QA_POD --> NODE2
        AI_POD[Pod AI<br/>Toleration: ai-workload=true] --> NODE_AI
    end

    subgraph "KEDA (Event-driven autoscaler)"
        SQS[SQS queue depth > threshold] --> SCALE[Escalar deployment]
        PROM[Prometheus metric] --> SCALE
        CRON[Cron schedule] --> SCALE
    end
```

### 11. Observabilidad completa (métricas + alarmas + seguridad)

```mermaid
flowchart TB
    subgraph "Fuentes de métricas"
        APP[Aplicación] -->|Embedded Metrics| CW[CloudWatch]
        EKS[EKS] -->|Container Insights| CW
        SQS[SQS] -->|Queue metrics| CW
        RDS[RDS] -->|Performance insights| CW
        CI[CI/CD Pipeline] -->|Métrica: imágenes firmadas| CW
    end

    subgraph "Procesamiento"
        CW --> DASH[Dashboards]
        CW --> ALARM[Alarmas]
        ALARM --> SNS[SNS Topic]
    end

    subgraph "Dashboards por tenant"
        DASH --> DASH_QA[Dashboard QA<br/>métricas de qa-dev/stage/prod]
        DASH --> DASH_AI[Dashboard AI]
        DASH --> DASH_WD[Dashboard WebDev]
    end

    subgraph "Alertas clave"
        ALARM --> A1[Error rate > 1%]
        ALARM --> A2[Latencia p99 > 30s]
        ALARM --> A3[Queue depth > 500]
        ALARM --> A4[0 imágenes en 2h]
        ALARM --> A5[Imagen sin firma intentada]
    end

    subgraph "Notificaciones"
        SNS --> EMAIL[Email]
        SNS --> SLACK[Slack]
        SNS --> PAGER[PagerDuty]
    end

    subgraph "Alerta de seguridad"
        A5 --> SEC[Security Team]
        SEC --> AUDIT[Auditoría]
    end
```

---

## Nota final

Este documento representa el diseño completo de la arquitectura multi-tenant, combinando el enfoque inicial con diagramas de profundización que detallan aspectos clave como IAM Conditions, IRSA mapping, Network Policies, seguridad en el pipeline de imágenes (Cosign + SBOM + Kyverno), escalado con KEDA (de ser preciso) y observabilidad avanzada (considerando las especificaciones de productividad requerida -4,000 imagenes/día.