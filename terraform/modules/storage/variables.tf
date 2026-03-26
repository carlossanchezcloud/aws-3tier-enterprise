# ============================================================
# storage/variables.tf
# ============================================================

variable "project_name" {
  description = "Prefijo para el nombre de todos los recursos"
  type        = string
  default     = "aws-3tier"
}

variable "cloudfront_price_class" {
  description = "Clase de precio CloudFront (PriceClass_100 = US/EU/Asia — más económico)"
  type        = string
  default     = "PriceClass_100"
}

variable "tags" {
  description = "Tags comunes aplicados a todos los recursos"
  type        = map(string)
  default     = {}
}
