# ============================================================
# compute/outputs.tf
# ============================================================

output "alb_dns_name" {
  description = "DNS público del ALB — apuntar el CNAME de Cloudflare aquí"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "ARN del Application Load Balancer"
  value       = aws_lb.main.arn
}

output "alb_zone_id" {
  description = "Hosted Zone ID del ALB (para Route53 alias records)"
  value       = aws_lb.main.zone_id
}

output "target_group_arn" {
  description = "ARN del Target Group del Backend"
  value       = aws_lb_target_group.backend.arn
}

output "asg_name" {
  description = "Nombre del Auto Scaling Group"
  value       = aws_autoscaling_group.backend.name
}

output "launch_template_id" {
  description = "ID del Launch Template"
  value       = aws_launch_template.backend.id
}

output "backend_iam_role_arn" {
  description = "ARN del IAM Role de las instancias Backend"
  value       = aws_iam_role.backend.arn
}
