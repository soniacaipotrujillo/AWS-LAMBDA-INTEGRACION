# compute_observability.tf


# 1. CLOUDWATCH (Cámaras, Bitácoras y Alarmas)


# Bitácora para la Lambda Upload (Retención de 14 días según diagrama)
resource "aws_cloudwatch_log_group" "upload_log_group" {
  name              = "/aws/lambda/upload-lambda-${var.environment}"
  retention_in_days = 14
}

# Bitácora para la Lambda Crop (Retención de 14 días)
resource "aws_cloudwatch_log_group" "crop_log_group" {
  name              = "/aws/lambda/crop-lambda-${var.environment}"
  retention_in_days = 14
}

# SNS Topic (El "Megáfono" que usa la alarma para avisar que algo falló)
resource "aws_sns_topic" "alarm_topic" {
  name = "dlq-alarm-topic-${var.environment}"
}

# Alarma de CloudWatch: "dlq-messages-alarm"
resource "aws_cloudwatch_metric_alarm" "dlq_alarm" {
  alarm_name          = "dlq-messages-alarm-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0 # Si hay más de 0 mensajes visibles, suena la alarma
  alarm_description   = "Alarma disparada si caen mensajes a la DLQ"
  alarm_actions       = [aws_sns_topic.alarm_topic.arn]
  
  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }
}


# 2. LAMBDAS (Los Trabajadores)


# TRUCO: Creamos un archivo ZIP temporal y vacío para que Terraform no dé error
data "archive_file" "dummy_lambda" {
  type        = "zip"
  output_path = "${path.module}/dummy.zip"
  source {
    content  = "exports.handler = async (event) => { return 'Hola, soy de mentira'; };"
    filename = "index.js"
  }
}

# Trabajador 1: Upload Lambda
resource "aws_lambda_function" "upload_lambda" {
  function_name = "upload-lambda-${var.environment}"
  role          = aws_iam_role.role_upload.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  memory_size   = 256 # Memoria según diagrama
  timeout       = 30  # Timeout según diagrama

  # Usamos el ZIP temporal por ahora
  filename         = data.archive_file.dummy_lambda.output_path
  source_code_hash = data.archive_file.dummy_lambda.output_base64sha256

  # Lo metemos a la VPC (Cuartos secretos y Porteros)
  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.sg_upload_lambda.id]
  }

  # Le damos variables de entorno (Instrucciones)
  environment {
    variables = {
      S3_BUCKET     = aws_s3_bucket.images.bucket
      UPLOAD_PREFIX = "uploads/"
    }
  }

  depends_on = [aws_cloudwatch_log_group.upload_log_group]
}

# Trabajador 2: Crop Lambda
resource "aws_lambda_function" "crop_lambda" {
  function_name = "crop-lambda-${var.environment}"
  role          = aws_iam_role.role_crop.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  memory_size   = 512 # Memoria mayor porque procesar imágenes pesa
  timeout       = 60

  filename         = data.archive_file.dummy_lambda.output_path
  source_code_hash = data.archive_file.dummy_lambda.output_base64sha256

  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.sg_crop_lambda.id]
  }

  environment {
    variables = {
      S3_BUCKET        = aws_s3_bucket.images.bucket
      PROCESSED_PREFIX = "processed/"
    }
  }

  depends_on = [aws_cloudwatch_log_group.crop_log_group]
}


# 3. CONEXIÓN SQS -> LAMBDA CROP

# Le decimos a la Lambda Crop: "Saca mensajes de la cola SQS de 5 en 5"
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn        = aws_sqs_queue.main_queue.arn
  function_name           = aws_lambda_function.crop_lambda.arn
  batch_size              = 5
  function_response_types = ["ReportBatchItemFailures"]
}