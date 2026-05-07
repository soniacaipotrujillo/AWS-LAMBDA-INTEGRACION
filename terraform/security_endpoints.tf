# security_endpoints.tf


# Portero para la Lambda de Subida (Upload)
resource "aws_security_group" "sg_upload_lambda" {
  name = "upload-lambda-sg-${var.environment}"
  description = "Security Group para la Lambda que sube imagenes"
  vpc_id      = aws_vpc.main.id

  # Outbound (Salida): Le permitimos salir por el puerto 443 (HTTPS seguro) para usar los túneles
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { name = "upload-lambda-sg-${var.environment}" }
}

# Portero para la Lambda de Recorte (Crop)
resource "aws_security_group" "sg_crop_lambda" {
  name        = "crop-lambda-sg-${var.environment}"
  description = "Security Group para la Lambda que recorta imagenes"
  vpc_id      = aws_vpc.main.id

  # Outbound (Salida): Le permitimos salir por el puerto 443 (HTTPS seguro)
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { name = "crop-lambda-sg-${var.environment}" }
}

# Portero para el Túnel secreto de SQS
resource "aws_security_group" "sg_vpce_sqs" {
  name = "vpce-sqs-sg-${var.environment}"
  description = "Security Group para el VPC Endpoint de SQS"
  vpc_id      = aws_vpc.main.id

  # Inbound (Entrada): Solo dejamos entrar al túnel a quienes vengan de las Lambdas Upload y Crop
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [
      aws_security_group.sg_upload_lambda.id, 
      aws_security_group.sg_crop_lambda.id
    ]
  }

  tags = { name = "vpce-sqs-sg-${var.environment}" }
}



# Túnel Tipo "Gateway" para S3 (Este túnel se agrega a los mapas de las rutas privadas)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  # Conectamos el túnel a nuestros cuartos privados A y B
  route_table_ids = [
    aws_route_table.private_a.id,
    aws_route_table.private_b.id
  ]


  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject", "s3:PutObject"]
        Resource  = [
          aws_s3_bucket.images.arn,
          "${aws_s3_bucket.images.arn}/*"
        ]
      }
    ]
  })

  tags = { Name = "vpce-s3-${var.environment}" }
}


resource "aws_vpc_endpoint" "sqs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.sqs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true # Requisito del diagrama

  # Instalamos el túnel directamente en las subredes privadas
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  # Le asignamos su guardia de seguridad
  security_group_ids = [aws_security_group.sg_vpce_sqs.id]

  tags = { Name = "vpce-sqs-${var.environment}" }
}