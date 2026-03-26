# ============================================================
# GUÍA DE DESPLIEGUE AWS — Salón de Belleza
# Arquitectura de 3 Capas Segura (VPC Privada)
# ============================================================
# Prerequisito: AWS CLI instalado y configurado con un usuario
# IAM que tenga permisos EC2, RDS, VPC.

# ──────────────────────────────────────────────────────────────
# PASO 1: CREAR LA VPC Y LAS SUBREDES
# ──────────────────────────────────────────────────────────────

# 1a. Crear la VPC
VPC_ID=$(aws ec2 create-vpc \
    --cidr-block 10.0.0.0/16 \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=salon-vpc}]' \
    --query 'Vpc.VpcId' --output text)
echo "VPC creada: $VPC_ID"

# Habilitar DNS en la VPC (necesario para resolver el endpoint RDS)
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames

# 1b. Crear las 3 subredes (usa dos AZs para RDS Multi-AZ)
SUBNET_PUB=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 \
    --availability-zone us-east-1a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=salon-subnet-public}]' \
    --query 'Subnet.SubnetId' --output text)

SUBNET_PRIV_APP=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 \
    --availability-zone us-east-1a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=salon-subnet-private-app}]' \
    --query 'Subnet.SubnetId' --output text)

SUBNET_PRIV_DB=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID --cidr-block 10.0.3.0/24 \
    --availability-zone us-east-1a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=salon-subnet-private-db}]' \
    --query 'Subnet.SubnetId' --output text)

# Segunda subred de datos en otra AZ (requerido por RDS Multi-AZ)
SUBNET_PRIV_DB2=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID --cidr-block 10.0.4.0/24 \
    --availability-zone us-east-1b \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=salon-subnet-private-db2}]' \
    --query 'Subnet.SubnetId' --output text)

echo "Subredes: PUB=$SUBNET_PUB | APP=$SUBNET_PRIV_APP | DB=$SUBNET_PRIV_DB / $SUBNET_PRIV_DB2"

# 1c. Internet Gateway → solo para la subred pública
IGW_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=salon-igw}]' \
    --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID

# 1d. Route table pública (con ruta a Internet)
RTB_PUB=$(aws ec2 create-route-table --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=salon-rtb-public}]' \
    --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $RTB_PUB \
    --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
aws ec2 associate-route-table --route-table-id $RTB_PUB --subnet-id $SUBNET_PUB

# Las subredes privadas NO tienen ruta a Internet (usan la route table main de la VPC)
# Para que el backend pueda hacer actualizaciones de SO (yum/apt), agregar un NAT Gateway
# opcional en la subred pública y asociarlo a los RTBs privados.


# ──────────────────────────────────────────────────────────────
# PASO 2: SECURITY GROUPS (Mínimo privilegio)
# ──────────────────────────────────────────────────────────────

