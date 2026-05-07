variable "aws_region" {
  description = "La region donde se crearan los recursos"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "El entorno actual (dev, qa, prod)"
  type        = string
}

variable "developer_suffix" {
  description = "Tus iniciales o alias para que los nombres sean unicos (ej. pals)"
  type        = string
}