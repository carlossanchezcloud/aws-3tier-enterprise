# ============================================================
# compute/main.tf
#
# Recursos:
#   - AMI data source (Amazon Linux 2023, última disponible)
#   - IAM Role + Instance Profile (AmazonSSMManagedInstanceCore)
#   - Application Load Balancer (subredes públicas)
#   - Target Group (HTTP :3000, health check /health)
#   - Listener ALB HTTP:80 → Target Group
#   - Launch Template (AL2023, t3.micro, IMDSv2, EBS 30GB gp3 cifrado)
#   - Auto Scaling Group (min=2, max=4, desired=2)
#   - CPU Target Tracking Scaling Policy (umbral 70%)
# ============================================================

locals {
  name = var.project_name
}

# ============================================================
# AMI — Amazon Linux 2023 (última versión disponible)
# ============================================================
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
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

# ============================================================
# IAM — Acceso por SSM (sin llaves SSH, sin puerto 22)
# ============================================================

# Role que asumen las instancias EC2
resource "aws_iam_role" "backend" {
  name        = "${local.name}-backend-role"
  description = "Role para EC2 Backend: acceso SSM + S3 artifacts"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, {
    Name = "${local.name}-backend-role"
  })
}

# AmazonSSMManagedInstanceCore: permite sesiones SSM desde consola AWS
# sin necesidad de abrir puerto 22 ni gestionar llaves SSH
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.backend.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "backend" {
  name = "${local.name}-backend-profile"
  role = aws_iam_role.backend.name

  tags = merge(var.tags, {
    Name = "${local.name}-backend-profile"
  })
}

# ============================================================
# ALB — Application Load Balancer (subredes públicas)
# ============================================================
resource "aws_lb" "main" {
  name               = "${local.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.sg_alb_id]
  subnets            = var.public_subnet_ids

  # Protección contra borrado accidental
  enable_deletion_protection = false

  # Access logs deshabilitados para Free Tier (S3 tiene costo)
  # Para producción: habilitar y especificar bucket

  tags = merge(var.tags, {
    Name = "${local.name}-alb"
  })
}

# ── Target Group ─────────────────────────────────────────────
resource "aws_lb_target_group" "backend" {
  name     = "${local.name}-tg-backend"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  # Deregistration delay: tiempo que el ALB espera antes de quitar
  # la instancia del target group (permite drenar conexiones activas)
  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = merge(var.tags, {
    Name = "${local.name}-tg-backend"
  })
}

# ── Listener HTTP:80 → Target Group ──────────────────────────
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  tags = merge(var.tags, {
    Name = "${local.name}-listener-http"
  })
}

# ============================================================
# Launch Template
# ============================================================
resource "aws_launch_template" "backend" {
  name_prefix   = "${local.name}-lt-backend-"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.instance_type

  # IAM Instance Profile — permite SSM y acceso a S3
  iam_instance_profile {
    name = aws_iam_instance_profile.backend.name
  }

  # ── IMDSv2 Obligatorio ──────────────────────────────────────
  # IMDSv2 requiere un token para acceder a los metadatos de la instancia.
  # Protege contra ataques SSRF donde código malicioso intenta leer
  # credenciales del endpoint 169.254.169.254.
  # http_tokens = "required" rechaza peticiones sin token (IMDSv1 deshabilitado).
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 obligatorio
    http_put_response_hop_limit = 1          # Solo accesible desde la instancia
  }

  # ── EBS Raíz ─────────────────────────────────────────────────
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.ebs_volume_size_gb
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # Security Group — sg_backend (acepta tráfico de Website, sale a RDS y npm)
  vpc_security_group_ids = [var.sg_backend_id]

  # ── user_data via templatefile() ─────────────────────────────
  # templatefile() sustituye las variables ${rds_endpoint}, ${db_password},
  # ${aws_region} en el script antes de pasarlo a la instancia.
  # base64encode() es necesario porque Launch Template espera el user_data
  # en base64.
  user_data = base64encode(templatefile("${path.module}/../../../scripts/user_data.sh", {
    rds_endpoint = var.rds_endpoint
    db_password  = var.db_password
    aws_region   = var.aws_region
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${local.name}-backend"
      Role = "Backend"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name = "${local.name}-backend-ebs"
    })
  }

  lifecycle {
    # Crear nueva versión del LT antes de destruir la actual
    # (el ASG puede seguir usando la versión anterior durante el reemplazo)
    create_before_destroy = true
  }
}

# ============================================================
# Auto Scaling Group
# ============================================================
resource "aws_autoscaling_group" "backend" {
  name = "${local.name}-asg-backend"

  # Distribución: una instancia por AZ (desired=2 con 2 AZs)
  vpc_zone_identifier = var.private_app_subnet_ids
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_desired_capacity

  # Target Group: el ALB registra/desregistra instancias automáticamente
  target_group_arns = [aws_lb_target_group.backend.arn]

  # Health check via ELB (usa el health check del Target Group)
  # Más preciso que EC2 health check porque valida que la app responde
  health_check_type         = "ELB"
  health_check_grace_period = 300 # 5 min para que la instancia arranque

  launch_template {
    id      = aws_launch_template.backend.id
    version = "$Latest"
  }

  # Rolling deployment: reemplaza instancias una a una durante actualizaciones
  # min_healthy_percentage=50 garantiza que al menos 1 instancia esté up
  # mientras la otra se reemplaza.
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 300
    }
    triggers = ["launch_template"]
  }

  tag {
    key                 = "Name"
    value               = "${local.name}-backend"
    propagate_at_launch = true
  }

  lifecycle {
    # Evitar que Terraform destruya instancias que el ASG gestiona
    ignore_changes = [desired_capacity]
  }
}

# ── CPU Target Tracking Scaling ───────────────────────────────
# Escala automáticamente cuando el CPU promedio supera el 70%.
# Target Tracking ajusta el desired_capacity para mantener el
# CPU cerca del target (escala hacia arriba y hacia abajo).
resource "aws_autoscaling_policy" "cpu_tracking" {
  name                   = "${local.name}-cpu-tracking"
  autoscaling_group_name = aws_autoscaling_group.backend.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value     = 70.0
    disable_scale_in = false
  }
}
