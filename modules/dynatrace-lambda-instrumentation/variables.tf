###############################################################################
# Function identity
###############################################################################

variable "function_name" {
  description = "Name of the AWS Lambda function to create and instrument."
  type        = string

  validation {
    condition     = length(var.function_name) >= 1 && length(var.function_name) <= 64
    error_message = "function_name must be 1-64 characters."
  }
}

variable "runtime" {
  description = "Lambda runtime identifier (e.g. python3.13, nodejs20.x, java21). The current-generation OneAgent layer instruments via AWS_LAMBDA_EXEC_WRAPPER and does NOT change the handler for any runtime."
  type        = string
}

variable "handler" {
  description = "The function handler entry point (e.g. index.handler). Left unchanged — current-generation instrumentation does not wrap the handler."
  type        = string
}

variable "architectures" {
  description = "Instruction set architecture(s) for the function. One of [\"x86_64\"] or [\"arm64\"]. Must match the Dynatrace layer variant."
  type        = list(string)
  default     = ["x86_64"]

  validation {
    condition     = length(var.architectures) == 1 && contains(["x86_64", "arm64"], var.architectures[0])
    error_message = "architectures must be exactly one of [\"x86_64\"] or [\"arm64\"]."
  }
}

variable "memory_size" {
  description = "Amount of memory in MB the function can use at runtime."
  type        = number
  default     = 256
}

variable "timeout" {
  description = "Function timeout in seconds. The layer fetches the auth token (when using Secrets Manager) once during init, adding to cold-start duration — keep this comfortably above the handler's own needs."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to all AWS resources created by this module."
  type        = map(string)
  default     = {}
}

###############################################################################
# Deployment package (Zip only — provide exactly one source)
###############################################################################

variable "filename" {
  description = "Path to a local .zip deployment package. Mutually exclusive with the s3_* inputs."
  type        = string
  default     = ""
}

variable "source_code_hash" {
  description = "Base64 SHA-256 of the local zip. Defaults to filebase64sha256(var.filename) when filename is set."
  type        = string
  default     = ""
}

variable "s3_bucket" {
  description = "S3 bucket holding the deployment package. Requires s3_key. Mutually exclusive with filename."
  type        = string
  default     = ""
}

variable "s3_key" {
  description = "S3 object key of the deployment package. Requires s3_bucket."
  type        = string
  default     = ""
}

variable "s3_object_version" {
  description = "Optional S3 object version of the deployment package."
  type        = string
  default     = ""
}

###############################################################################
# Dynatrace OneAgent layer + tracing connection
#
# Values come from the Dynatrace Hub AWS Lambda deployment wizard (or the
# Deployment API). The wizard emits exactly these variables for the
# current-generation, collector-based layer (published from account 585768157899).
###############################################################################

variable "dynatrace_layer_arn" {
  description = <<-EOT
    ARN of the current-generation Dynatrace OneAgent AWS Lambda layer for this
    region/runtime/architecture. Use the WITH-collector variant when log collection
    is enabled. Obtain it from the Hub deployment wizard or
    GET /api/v1/deployment/lambda/layer?techtype=<rt>&region=<r>&arch=<a>.
  EOT
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:lambda:[a-z0-9-]+:[0-9]{12}:layer:[^:]+:[0-9]+$", var.dynatrace_layer_arn))
    error_message = "dynatrace_layer_arn must be a fully qualified Lambda layer version ARN (…:layer:<name>:<version>)."
  }
}

variable "dynatrace_layer_publisher_account_id" {
  description = "Dynatrace AWS account that publishes the current-generation OneAgent Lambda layer. Documentation/output only."
  type        = string
  default     = "585768157899"
}

variable "additional_layers" {
  description = "Extra Lambda layer ARNs to attach alongside the Dynatrace layer."
  type        = list(string)
  default     = []
}

variable "exec_wrapper" {
  description = "Value of AWS_LAMBDA_EXEC_WRAPPER. The layer's wrapper script that LD_PRELOADs the native OneAgent. Override only if Dynatrace changes the path."
  type        = string
  default     = "/opt/dynatrace"
}

variable "dt_tenant" {
  description = "Dynatrace tenant (environment) ID — value of DT_TENANT (e.g. abc12345)."
  type        = string
}

