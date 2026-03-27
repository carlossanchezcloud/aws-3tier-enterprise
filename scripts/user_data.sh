#!/bin/bash
# =============================================================
# user_data.sh - Plantilla para templatefile() de Terraform
#
# Variables sustituidas por Terraform en tiempo de plan:
#   ${rds_endpoint}  - host:puerto del endpoint RDS
#   ${db_password}   - contrasena del usuario admin de MySQL
#   ${aws_region}    - region AWS (ej. us-east-1)
#
# Sistema: Amazon Linux 2023 (dnf, systemd)
# =============================================================
set -euo pipefail

LOG="/var/log/user_data.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== [$(date -u +%Y-%m-%dT%H:%M:%SZ)] Iniciando user_data ==="

# -- 1. Node.js 20 via NodeSource -----------------------------
echo "--- Instalando Node.js 20..."
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
dnf install -y nodejs git

node --version
npm --version

# -- 2. PM2 - gestor de procesos para Node.js -----------------
echo "--- Instalando PM2..."
npm install -g pm2

pm2 --version

# -- 3. Clonar repositorio ------------------------------------
echo "--- Clonando repositorio..."
REPO_DIR="/app/repo"
BACKEND_DIR="$REPO_DIR/app/backend"

mkdir -p /app

if [ -d "$REPO_DIR/.git" ]; then
  echo "    Repositorio ya existe, actualizando..."
  git -C "$REPO_DIR" pull --ff-only
else
  git clone https://github.com/carlossanchezcloud/aws-3tier-enterprise "$REPO_DIR"
fi

cd /app/repo/app/backend
npm install

# -- 4. Generar /app/repo/app/backend/.env --------------------
# printf '%s=%s\n' es mas seguro que echo o heredoc para
# valores con caracteres especiales (passwords con $, !, etc.)
echo "--- Generando .env..."

# Extraer solo el hostname del endpoint RDS (quitar :3306 si viene incluido)
RDS_HOST=$(echo "${rds_endpoint}" | cut -d: -f1)

printf '%s=%s\n' "DB_HOST"    "$RDS_HOST"       > "$BACKEND_DIR/.env"
printf '%s=%s\n' "DB_PORT"    "3306"            >> "$BACKEND_DIR/.env"
printf '%s=%s\n' "DB_USER"    "admin"           >> "$BACKEND_DIR/.env"
printf '%s=%s\n' "DB_PASS"    "${db_password}"  >> "$BACKEND_DIR/.env"
printf '%s=%s\n' "DB_NAME"    "appcitas"        >> "$BACKEND_DIR/.env"
printf '%s=%s\n' "PORT"       "3000"            >> "$BACKEND_DIR/.env"
printf '%s=%s\n' "AWS_REGION" "${aws_region}"   >> "$BACKEND_DIR/.env"
printf '%s=%s\n' "NODE_ENV"   "production"      >> "$BACKEND_DIR/.env"

# Permisos restrictivos - solo root puede leer el .env con el password
chmod 600 "$BACKEND_DIR/.env"

echo "    .env generado correctamente."

# -- 5. Arrancar con PM2 --------------------------------------
echo "--- Arrancando aplicacion con PM2..."
cd "$BACKEND_DIR"

# Detener instancia anterior si existe (re-run seguro)
pm2 delete backend 2>/dev/null || true

pm2 start server.js \
  --name backend \
  --instances 1 \
  --max-memory-restart 400M \
  --log /var/log/pm2-backend.log \
  --merge-logs

# Esperar que la app arranque y verificar health check
echo "--- Verificando health check..."
RETRIES=12
for i in $(seq 1 $RETRIES); do
  HTTP_STATUS=$(curl -s -o /dev/null -w "%%{http_code}" http://localhost:3000/health || echo "000")
  if [ "$HTTP_STATUS" = "200" ]; then
    echo "    Health check OK (status $HTTP_STATUS)"
    break
  fi
  echo "    Intento $i/$RETRIES - status: $HTTP_STATUS, esperando 5s..."
  sleep 5
done

if [ "$HTTP_STATUS" != "200" ]; then
  echo "WARN: Health check no respondio 200 despues de $RETRIES intentos"
fi

# -- 6. Persistir PM2 al reinicio (systemd) -------------------
echo "--- Configurando PM2 startup (systemd)..."
pm2 save

# Genera el comando systemd y lo ejecuta directamente
# pm2 startup imprime lineas con color ANSI; filtramos la linea con el comando real
pm2 startup systemd -u root --hp /root 2>&1 \
  | sed 's/\x1B\[[0-9;]*[mGKH]//g' \
  | grep -E 'env PATH|^sudo' \
  | tail -1 \
  | bash

systemctl enable pm2-root 2>/dev/null || true
systemctl start pm2-root 2>/dev/null || true

echo "=== [$(date -u +%Y-%m-%dT%H:%M:%SZ)] user_data completado ==="
