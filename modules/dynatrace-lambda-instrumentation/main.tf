###############################################################################
# Dynatrace OneAgent tracing instrumentation for a net-new AWS Lambda function
# (current-generation, collector-based layer — published from account 585768157899).
#
# Terraform owns every immutable artifact required for tracing:
#   - the Lambda function with the OneAgent layer attached
#   - AWS_LAMBDA_EXEC_WRAPPER (the layer LD_PRELOADs the native OneAgent; the
#     handler is NOT changed)
#   - the Dynatrace connection variables (DT_TENANT / DT_CLUSTER / DT_CONNECTION_BASE_URL)
#   - the connection (trace) token, resolved from Secrets Manager at cold start
#   - the optional log-collection token (DT_LOG_COLLECTION_AUTH_TOKEN)
#   - the IAM execution role granting secretsmanager:GetSecretValue
#
# Nothing is configured in Dynatrace at deploy time: once the function runs with
# the layer active, Dynatrace auto-discovers it as a service and populates traces,
# cold-start detection, Davis AI, and Smartscape. Obtain the layer ARN and the
# DT_* values from the Hub deployment wizard / Deployment API.
###############################################################################

locals {
  # Resolve the connection-token secret ARN: created here, or supplied by the caller.
  # Known at plan time via booleans; the created ARN itself is only known after apply.
  use_connection_secret = var.create_connection_auth_token_secret || var.connection_auth_token_secret_arn != ""
  connection_secret_arn = var.create_connection_auth_token_secret ? aws_secretsmanager_secret.connection_auth_token[0].arn : var.connection_auth_token_secret_arn

  # All layer ARNs, Dynatrace first. compact() drops any empty additional entries.
  layers = compact(concat([var.dynatrace_layer_arn], var.additional_layers))

  # Module-managed environment. additional_environment_variables is merged last so
  # callers can override.
  managed_environment = merge(
    {
      AWS_LAMBDA_EXEC_WRAPPER = var.exec_wrapper
      DT_TENANT               = var.dt_tenant
      DT_CLUSTER              = var.dt_cluster
      DT_CONNECTION_BASE_URL  = var.dt_connection_base_url
    },
    # Connection (trace) token: prefer the Secrets Manager indirection; otherwise plaintext.
    local.use_connection_secret ? {
      DT_CONNECTION_AUTH_TOKEN_SECRETS_MANAGER_ARN = local.connection_secret_arn
      } : (var.connection_auth_token != "" ? {
        DT_CONNECTION_AUTH_TOKEN = var.connection_auth_token
    } : {}),
    # Optional log collection (required by the with-collector layer).
    var.log_collection_auth_token != "" ? {
      DT_LOG_COLLECTION_AUTH_TOKEN = var.log_collection_auth_token
    } : {},
  )

  environment_variables = merge(local.managed_environment, var.additional_environment_variables)
}

###############################################################################
# Secrets Manager — connection (trace) token container.
# Value written out-of-band (Ansible/pipeline); resolved by the layer at cold start.
###############################################################################

resource "aws_secretsmanager_secret" "connection_auth_token" {
  count = var.create_connection_auth_token_secret ? 1 : 0

  name                    = var.connection_auth_token_secret_name != "" ? var.connection_auth_token_secret_name : "dynatrace/${var.function_name}/connection-auth-token"
  description             = "Dynatrace OneAgent connection (trace-ingest) token for Lambda ${var.function_name}. Plaintext token value written out-of-band and resolved by the layer at cold start."
  recovery_window_in_days = var.auth_token_secret_recovery_window_in_days
  tags                    = var.tags
}

###############################################################################
# Lambda function — code and handler unchanged; instrumentation at deploy time
###############################################################################

resource "aws_lambda_function" "this" {
  function_name = var.function_name
  role          = local.execution_role_arn
  runtime       = var.runtime
  handler       = var.handler
  architectures = var.architectures
  memory_size   = var.memory_size
  timeout       = var.timeout
  layers        = local.layers

  filename          = var.filename != "" ? var.filename : null
  source_code_hash  = var.filename != "" ? (var.source_code_hash != "" ? var.source_code_hash : filebase64sha256(var.filename)) : null
  s3_bucket         = var.s3_bucket != "" ? var.s3_bucket : null
  s3_key            = var.s3_key != "" ? var.s3_key : null
  s3_object_version = var.s3_object_version != "" ? var.s3_object_version : null

  environment {
    variables = local.environment_variables
  }

  dynamic "vpc_config" {
    for_each = length(var.vpc_subnet_ids) > 0 ? [1] : []
    content {
      subnet_ids         = var.vpc_subnet_ids
      security_group_ids = var.vpc_security_group_ids
    }
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.basic,
    aws_iam_role_policy.secrets,
  ]
}
