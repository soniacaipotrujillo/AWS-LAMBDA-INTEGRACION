# storage_messaging.tf



# DLQ (Dead-Letter Queue): La "cápsula de rescate" para mensajes que fallan
resource "aws_sqs_queue" "dlq" {
  name                      = "image-processor-${var.environment}-image-dlq"
  message_retention_seconds = 1209600 # 14 días de retención (según el diagrama)
}

# Cola Principal: Donde llegan los avisos de nuevas imágenes
resource "aws_sqs_queue" "main_queue" {
  name                       = "image-processor-${var.environment}-image-queue"
  visibility_timeout_seconds = 360   # 360s (6 veces el timeout de la Lambda, según diagrama)
  message_retention_seconds  = 86400 # 1 día de retención
  receive_wait_time_seconds  = 20    # Long polling de 20s
  
  # Si un mensaje falla 3 veces, lo mandamos a la DLQ
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

# Permiso para que S3 pueda "escribir" mensajes en la cola principal SQS
resource "aws_sqs_queue_policy" "main_queue_policy" {
  queue_url = aws_sqs_queue.main_queue.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.main_queue.arn
        Condition = {
          ArnEquals = { "aws:SourceArn" = aws_s3_bucket.images.arn }
        }
      }
    ]
  })
}



# El Bucket principal (Aquí usaremos tu variable con el sufijo "pals")
resource "aws_s3_bucket" "images" {
  bucket = "image-processor-${var.environment}-images-${var.bucket_suffix}"
}

# Bloquear todo el acceso público (Access: fully private)
resource "aws_s3_bucket_public_access_block" "images_private" {
  bucket                  = aws_s3_bucket.images.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Activar el versionado de archivos
resource "aws_s3_bucket_versioning" "images_versioning" {
  bucket = aws_s3_bucket.images.id
  versioning_configuration { status = "Enabled" }
}

# Cifrado SSE AES-256 (Requisito del diagrama)
resource "aws_s3_bucket_server_side_encryption_configuration" "images_encryption" {
  bucket = aws_s3_bucket.images.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Reglas de Ciclo de Vida (Lifecycle: expirar archivos viejos para ahorrar costos)
resource "aws_s3_bucket_lifecycle_configuration" "images_lifecycle" {
  bucket = aws_s3_bucket.images.id

  rule {
    id     = "expire-uploads"
    status = "Enabled"
    filter { prefix = "uploads/" }
    expiration { days = 30 }
  }

  rule {
    id     = "expire-processed"
    status = "Enabled"
    filter { prefix = "processed/" }
    expiration { days = 90 }
  }
}



# Le decimos a S3: "Cada vez que se cree un objeto en la carpeta uploads/, avisa a la cola SQS"
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.images.id

  queue {
    queue_arn     = aws_sqs_queue.main_queue.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "uploads/"
  }
  
  # Terraform debe esperar a que la política exista antes de crear esta notificación
  depends_on = [aws_sqs_queue_policy.main_queue_policy]
}