variable "dt_cluster" {
  description = "Dynatrace cluster ID — value of DT_CLUSTER (from the deployment wizard)."
  type        = string
}

variable "dt_connection_base_url" {
  description = "Dynatrace connection base URL — value of DT_CONNECTION_BASE_URL (e.g. https://<tenant>.live.dynatrace.com)."
  type        = string

  validation {
    condition     = can(regex("^https://", var.dt_connection_base_url))
    error_message = "dt_connection_base_url must be an https:// URL."
  }
}

variable "additional_environment_variables" {
  description = "Extra environment variables merged into the function. Takes precedence over module-managed variables on key collision."
  type        = map(string)
  default     = {}
}

###############################################################################
# Connection (trace-ingest) auth token — DT_CONNECTION_AUTH_TOKEN
#
# Needs the "Ingest OpenTelemetry traces" (openTelemetryTrace.ingest) scope.
# Preferred: store in Secrets Manager and let the layer resolve it at cold start
# via DT_CONNECTION_AUTH_TOKEN_SECRETS_MANAGER_ARN (token never in plain config).
###############################################################################

variable "create_connection_auth_token_secret" {
  description = "Create a Secrets Manager secret for the connection (trace) token and wire DT_CONNECTION_AUTH_TOKEN_SECRETS_MANAGER_ARN. The token VALUE is written out-of-band (Ansible/pipeline)."
  type        = bool
  default     = true
}

variable "connection_auth_token_secret_name" {
  description = "Name of the created connection-token secret. Defaults to dynatrace/<function_name>/connection-auth-token when empty."
  type        = string
  default     = ""
}

variable "connection_auth_token_secret_arn" {
  description = "ARN of an existing connection-token secret to use when create_connection_auth_token_secret is false."
  type        = string
  default     = ""
}

variable "connection_auth_token" {
  description = "Plaintext connection (trace) token. Only used when NOT using Secrets Manager (both create_… false and …_secret_arn empty). Sets DT_CONNECTION_AUTH_TOKEN directly — avoid in production."
  type        = string
  default     = ""
  sensitive   = true
}

variable "auth_token_secret_recovery_window_in_days" {
  description = "Recovery window for created secrets. 0 for immediate deletion (lab/test); 7-30 for production."
  type        = number
  default     = 30
}

###############################################################################
# Log collection (optional) — DT_LOG_COLLECTION_AUTH_TOKEN
#
# Required when using the WITH-collector layer; without it the collector fails
# to start ("dynatracelogs: endpoint is required") and runs in no-op mode. Needs
# the "Ingest logs" (logs.ingest) scope. No Secrets Manager indirection exists
# for this variable, so it is set as a (sensitive) plaintext env var.
###############################################################################

variable "log_collection_auth_token" {
  description = "Plaintext log-ingest token for DT_LOG_COLLECTION_AUTH_TOKEN. Set when using the with-collector layer to enable log collection. Leave empty to omit (use a without-collector layer for trace-only)."
  type        = string
  default     = ""
  sensitive   = true
}

###############################################################################
# IAM execution role
###############################################################################

variable "create_execution_role" {
  description = "Create the Lambda execution role. Set false to attach an existing role via execution_role_arn."
  type        = bool
  default     = true
}

variable "execution_role_arn" {
  description = "ARN of an existing execution role to use when create_execution_role is false. Must allow secretsmanager:GetSecretValue on the connection-token secret when one is used."
  type        = string
  default     = ""
}

variable "execution_role_name" {
  description = "Name of the execution role to create. Defaults to <function_name>-dynatrace-exec when empty."
  type        = string
  default     = ""
}

variable "additional_policy_arns" {
  description = "Extra managed policy ARNs to attach to the created execution role (e.g. AWSLambdaVPCAccessExecutionRole)."
  type        = list(string)
  default     = []
}

###############################################################################
# Optional VPC config
###############################################################################

variable "vpc_subnet_ids" {
  description = "Subnet IDs for VPC-attached functions. Leave empty for no VPC. The function must still reach the Dynatrace connection URL (NAT/endpoint)."
  type        = list(string)
  default     = []
}

variable "vpc_security_group_ids" {
  description = "Security group IDs for VPC-attached functions."
  type        = list(string)
  default     = []
}
