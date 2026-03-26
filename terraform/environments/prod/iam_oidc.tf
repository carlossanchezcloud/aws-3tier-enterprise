# ============================================================
# iam_oidc.tf
#
# IAM OIDC para GitHub Actions — autenticación sin claves estáticas
#
# Flujo:
#   1. GitHub Actions genera un JWT token firmado por GitHub
#   2. AWS valida el JWT contra el OIDC provider configurado aquí
#   3. Si la validación pasa (repo correcto), AWS emite credenciales
#      temporales via STS:AssumeRoleWithWebIdentity
#   4. El workflow opera con esas credenciales temporales (~1h TTL)
#
# Ventaja: CERO secretos de larga duración en GitHub Secrets.
# ============================================================

# ── OIDC Provider de GitHub Actions ──────────────────────────
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  # sts.amazonaws.com es la audiencia que GitHub incluye en sus JWTs
  client_id_list = ["sts.amazonaws.com"]

  # Thumbprint del certificado TLS raíz de token.actions.githubusercontent.com
  # Verificado en: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc_verify-thumbprint.html
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Name = "${var.project_name}-github-oidc-provider"
  }
}

# ── IAM Role que asumen los workflows de GitHub Actions ──────
resource "aws_iam_role" "github_actions" {
  name        = "${var.project_name}-github-actions-role"
  description = "Rol asumido por GitHub Actions via OIDC para deployments"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GitHubActionsOIDC"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            # Solo tokens con audiencia sts.amazonaws.com
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # Solo el repo específico (cualquier rama/entorno)
            # Para restringir a main: "repo:carlossanchezcloud/aws-3tier-enterprise:ref:refs/heads/main"
            "token.actions.githubusercontent.com:sub" = "repo:carlossanchezcloud/aws-3tier-enterprise:*"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-github-actions-role"
  }
}

# ── Política Least Privilege para el Role ────────────────────
# Solo los permisos necesarios para los workflows de CI/CD:
#   - infra.yml: terraform plan (solo lectura de infraestructura)
#   - app.yml: deploy frontend (S3 sync + CloudFront invalidation)
resource "aws_iam_policy" "github_actions" {
  name        = "${var.project_name}-github-actions-policy"
  description = "Permisos mínimos para workflows GitHub Actions (deploy frontend + tf plan)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3FrontendDeploy"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetObject",
          "s3:GetBucketLocation"
        ]
        # Se restringe al bucket del frontend — valor interpolado en Fase 3
        Resource = [
          "arn:aws:s3:::${var.project_name}-frontend-*",
          "arn:aws:s3:::${var.project_name}-frontend-*/*"
        ]
      },
      {
        Sid    = "CloudFrontInvalidation"
        Effect = "Allow"
        Action = [
          "cloudfront:CreateInvalidation",
          "cloudfront:GetInvalidation",
          "cloudfront:ListInvalidations"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2ReadOnly"
        Effect = "Allow"
        Action = [
          "ec2:Describe*"
        ]
        Resource = "*"
      },
      {
        Sid    = "TerraformStateRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::aws-3tier-appcitas-tfstate",
          "arn:aws:s3:::aws-3tier-appcitas-tfstate/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions.arn
}

# ── Outputs ───────────────────────────────────────────────────
output "github_actions_role_arn" {
  description = "ARN del rol IAM para GitHub Actions — usar en workflows como role-to-assume"
  value       = aws_iam_role.github_actions.arn
}
