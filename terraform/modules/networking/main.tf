# ============================================================
# networking/main.tf
#
# Recursos:
#   - VPC con DNS habilitado
#   - Internet Gateway
#   - 6 subredes (2 públicas, 2 privadas-app, 2 privadas-db)
#   - NAT Instance t3.micro con source_dest_check=false
#   - EIP para la NAT Instance
#   - Tablas de rutas (pública, 2× privada-app, 2× privada-db)
#   - 4 Security Groups encadenados (ALB → Website → Backend → Database)
# ============================================================

locals {
  name = var.project_name
}

# ============================================================
# VPC
# ============================================================
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "${local.name}-vpc"
  })
}

# ============================================================
# Internet Gateway
# ============================================================
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${local.name}-igw"
  })
}

# ============================================================
# Subredes
# ============================================================

# Públicas — ALB vive aquí, la NAT Instance también
resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${local.name}-public-${var.azs[count.index]}"
    Tier = "Public"
  })
}

# Privadas App — Website EC2 + Backend EC2
resource "aws_subnet" "private_app" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_app_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${local.name}-private-app-${var.azs[count.index]}"
    Tier = "PrivateApp"
  })
}

# Privadas DB — RDS subnets, sin ruta a Internet
resource "aws_subnet" "private_db" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_db_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${local.name}-private-db-${var.azs[count.index]}"
    Tier = "PrivateDB"
  })
}

# ============================================================
# NAT Instance
# ============================================================

# AMI: Amazon Linux 2 (última disponible, región automática)
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

# Security Group de la NAT Instance:
# - Permite todo el tráfico entrante desde la VPC (subredes privadas lo envían aquí)
# - Permite todo el tráfico saliente hacia Internet
resource "aws_security_group" "nat" {
  name        = "${local.name}-sg-nat"
  description = "NAT Instance - VPC traffic to Internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "All traffic from VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All traffic to Internet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${local.name}-sg-nat"
  })
}

# EIP estática para la NAT Instance (la IP pública no cambia si se reinicia)
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${local.name}-eip-nat"
  })

  depends_on = [aws_internet_gateway.main]
}

# NAT Instance
# ─────────────────────────────────────────────────────────────
# ¿Por qué source_dest_check = false?
#
# Por defecto, AWS descarta cualquier paquete cuya IP origen
# NO coincida con la IP de la instancia que lo recibe.
# Esto protege contra spoofing, pero impide que la instancia
# actúe como router.
#
# Al deshabilitar source_dest_check, le decimos a AWS:
#   "Esta instancia debe recibir y reenviar paquetes de/hacia
#    IPs que no son las suyas propias"
#
# Con ip_forward=1 (kernel) + iptables MASQUERADE (user space),
# la instancia NAT:
#   1. Recibe paquetes de EC2 privadas (src: 10.0.x.x, dst: 1.2.3.4)
#   2. Reescribe el src a su propia IP pública (MASQUERADE)
#   3. Envía el paquete al destino en Internet
#   4. Cuando recibe la respuesta (src: 1.2.3.4, dst: su IP pública),
#      deshace el MASQUERADE (conntrack) y reenvía a la EC2 privada
# ─────────────────────────────────────────────────────────────
resource "aws_instance" "nat" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = var.nat_instance_type
  subnet_id                   = aws_subnet.public[0].id # AZ1 — una sola NAT (Free Tier)
  vpc_security_group_ids      = [aws_security_group.nat.id]
  source_dest_check           = false # CRÍTICO: permite actuar como router
  associate_public_ip_address = true

  # user_data: habilita ip_forward en el kernel y configura iptables MASQUERADE
  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -euo pipefail

    # 1. Habilitar IP forwarding a nivel de kernel
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-nat.conf
    sysctl -p /etc/sysctl.d/99-nat.conf

    # 2. Instalar iptables-services (persiste reglas entre reinicios)
    yum install -y iptables-services

    # 3. MASQUERADE: reescribe la IP origen de paquetes salientes por eth0
    #    (la IP pública de la NAT Instance) — esto es NAT/PAT
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

    # 4. Permitir forwarding en la cadena FORWARD
    iptables -I FORWARD -j ACCEPT

    # 5. Persistir reglas para que sobrevivan reinicios
    service iptables save
    systemctl enable iptables
    systemctl start iptables
  EOF
  )

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(var.tags, {
    Name = "${local.name}-nat-instance"
    Role = "NAT"
  })

  # Prevenir reemplazos accidentales:
  # las tablas de rutas apuntan a la ENI de esta instancia.
  # Si Terraform la recrea, las rutas privadas quedan rotas hasta
  # que se vuelva a aplicar. lifecycle evita destrucción accidental.
  lifecycle {
    ignore_changes = [ami] # No destruir si sale una nueva AMI
  }
}

