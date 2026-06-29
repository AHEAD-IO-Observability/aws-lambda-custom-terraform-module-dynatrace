output "function_name" {
  description = "Name of the instrumented Lambda function."
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN of the instrumented Lambda function."
  value       = aws_lambda_function.this.arn
}

output "function_qualified_arn" {
  description = "Qualified (versioned) ARN of the function."
  value       = aws_lambda_function.this.qualified_arn
}

output "function_invoke_arn" {
  description = "Invoke ARN of the function (for API Gateway / EventBridge integrations)."
  value       = aws_lambda_function.this.invoke_arn
}

output "environment_variables" {
  description = "Environment variables applied to the function (Dynatrace-managed merged with caller overrides). Token values are not included unless passed in plaintext."
  value       = local.environment_variables
  sensitive   = true
}

output "execution_role_arn" {
  description = "ARN of the Lambda execution role (created or supplied)."
  value       = local.execution_role_arn
}

output "execution_role_name" {
  description = "Name of the created execution role, or null when an existing role ARN was supplied."
  value       = var.create_execution_role ? aws_iam_role.exec[0].name : null
}

output "connection_auth_token_secret_arn" {
  description = "ARN of the connection (trace) token secret in use, or empty when a plaintext token / no secret is used. Write the trace-ingest token here out-of-band."
  value       = local.use_connection_secret ? local.connection_secret_arn : ""
}

output "connection_auth_token_secret_name" {
  description = "Name of the created connection-token secret, or null when not created here."
  value       = var.create_connection_auth_token_secret ? aws_secretsmanager_secret.connection_auth_token[0].name : null
}

output "log_collection_enabled" {
  description = "Whether a log-collection token was configured (DT_LOG_COLLECTION_AUTH_TOKEN set)."
  value       = nonsensitive(var.log_collection_auth_token != "")
}

output "dynatrace_layer_arn" {
  description = "Dynatrace OneAgent layer ARN attached to the function."
  value       = var.dynatrace_layer_arn
}
