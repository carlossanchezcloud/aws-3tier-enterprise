![Terraform](https://img.shields.io/badge/Terraform-1.10+-purple)
![AWS](https://img.shields.io/badge/AWS-us--east--1-orange)
![License](https://img.shields.io/badge/License-MIT-green)

# aws-3tier-enterprise

Arquitectura AWS de 3 capas con alta disponibilidad, seguridad por defecto y despliegue automatizado mediante GitHub Actions + Terraform. Diseñada para maximizar cobertura arquitectónica dentro de los límites del AWS Free Tier.

## Topología

```
Internet
    │
    ▼
[ALB] - Subredes Públicas (10.0.1.0/24, 10.0.2.0/24)
    │
    ▼
[EC2 Website × 2] - Subredes Privadas App (10.0.11.0/24, 10.0.12.0/24)
    │
    ▼
[EC2 Backend × 2] - Subredes Privadas App (10.0.11.0/24, 10.0.12.0/24)
    │
    ▼
[RDS MySQL Primary ↔ Failover] - Subredes Privadas DB (10.0.21.0/24, 10.0.22.0/24)

Salida a Internet (EC2 privadas) → NAT Instance (t3.micro, Free Tier)
```

## Stack Tecnológico

| Capa          | Tecnología                                                      |
|---------------|-----------------------------------------------------------------|
| Frontend      | S3 estático + CloudFront (OAC)                                  |
| Backend       | Node.js 20 + PM2, EC2 t3.micro                                  |
| Base de datos | RDS MySQL 8.0, db.t3.micro, Multi-AZ                            |
| IaC           | Terraform >= 1.10, módulos reutilizables                        |
| CI/CD         | GitHub Actions + OIDC (sin claves de larga duración)            |
| Acceso EC2    | AWS Systems Manager Session Manager (sin SSH)                   |
| NAT           | NAT Instance t3.micro (Free Tier)                               |
| Estado remoto | S3 + `use_lockfile = true` (Terraform >= 1.10, sin DynamoDB)    |

## Decisiones de Diseño

### NAT Instance en lugar de NAT Gateway
NAT Gateway tiene un costo fijo de ~$32/mes independiente del uso. Una NAT Instance t3.micro cubre el mismo caso de uso enrutar tráfico de salida de las EC2 privadas hacia Internet con `source_dest_check = false` e `iptables MASQUERADE`, sin costo durante el primer año en Free Tier.

### IAM OIDC para GitHub Actions
Los workflows se autentican contra AWS mediante tokens JWT firmados por GitHub, sin necesidad de almacenar `AWS_ACCESS_KEY_ID` ni `AWS_SECRET_ACCESS_KEY` como secretos. AWS valida el token contra el OIDC provider y emite credenciales temporales vía `sts:AssumeRoleWithWebIdentity`. Rotación automática, sin secretos de larga duración.

### AWS Systems Manager en lugar de SSH
- Sin gestión de pares de claves ni puertos 22 abiertos
- Reduce la superficie de ataque de los Security Groups
- Sesiones auditadas en AWS CloudTrail
- Acceso desde consola AWS o CLI sin requerir VPN ni bastión

### Estado remoto con S3 native locking
Desde Terraform 1.10, el backend S3 soporta locking nativo mediante `use_lockfile = true`. Terraform escribe un objeto `.tflock` en el mismo bucket usando S3 conditional writes (`If-None-Match: *`), eliminando la dependencia de DynamoDB para la coordinación de estado concurrente.

## Requisitos Previos

- Terraform >= 1.10.0
- AWS CLI v2 configurado (`aws configure`)
- Cuenta GitHub con repositorio `carlossanchezcloud/aws-3tier-enterprise`
- PowerShell 7+ (scripts de bootstrap y validación)

## Bootstrap

Antes del primer `terraform init`, ejecutar `scripts/bootstrap.ps1` para crear el bucket S3 de estado remoto con versionado, cifrado AES-256 y bloqueo de acceso público. El locking se gestiona con S3 native locking — no se crea ningún recurso adicional de DynamoDB.

## Estructura del Repositorio

```
aws-3tier-enterprise/
├── .gitignore                        # Excluye *.tfvars, .terraform/, *.tfstate
├── README.md
├── terraform/
│   ├── modules/
│   │   ├── networking/               # VPC, subredes, NAT Instance, 4 SGs, rutas
│   │   ├── compute/                  # ALB, ASG, Launch Template (IMDSv2), IAM/SSM
│   │   ├── database/                 # RDS MySQL 8.0 Multi-AZ, Parameter Group utf8mb4
│   │   └── storage/                  # S3 privado + CloudFront OAC
│   └── environments/
│       └── prod/                     # Punto de entrada - llama a los 4 módulos
│           ├── main.tf
│           ├── variables.tf
│           ├── outputs.tf
│           ├── providers.tf
│           ├── iam_oidc.tf           # OIDC provider + IAM Role GitHub Actions
│           └── terraform.tfvars      # ← en .gitignore (credenciales sensibles)
├── app/
│   ├── frontend/                     # React + Vite
│   └── backend/                      # Node.js + Express + Sequelize
├── scripts/
│   ├── bootstrap.ps1                 # Crea bucket S3 de estado remoto
│   ├── user_data.sh                  # Plantilla EC2 - templatefile() de Terraform
│   └── validate.ps1                  # Validaciones automáticas post-deploy
└── .github/
    └── workflows/
        ├── infra.yml                 # PR → fmt · tflint · tfsec · validate · plan
        └── app.yml                   # Push main → build · S3 sync · CF invalidation
```

## Security Groups — Flujo de Red

```
Internet → sg_alb (80, 443) → sg_website (80, 3000) → sg_backend (3000) → sg_database (3306)
```

Ninguna capa expone puertos directamente a Internet excepto el ALB. RDS no tiene endpoint público y las EC2 de backend no tienen IP pública.

## Licencia

MIT
