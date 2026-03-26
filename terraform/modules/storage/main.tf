# ============================================================
# storage/main.tf
#
# Recursos:
#   - S3 bucket privado para el frontend estático (React/Vite)
#   - CloudFront Origin Access Control (OAC) — NO el OAI legacy
#   - CloudFront Distribution con cache diferenciado por ruta
#   - Bucket policy: solo permite GetObject desde el OAC de CloudFront
#
# Flujo de una petición:
#   Browser → CloudFront Edge (cache hit: responde)
#                             (cache miss) → S3 [via OAC] → responde
#
# OAC vs OAI:
#   OAI (legacy): CloudFront firma peticiones con un "identity" de IAM.
#   OAC (actual): CloudFront firma las peticiones con SigV4 usando
#   su propio service principal (cloudfront.amazonaws.com).
#   OAC es más seguro, soporta SSE-KMS y es el estándar recomendado por AWS.
# ============================================================

locals {
  name = var.project_name
}

# Account ID para hacer el bucket name globalmente único
data "aws_caller_identity" "current" {}

# ============================================================
# S3 Bucket — almacenamiento privado del frontend
# ============================================================
resource "aws_s3_bucket" "frontend" {
  # Account ID en el nombre garantiza unicidad global del bucket
  bucket        = "${local.name}-frontend-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # Permite destruir aunque tenga objetos (terraform destroy)

  tags = merge(var.tags, {
    Name = "${local.name}-frontend"
  })
}

# Versionado: permite recuperar versiones anteriores del build si hay un deploy roto
resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Bloquear TODO acceso público — el bucket NUNCA debe ser accesible directamente
# Solo CloudFront (via OAC) puede leer objetos
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# Cifrado en reposo (AES-256, sin costo adicional)
resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ============================================================
# CloudFront Origin Access Control (OAC)
# ============================================================
# OAC permite a CloudFront autenticarse contra S3 usando SigV4.
# La petición llega a S3 con una firma válida de CloudFront —
# S3 verifica la firma contra la política de bucket y permite
# el acceso solo si viene de ESTA distribución concreta.
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${local.name}-oac-frontend"
  description                       = "OAC para bucket S3 del frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"   # Siempre firma las peticiones a S3
  signing_protocol                  = "sigv4"    # AWS Signature Version 4
}

# ============================================================
# CloudFront Distribution
# ============================================================
resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = var.cloudfront_price_class
  comment             = "${local.name} frontend SPA"

  # ── Origen: S3 bucket (acceso via OAC) ───────────────────────
  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.frontend.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # ── Cache behavior para assets estáticos (/assets/*) ─────────
  # Los assets de Vite incluyen hash en el nombre (main.abc123.js),
  # por lo que son inmutables → 1 año de TTL es seguro.
  ordered_cache_behavior {
    path_pattern           = "/assets/*"
    target_origin_id       = "S3-${aws_s3_bucket.frontend.id}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 31536000 # 1 año
    max_ttl     = 31536000 # 1 año
  }

  # ── Cache behavior por defecto (HTML, manifest, etc.) ────────
  # index.html NO debe cachearse agresivamente porque cambia con
  # cada deploy (aunque el hash del bundle sea diferente).
  default_cache_behavior {
    target_origin_id       = "S3-${aws_s3_bucket.frontend.id}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 300 # 5 minutos
    max_ttl     = 300 # 5 minutos
  }

  # ── SPA: redirigir errores 403/404 a index.html ──────────────
  # Cuando el usuario recarga en /clientes o /turnos, CloudFront
  # busca ese path en S3 (no existe), S3 retorna 403 (bucket privado).
  # Redirigimos al index.html para que React Router tome el control.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Certificado por defecto de CloudFront (*.cloudfront.net)
  # Para dominio personalizado: añadir aliases y certificado ACM us-east-1
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = merge(var.tags, {
    Name = "${local.name}-cloudfront"
  })

  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

# ============================================================
# Bucket Policy — solo CloudFront OAC puede leer objetos
# ============================================================
# La condición aws:SourceArn restringe el acceso al ARN exacto
# de ESTA distribución. Si alguien crea otra distribución que
# apunte al mismo bucket, no tendrá acceso.
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn
          }
        }
      }
    ]
  })

  # La política referencia la distribución — esperar a que exista
  depends_on = [
    aws_cloudfront_distribution.frontend,
    aws_s3_bucket_public_access_block.frontend
  ]
}
