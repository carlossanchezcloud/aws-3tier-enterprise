# aws-3tier-enterprise

Arquitectura AWS de 3 capas con alta disponibilidad, seguridad por defecto y despliegue automatizado mediante GitHub Actions + Terraform.

## Topología

```
Internet
    │
    ▼
[ALB] ── Subredes Públicas (10.0.1.0/24, 10.0.2.0/24)
    │
    ▼
[EC2 Website × 2] ── Subredes Privadas App (10.0.11.0/24, 10.0.12.0/24)
    │
    ▼
[EC2 Backend × 2] ── Subredes Privadas App (10.0.11.0/24, 10.0.12.0/24)
    │
    ▼
[RDS MySQL Primary ↔ Failover] ── Subredes Privadas DB (10.0.21.0/24, 10.0.22.0/24)

Salida a Internet (EC2 privadas) → NAT Instance (t3.micro, Free Tier)
```

## Stack Tecnológico

| Capa       | Tecnología                          |
|------------|-------------------------------------|
| Frontend   | S3 estático + CloudFront (OAC)      |
| Backend    | Node.js 20 + PM2, EC2 t3.micro      |
| Base datos | RDS MySQL 8.0, db.t3.micro, Multi-AZ|
| IaC        | Terraform 1.x, módulos reutilizables|
| CI/CD      | GitHub Actions + OIDC (sin claves)  |
| Acceso EC2 | AWS Systems Manager (sin SSH)       |
| NAT        | NAT Instance t3.micro (Free Tier)   |

## Decisiones de Diseño

### Por qué NAT Instance y no NAT Gateway
NAT Gateway cuesta ~$32/mes fijo + transferencia. Una NAT Instance t3.micro entra en Free Tier (750 h/mes el primer año) y realiza exactamente la misma función para tráfico de salida moderado.

### Por qué IAM OIDC para GitHub Actions
Elimina la necesidad de almacenar `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` en secretos de GitHub. El workflow obtiene credenciales temporales firmadas por el token JWT de GitHub — rotación automática, sin secretos de larga duración.

### Por qué SSM en lugar de llaves SSH
- Sin gestión de pares de claves
- Sin puertos 22 abiertos (reduce superficie de ataque)
- Sesiones auditadas en CloudTrail
- Acceso desde consola AWS sin VPN

## Requisitos Previos

- Terraform >= 1.5
- AWS CLI v2 configurado (`aws configure`)
- Cuenta GitHub con repositorio `carlossanchezcloud/aws-3tier-enterprise`
- PowerShell 7+ (para scripts Windows)

## Despliegue — Paso a Paso

### 1. Bootstrap (solo primera vez)

```powershell
.\scripts\bootstrap.ps1
```

Crea el bucket S3 y tabla DynamoDB para el estado remoto de Terraform.

### 2. Inicializar Terraform

```bash
cd terraform/environments/prod
terraform init
```

### 3. Revisar plan

```bash
terraform plan -var-file="terraform.tfvars"
```

### 4. Aplicar

```bash
terraform apply -var-file="terraform.tfvars"
```

### 5. Validar despliegue

```powershell
.\scripts\validate.ps1
```

Genera `validate_report.txt` con estado de todos los recursos.

## Estructura del Repositorio

```
aws-3tier-enterprise/
├── .gitignore                        # Protege secretos y estado
├── README.md
├── terraform/
│   ├── modules/
│   │   ├── networking/               # VPC, subredes, NAT, SGs
│   │   ├── compute/                  # ASG, ALB, Launch Template
│   │   ├── database/                 # RDS MySQL Multi-AZ
│   │   └── storage/                  # S3 + CloudFront OAC
│   └── environments/
│       └── prod/                     # Punto de entrada Terraform
│           ├── main.tf
│           ├── variables.tf
│           ├── outputs.tf
│           ├── providers.tf
│           └── terraform.tfvars      # ← en .gitignore (secretos)
├── app/
│   ├── frontend/                     # React / Vite
│   └── backend/                      # Node.js / Express
├── scripts/
│   ├── bootstrap.ps1                 # Crea backend S3 + DynamoDB
│   ├── user_data.sh                  # Plantilla EC2 user_data
│   └── validate.ps1                  # Validaciones post-deploy
└── .github/
    └── workflows/
        ├── infra.yml                 # PR → fmt/lint/tfsec/plan
        └── app.yml                   # Push main → build/deploy
```

## Security Groups — Flujo de Red

```
Internet → sg_alb (80, 443) → sg_website (80, 3000) → sg_backend (3000) → sg_database (3306)
```

Ninguna capa expone puertos directamente a Internet excepto el ALB.

## Variables Sensibles

Nunca hardcodear en código. Usar `terraform.tfvars` (excluido de Git):

```hcl
db_password = "TuPasswordSeguro2026"
```

En producción, migrar a AWS Secrets Manager o SSM Parameter Store SecureString.

## Licencia

MIT