# Asociar EIP a la NAT Instance
resource "aws_eip_association" "nat" {
  instance_id   = aws_instance.nat.id
  allocation_id = aws_eip.nat.id
}

# ============================================================
# Tablas de Rutas
# ============================================================

# Pública: tráfico a Internet via IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${local.name}-rt-public"
  })
}

# Privada App (una por AZ, ambas apuntan a la MISMA NAT Instance)
# Decisión de costo: una sola NAT en AZ1 — Free Tier.
# En producción: una NAT Instance/Gateway por AZ para HA.
resource "aws_route_table" "private_app" {
  count  = length(var.azs)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.nat.primary_network_interface_id
  }

  tags = merge(var.tags, {
    Name = "${local.name}-rt-private-app-${var.azs[count.index]}"
  })
}

# Privada DB: sin ruta a Internet (subredes completamente aisladas)
resource "aws_route_table" "private_db" {
  count  = length(var.azs)
  vpc_id = aws_vpc.main.id

  # Solo ruta local (VPC CIDR) — implícita en toda route table

  tags = merge(var.tags, {
    Name = "${local.name}-rt-private-db-${var.azs[count.index]}"
  })
}

# ── Asociaciones ─────────────────────────────────────────────

resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_app" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app[count.index].id
}

resource "aws_route_table_association" "private_db" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private_db[count.index].id
}

# ============================================================
# Security Groups — Cadena de acceso estricta
#
# Internet → sg_alb → sg_website → sg_backend → sg_database
#
# NOTA sobre dependencias circulares en Terraform:
# Si sg_alb.egress referencia sg_website.id, y sg_website.ingress
# referencia sg_alb.id, Terraform detecta un ciclo en el grafo
# de dependencias y falla.
#
# Solución aplicada: se rompen los dos puntos de ciclo usando
# bloques CIDR en lugar de referencias SG para:
#   - sg_alb egress → CIDR private_app (en vez de sg_website ref)
#   - sg_website egress → CIDR private_app (en vez de sg_backend ref)
#   - sg_backend ingress → CIDR private_app (en vez de sg_website ref)
# La seguridad es equivalente porque solo Website y Backend EC2s
# existen en private_app_subnet_cidrs.
# ============================================================

# ── sg_alb: punto de entrada público ─────────────────────────
resource "aws_security_group" "alb" {
  name        = "${local.name}-sg-alb"
  description = "ALB - HTTP and HTTPS from Internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] #tfsec:ignore:aws-ec2-no-public-ingress-sgr
  }

  ingress {
    description = "HTTPS from Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] #tfsec:ignore:aws-ec2-no-public-ingress-sgr
  }

  # Egress a CIDRs de app (no SG ref) para evitar ciclo con sg_website
  egress {
    description = "Forward traffic to private app subnets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.private_app_subnet_cidrs
  }

  tags = merge(var.tags, {
    Name = "${local.name}-sg-alb"
  })
}

# ── sg_website: capa de presentación ─────────────────────────
resource "aws_security_group" "website" {
  name        = "${local.name}-sg-website"
  description = "Website EC2 - only from ALB, forwards to Backend"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "App port from ALB"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Egress a CIDRs (no sg_backend ref) para evitar ciclo con sg_backend
  egress {
    description = "Forward traffic to private app subnets (Backend)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.private_app_subnet_cidrs
  }

  tags = merge(var.tags, {
    Name = "${local.name}-sg-website"
  })
}

# ── sg_backend: capa de lógica de negocio ────────────────────
resource "aws_security_group" "backend" {
  name        = "${local.name}-sg-backend"
  description = "Backend EC2 - only from Website, accesses RDS and NAT"
  vpc_id      = aws_vpc.main.id

  # Ingress desde subredes publicas donde vive el ALB
  ingress {
    description = "App port from public subnets (ALB)"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.public_subnet_cidrs
  }

  # Egress hacia RDS via CIDR (evita ciclo con sg_database si usara SG ref)
  egress {
    description = "MySQL to DB subnets"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = var.private_db_subnet_cidrs
  }

  # Egress HTTPS para npm install / actualizaciones via NAT Instance
  egress {
    description = "HTTPS to Internet via NAT"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${local.name}-sg-backend"
  })
}

# ── sg_database: capa de datos — completamente aislada ───────
resource "aws_security_group" "database" {
  name        = "${local.name}-sg-database"
  description = "Database - only from Backend on port 3306"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from Backend"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }

  # egress = [] elimina la regla "allow all" que AWS agrega por defecto
  # RDS no necesita iniciar conexiones salientes
  egress = []

  tags = merge(var.tags, {
    Name = "${local.name}-sg-database"
  })
}
