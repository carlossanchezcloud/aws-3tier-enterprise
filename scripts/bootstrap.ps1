<#
.SYNOPSIS
    Bootstrap del backend de estado remoto para Terraform.

.DESCRIPTION
    Crea el bucket S3 (versionado + cifrado) necesario ANTES de ejecutar
    `terraform init` en environments/prod.

    El locking se gestiona con S3 native locking (Terraform >= 1.10),
    que escribe un archivo .tflock en el mismo bucket usando S3 conditional
    writes. No se necesita DynamoDB.

    Ejecutar UNA SOLA VEZ por cuenta/región.

.PARAMETER Region
    Región AWS donde se crea el bucket. Default: us-east-1

.PARAMETER BucketName
    Nombre del bucket S3 para el estado. Default: aws-3tier-appcitas-tfstate

.EXAMPLE
    .\scripts\bootstrap.ps1
    .\scripts\bootstrap.ps1 -Region us-west-2
#>

param(
    [string]$Region     = "us-east-1",
    [string]$BucketName = "aws-3tier-appcitas-tfstate"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "    [OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "    [!!] $Message" -ForegroundColor Yellow
}

# ------------------------------------------------------------------
# 0. Verificar AWS CLI y credenciales
# ------------------------------------------------------------------
Write-Step "Verificando AWS CLI y credenciales..."

try {
    $identity = aws sts get-caller-identity --output json | ConvertFrom-Json
    Write-Success "Account : $($identity.Account)"
    Write-Success "UserARN : $($identity.Arn)"
    Write-Success "Region  : $Region"
} catch {
    Write-Error "No se pudo autenticar con AWS. Ejecuta 'aws configure' primero."
    exit 1
}

# ------------------------------------------------------------------
# 1. Crear bucket S3
# ------------------------------------------------------------------
Write-Step "Creando bucket S3: $BucketName"

$bucketExists = $false
try {
    aws s3api head-bucket --bucket $BucketName --region $Region 2>$null
    $bucketExists = $true
    Write-Warn "El bucket ya existe. Omitiendo creación."
} catch {
    # El bucket no existe — crearlo
}

if (-not $bucketExists) {
    if ($Region -eq "us-east-1") {
        # us-east-1 NO acepta LocationConstraint
        aws s3api create-bucket `
            --bucket $BucketName `
            --region $Region
    } else {
        aws s3api create-bucket `
            --bucket $BucketName `
            --region $Region `
            --create-bucket-configuration LocationConstraint=$Region
    }
    Write-Success "Bucket creado."
}

# ------------------------------------------------------------------
# 2. Habilitar versionado
# Permite recuperar versiones anteriores del estado si se corrompe
# ------------------------------------------------------------------
Write-Step "Habilitando versionado en S3..."

aws s3api put-bucket-versioning `
    --bucket $BucketName `
    --versioning-configuration Status=Enabled

Write-Success "Versionado activado."

# ------------------------------------------------------------------
# 3. Cifrado por defecto (AES-256)
# ------------------------------------------------------------------
Write-Step "Configurando cifrado AES-256 por defecto..."

$encryptionConfig = @{
    Rules = @(
        @{
            ApplyServerSideEncryptionByDefault = @{
                SSEAlgorithm = "AES256"
            }
            BucketKeyEnabled = $true
        }
    )
} | ConvertTo-Json -Depth 5

aws s3api put-bucket-encryption `
    --bucket $BucketName `
    --server-side-encryption-configuration $encryptionConfig

Write-Success "Cifrado AES-256 configurado."

# ------------------------------------------------------------------
# 4. Bloquear acceso público (nunca exponer el estado)
# ------------------------------------------------------------------
Write-Step "Bloqueando acceso público al bucket..."

aws s3api put-public-access-block `
    --bucket $BucketName `
    --public-access-block-configuration `
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

Write-Success "Acceso público bloqueado."

# ------------------------------------------------------------------
# 5. Política de ciclo de vida (limpiar versiones antiguas tras 90 días)
# ------------------------------------------------------------------
Write-Step "Configurando lifecycle policy (versiones antiguas → 90 días)..."

$lifecycleConfig = @{
    Rules = @(
        @{
            ID     = "expire-old-versions"
            Status = "Enabled"
            Filter = @{ Prefix = "" }
            NoncurrentVersionExpiration = @{
                NoncurrentDays = 90
            }
        }
    )
} | ConvertTo-Json -Depth 5

aws s3api put-bucket-lifecycle-configuration `
    --bucket $BucketName `
    --lifecycle-configuration $lifecycleConfig

Write-Success "Lifecycle configurado."

# ------------------------------------------------------------------
# 6. Resumen final
# ------------------------------------------------------------------
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Bootstrap completado exitosamente" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  S3 Bucket  : $BucketName"
Write-Host "  Locking    : S3 native (use_lockfile = true) — sin DynamoDB"
Write-Host "  Region     : $Region"
Write-Host ""
Write-Host "  Siguiente paso:" -ForegroundColor Yellow
Write-Host "    cd terraform/environments/prod" -ForegroundColor Yellow
Write-Host "    terraform init" -ForegroundColor Yellow
Write-Host ""
