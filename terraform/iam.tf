# iam.tf


# 1. POLÍTICA DE CONFIANZA (¿Quién puede usar el gafete?)

# Le decimos a AWS que solo los servicios "Lambda" pueden ponerse estos gafetes.
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}


# 2. GAFETE PARA LA LAMBDA DE SUBIDA (Upload)

resource "aws_iam_role" "role_upload" {
  name               = "upload-lambda-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# Permisos básicos de AWS para la Lambda Upload (Escribir logs y conectarse a la red/VPC)
resource "aws_iam_role_policy_attachment" "upload_basic_logs" {
  role       = aws_iam_role.role_upload.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "upload_vpc_access" {
  role       = aws_iam_role.role_upload.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Permiso específico: Solo guardar fotos nuevas en la carpeta "uploads/"
resource "aws_iam_role_policy" "policy_upload_s3" {
  name = "s3-upload-policy-${var.environment}"
  role = aws_iam_role.role_upload.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.images.arn}/uploads/*"
      }
    ]
  })
}


# 3. GAFETE PARA LA LAMBDA DE RECORTE (Crop)

resource "aws_iam_role" "role_crop" {
  name               = "crop-lambda-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# Permisos básicos de AWS para la Lambda Crop (Escribir logs y conectarse a la red/VPC)
resource "aws_iam_role_policy_attachment" "crop_basic_logs" {
  role       = aws_iam_role.role_crop.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "crop_vpc_access" {
  role       = aws_iam_role.role_crop.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Permisos específicos: Leer de "uploads/", Guardar en "processed/" y manejar la fila SQS
resource "aws_iam_role_policy" "policy_crop_s3_sqs" {
  name = "s3-sqs-crop-policy-${var.environment}"
  role = aws_iam_role.role_crop.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Permiso: Solo leer fotos originales
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.images.arn}/uploads/*"
      },
      {
        # Permiso: Solo guardar fotos procesadas
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.images.arn}/processed/*"
      },
      {
        # Permisos: Atender mensajes de la cola SQS
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = aws_sqs_queue.main_queue.arn
      }
    ]
  })
}