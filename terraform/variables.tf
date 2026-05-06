# variables.tf

variable "aws_region" {
  description = "La region de AWS donde se desplegara todo"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "El entorno actual (dev, qa, prod)"
  type        = string
}

variable "bucket_suffix" {
  description = "Sufijo unico para el bucket S3 (los nombres en S3 deben ser unicos a nivel mundial)"
  type        = string
}