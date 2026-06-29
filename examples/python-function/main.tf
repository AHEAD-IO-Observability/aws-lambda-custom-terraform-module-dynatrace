variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "function_name" {
  type    = string
  default = "dynatrace-instrumented-demo"
}

variable "runtime" {
  type    = string
  default = "python3.13"
}

variable "dynatrace_layer_arn" {
  description = "Dynatrace OneAgent layer ARN (with-collector variant) for this region/runtime/arch."
  type        = string
}

variable "dt_tenant" {
  type = string
}

variable "dt_cluster" {
  type = string
}

variable "dt_connection_base_url" {
  type = string
}

# Optional: enable log collection (required by the with-collector layer to fully
# start its collector). Leave empty to deploy trace-only (use a without-collector layer).
variable "log_collection_auth_token" {
  type      = string
  default   = ""
  sensitive = true
}

variable "auth_token_secret_recovery_window_in_days" {
  description = "0 for immediate deletion on destroy (lab); 7-30 for production."
  type        = number
  default     = 0
}

variable "tags" {
  type = map(string)
  default = {
    managed-by = "terraform"
    purpose    = "dynatrace-lambda-instrumentation"
  }
}

# Package the unchanged application code as a Zip.
data "archive_file" "package" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/build/package.zip"
}

module "instrumented_function" {
  source = "../../modules/dynatrace-lambda-instrumentation"

  function_name = var.function_name
  runtime       = var.runtime
  handler       = "app.handler"

  filename         = data.archive_file.package.output_path
  source_code_hash = data.archive_file.package.output_base64sha256

  dynatrace_layer_arn    = var.dynatrace_layer_arn
  dt_tenant              = var.dt_tenant
  dt_cluster             = var.dt_cluster
  dt_connection_base_url = var.dt_connection_base_url

  # Connection (trace) token stored in Secrets Manager; write the value out-of-band.
  create_connection_auth_token_secret       = true
  auth_token_secret_recovery_window_in_days = var.auth_token_secret_recovery_window_in_days

  # Optional log collection.
  log_collection_auth_token = var.log_collection_auth_token

  tags = var.tags
}

output "function_arn" {
  value = module.instrumented_function.function_arn
}

output "connection_auth_token_secret_arn" {
  value = module.instrumented_function.connection_auth_token_secret_arn
}

output "execution_role_arn" {
  value = module.instrumented_function.execution_role_arn
}

output "log_collection_enabled" {
  value = module.instrumented_function.log_collection_enabled
}
