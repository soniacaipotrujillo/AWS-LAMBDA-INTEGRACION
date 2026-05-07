# storage_messaging.tf

# ==========================================
# 1. BUCKET S3 (El disco duro)
# ==========================================
resource "aws_s3_bucket" "images" {
  bucket        = "image-processor-${var.environment}-images-${var.developer_suffix}"
  force_destroy = true
}

# Encriptación por defecto (AES-256)
resource "aws_s3_bucket_server_side_encryption_configuration" "images_encryption" {
  bucket = aws_s3_bucket.images.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Ciclo de vida (30/90 días)
resource "aws_s3_bucket_lifecycle_configuration" "images_lifecycle" {
  bucket = aws_s3_bucket.images.id

  rule {
    id     = "transition-and-expiration"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 90
    }
  }
}

# ==========================================
# 2. COLAS SQS (Los mensajeros)
# ==========================================
# Cola principal
resource "aws_sqs_queue" "main_queue" {
  name                       = "image-processing-queue-${var.environment}"
  visibility_timeout_seconds = 60

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

# Cola de mensajes muertos (DLQ)
resource "aws_sqs_queue" "dlq" {
  name = "image-processing-dlq-${var.environment}"
}

# Permiso para que S3 pueda escribir en la cola SQS principal
resource "aws_sqs_queue_policy" "s3_to_sqs" {
  queue_url = aws_sqs_queue.main_queue.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.main_queue.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.images.arn
          }
        }
      }
    ]
  })
}

# ==========================================
# 3. NOTIFICACIONES (S3 avisa a SQS)
# ==========================================
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.images.id

  queue {
    queue_arn     = aws_sqs_queue.main_queue.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "uploads/"
    filter_suffix = ".png"
  }

  depends_on = [aws_sqs_queue_policy.s3_to_sqs]
}