# SG-frontend: solo 80/443 desde Internet
SG_FRONTEND=$(aws ec2 create-security-group \
    --group-name SG-salon-frontend \
    --description "Frontend EC2 - acepta HTTP/S publico" \
    --vpc-id $VPC_ID \
    --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id $SG_FRONTEND \
    --protocol tcp --port 80  --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_FRONTEND \
    --protocol tcp --port 443 --cidr 0.0.0.0/0
# SSH solo desde tu IP (reemplazar con tu IP real)
aws ec2 authorize-security-group-ingress --group-id $SG_FRONTEND \
    --protocol tcp --port 22 --cidr TU_IP/32

# SG-backend: SOLO acepta tráfico del SG-frontend en el puerto 3001
SG_BACKEND=$(aws ec2 create-security-group \
    --group-name SG-salon-backend \
    --description "Backend Node.js - solo acepta desde SG-frontend" \
    --vpc-id $VPC_ID \
    --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id $SG_BACKEND \
    --protocol tcp --port 3001 \
    --source-group $SG_FRONTEND    # ← referencia al SG, no a una IP
# SSH desde bastion o tu IP para mantenimiento
aws ec2 authorize-security-group-ingress --group-id $SG_BACKEND \
    --protocol tcp --port 22 --cidr TU_IP/32

# SG-db: SOLO acepta PostgreSQL desde el SG-backend
SG_DB=$(aws ec2 create-security-group \
    --group-name SG-salon-db \
    --description "RDS PostgreSQL - solo acepta desde SG-backend" \
    --vpc-id $VPC_ID \
    --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id $SG_DB \
    --protocol tcp --port 5432 \
    --source-group $SG_BACKEND     # ← solo el backend puede conectarse a la BD

echo "SGs: FRONTEND=$SG_FRONTEND | BACKEND=$SG_BACKEND | DB=$SG_DB"


# ──────────────────────────────────────────────────────────────
# PASO 3: RDS POSTGRESQL
# ──────────────────────────────────────────────────────────────

# 3a. Subnet Group de la BD (requiere mínimo 2 AZs)
aws rds create-db-subnet-group \
    --db-subnet-group-name salon-db-subnet-group \
    --db-subnet-group-description "Subredes privadas para RDS salon" \
    --subnet-ids $SUBNET_PRIV_DB $SUBNET_PRIV_DB2

# 3b. Crear la instancia RDS
aws rds create-db-instance \
    --db-instance-identifier salon-db \
    --db-instance-class       db.t3.micro \
    --engine                  postgres \
    --engine-version          16.3 \
    --master-username         salon_admin \
    --master-user-password    "TuPasswordSegura123!" \
    --db-name                 salon_db \
    --vpc-security-group-ids  $SG_DB \
    --db-subnet-group-name    salon-db-subnet-group \
    --no-publicly-accessible \          # ← CRÍTICO: sin acceso desde Internet
    --storage-encrypted \               # ← cifrado en reposo
    --allocated-storage       20 \
    --backup-retention-period 7 \
    --deletion-protection               # ← evita borrado accidental

# Esperar hasta que la instancia esté disponible (~10 min)
aws rds wait db-instance-available --db-instance-identifier salon-db

# Obtener el endpoint del RDS (usar en el .env del backend)
RDS_ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier salon-db \
    --query 'DBInstances[0].Endpoint.Address' --output text)
echo "RDS Endpoint: $RDS_ENDPOINT"

# 3c. Crear las tablas desde el EC2 backend (ya dentro de la VPC)
# psql -h $RDS_ENDPOINT -U salon_admin -d salon_db -f schema.sql


# ──────────────────────────────────────────────────────────────
# PASO 4: EC2 BACKEND (subred privada)
# ──────────────────────────────────────────────────────────────
# AMI Amazon Linux 2023 en us-east-1 (verificar la AMI más reciente)
AMI_ID="ami-0c02fb55956c7d316"

# Key pair para acceso SSH (crear antes si no existe)
aws ec2 create-key-pair --key-name salon-key \
    --query 'KeyMaterial' --output text > ~/.ssh/salon-key.pem
chmod 400 ~/.ssh/salon-key.pem

INSTANCE_BACKEND=$(aws ec2 run-instances \
    --image-id           $AMI_ID \
    --instance-type      t3.small \
    --key-name           salon-key \
    --security-group-ids $SG_BACKEND \
    --subnet-id          $SUBNET_PRIV_APP \
    --no-associate-public-ip-address \   # ← sin IP pública
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=salon-backend}]' \
    --user-data '#!/bin/bash
        dnf update -y
        dnf install -y nodejs20 git
        npm install -g pm2
        # Clonar el código desde S3 o CodeDeploy en lugar de GitHub en producción
    ' \
    --query 'Instances[0].InstanceId' --output text)

echo "EC2 Backend: $INSTANCE_BACKEND"


# ──────────────────────────────────────────────────────────────
# PASO 5: EC2 FRONTEND (subred pública)
# ──────────────────────────────────────────────────────────────
INSTANCE_FRONTEND=$(aws ec2 run-instances \
    --image-id           $AMI_ID \
    --instance-type      t3.micro \
    --key-name           salon-key \
    --security-group-ids $SG_FRONTEND \
    --subnet-id          $SUBNET_PUB \
    --associate-public-ip-address \      # ← sí tiene IP pública
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=salon-frontend}]' \
    --user-data '#!/bin/bash
        dnf update -y
        dnf install -y nginx nodejs20 git
        systemctl enable nginx
        # Aquí se despliega el build de Vite
    ' \
    --query 'Instances[0].InstanceId' --output text)

# Obtener IP pública del frontend
FRONTEND_IP=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_FRONTEND \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "Frontend IP pública: $FRONTEND_IP"


# ──────────────────────────────────────────────────────────────
# PASO 6: DESPLEGAR EL CÓDIGO EN EL BACKEND
# ──────────────────────────────────────────────────────────────
# Conectarse al EC2 backend via Session Manager (no requiere SSH público):
# aws ssm start-session --target $INSTANCE_BACKEND
#
# Una vez conectado:
#   git clone <tu-repo> /home/ec2-user/salon-belleza
#   cd /home/ec2-user/salon-belleza/backend
#   cp .env.example .env
#   # Editar .env con el endpoint RDS real y CORS_ORIGIN=http://<FRONTEND_IP>
#   nano .env
#   npm install --production
#   sudo cp ../infra/salon-backend.service /etc/systemd/system/
#   sudo systemctl daemon-reload
#   sudo systemctl enable --now salon-backend
#   sudo systemctl status salon-backend
#
# Crear las tablas:
#   psql -h $RDS_ENDPOINT -U salon_admin -d salon_db -f database/schema.sql


# ──────────────────────────────────────────────────────────────
# PASO 7: DESPLEGAR EL FRONTEND
# ──────────────────────────────────────────────────────────────
# En tu máquina local:
#   cd frontend
#   cp .env.example .env
#   # Editar VITE_API_URL con la IP PRIVADA del EC2 backend (10.0.2.XX:3001/api)
#   nano .env
#   npm install
#   npm run build          # genera /dist
#   scp -i ~/.ssh/salon-key.pem -r dist/ ec2-user@$FRONTEND_IP:/var/www/salon/
#
# En el EC2 frontend:
#   sudo cp infra/nginx-frontend.conf /etc/nginx/sites-available/salon
#   sudo ln -s /etc/nginx/sites-available/salon /etc/nginx/sites-enabled/
#   sudo nginx -t && sudo systemctl reload nginx


# ──────────────────────────────────────────────────────────────
# VERIFICACIÓN FINAL
# ──────────────────────────────────────────────────────────────
# 1. Desde un navegador: http://<FRONTEND_IP>  → debe cargar la app React
# 2. Desde el EC2 backend (interno):
#    curl http://localhost:3001/health          → {"status":"ok",...}
# 3. Desde el EC2 backend:
#    psql -h $RDS_ENDPOINT -U salon_admin -d salon_db -c "\dt"  → lista las tablas
# 4. Intentar desde Internet al backend:
#    curl http://<IP_PRIVADA_BACKEND>:3001      → debe FALLAR (sin ruta)
# 5. Intentar desde Internet al RDS:
#    psql -h $RDS_ENDPOINT                     → debe FALLAR (no publicly accessible)
