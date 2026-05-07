# api_gateway.tf


# 1. La BITÁCORA DE LA VENTANILLA (Logs)

resource "aws_cloudwatch_log_group" "api_gw_logs" {
  name              = "/aws/apigateway/image-processor-api-${var.environment}"
  retention_in_days = 14
}


# 2. La VENTANILLA (HTTP API v2)

resource "aws_apigatewayv2_api" "http_api" {
  name          = "image-processor-api-${var.environment}"
  protocol_type = "HTTP"
  
  # CORS habilitado (Requisito del diagrama)
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["content-type"]
  }
}

# Escenario por defecto (Stage: default, auto-deploy)
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true

  # Guardar accesos en formato JSON
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw_logs.arn
    format          = jsonencode({
      requestId      = "$context.requestId"
      sourceIp       = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
    })
  }
  
  # Throttling: 10,000 rps (Requisito del diagrama)
  default_route_settings {
    throttling_burst_limit = 10000
    throttling_rate_limit  = 10000
  }
}


# 3. CONECTAR VENTANILLA CON LAMBDA

# Le decimos a la API que se comunique con la Lambda Upload (Payload 2.0)
resource "aws_apigatewayv2_integration" "lambda_upload" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.upload_lambda.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# Creamos la ruta específica: POST /upload
resource "aws_apigatewayv2_route" "post_upload" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /upload"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_upload.id}"
}


# 4. PERMISOS

# Le damos permiso al guardia para que la Ventanilla pueda despertar a la Lambda
resource "aws_lambda_permission" "api_gw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}


# 5. SALIDA (OUTPUT)

# Esto imprimirá la URL en la pantalla al final para que puedas probarla con el comando 'curl' de tu compañero
output "api_url" {
  value       = "${aws_apigatewayv2_api.http_api.api_endpoint}/upload"
  description = "La URL publica para subir tus imagenes"
}