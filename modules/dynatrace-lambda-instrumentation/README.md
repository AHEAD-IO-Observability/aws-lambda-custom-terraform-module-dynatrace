# Module: dynatrace-lambda-instrumentation

Creates a net-new AWS Lambda function with Dynatrace OneAgent distributed tracing
baked in at deploy time — no application code changes, no OpenTelemetry pipeline,
and no manual Dynatrace console steps. The function is auto-discovered as a
Dynatrace service the first time it is invoked.

Targets the **current-generation, collector-based** OneAgent Lambda layer (published
from Dynatrace AWS account `585768157899`). This layer instruments via
`AWS_LAMBDA_EXEC_WRAPPER` (it `LD_PRELOAD`s the native OneAgent) — it does **not**
change the function handler. See the [repository README](../../README.md) for the
component-ownership picture and the Terraform/Ansible split.

> Not the classic mechanism. Older docs describe a handler swap to
> `dtlambdainstrument.handler_wrap` + `ORIGINAL_HANDLER` (classic layer, account
> `725887861453`). The current layer does not ship that module; this module uses the
> exec-wrapper approach the Hub deployment wizard emits.

## What the module owns

| Concern | Resource / setting |
|---|---|
| Lambda function with the OneAgent layer attached | `aws_lambda_function` (`layers`) |
| `AWS_LAMBDA_EXEC_WRAPPER=/opt/dynatrace` (handler unchanged) | function `environment` |
| Connection vars `DT_TENANT`, `DT_CLUSTER`, `DT_CONNECTION_BASE_URL` | function `environment` |
| Connection (trace) token via Secrets Manager | `aws_secretsmanager_secret` + `DT_CONNECTION_AUTH_TOKEN_SECRETS_MANAGER_ARN` |
| Optional log-ingest token `DT_LOG_COLLECTION_AUTH_TOKEN` | function `environment` (plaintext, sensitive) |
| Execution role + scoped `secretsmanager:GetSecretValue` + logs | `aws_iam_role` + policies |

The connection-token **value** is not managed here: Terraform creates the empty
secret, the plaintext trace-ingest token is written out-of-band (Ansible / pipeline),
and the layer resolves it from Secrets Manager once during init — so it never lives
in Terraform state or plaintext function config.

## Tokens & scopes (from the Hub wizard)

| Variable | Purpose | Token scope |
|---|---|---|
| `DT_CONNECTION_AUTH_TOKEN` (or `…_SECRETS_MANAGER_ARN`) | trace ingest (creates the service) | `openTelemetryTrace.ingest` |
| `DT_LOG_COLLECTION_AUTH_TOKEN` | log ingest | `logs.ingest` |

The **with-collector** layer requires a log token; without it the collector fails to
start (`dynatracelogs: endpoint is required`) and runs no-op. For trace-only, use a
**without-collector** layer and omit `log_collection_auth_token`.

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.5.0 |
| hashicorp/aws | ~> 5.40 |

> Only the AWS provider is required — nothing is configured in Dynatrace at deploy time.

## Usage

```hcl
module "instrumented_function" {
  source = "github.com/AHEAD-IO-Observability/aws-lambda-custom-terraform-module-dynatrace//modules/dynatrace-lambda-instrumentation"

  function_name = "payments-api"
  runtime       = "python3.13"
  handler       = "app.handler"            # unchanged
  filename      = data.archive_file.pkg.output_path

  # From the Dynatrace Hub AWS Lambda deployment wizard:
  dynatrace_layer_arn    = "arn:aws:lambda:us-east-1:585768157899:layer:Dynatrace_OneAgent_1_339_55_..._with_collector_python_x86:1"
  dt_tenant              = "abc12345"
  dt_cluster             = "490143432"
  dt_connection_base_url = "https://abc12345.live.dynatrace.com"

  # Trace token via Secrets Manager (value written out-of-band); log token enables logs.
  create_connection_auth_token_secret = true
  log_collection_auth_token            = var.dt_log_ingest_token   # logs.ingest scope

  tags = { team = "payments", managed-by = "terraform" }
}
```

Then write the trace token into the created secret:

```bash
aws secretsmanager put-secret-value \
  --secret-id "$(terraform output -raw connection_auth_token_secret_arn)" \
  --secret-string 'dt0c01.XXXX...'        # openTelemetryTrace.ingest, plaintext, no quotes
```

Pin to a released tag in production, e.g. `...//modules/dynatrace-lambda-instrumentation?ref=v1.0.0`.

## Getting the layer ARN & connection values

All come from the Dynatrace Hub **AWS Lambda deployment wizard** (recommended), or the
Deployment API:
- `GET /api/v1/deployment/lambda/layer?techtype=python&region=us-east-1&arch=x86` → layer ARN
- `GET /api/v1/deployment/installer/agent/connectioninfo` → `tenantUUID` / cluster / endpoints

## Inputs

| Name | Type | Default | Required |
|---|---|---|:--:|
| `function_name` | string | – | yes |
| `runtime` | string | – | yes |
| `handler` | string | – | yes |
| `dynatrace_layer_arn` | string | – | yes |
| `dt_tenant` | string | – | yes |
| `dt_cluster` | string | – | yes |
| `dt_connection_base_url` | string | – | yes |
| `filename` / `s3_bucket` + `s3_key` / `s3_object_version` | string | `""` | one of filename / s3_* |
| `source_code_hash` | string | derived | no |
| `architectures` | list(string) | `["x86_64"]` | no |
| `memory_size` | number | `256` | no |
| `timeout` | number | `30` | no |
| `additional_layers` | list(string) | `[]` | no |
| `exec_wrapper` | string | `/opt/dynatrace` | no |
| `additional_environment_variables` | map(string) | `{}` | no |
| `create_connection_auth_token_secret` | bool | `true` | no |
| `connection_auth_token_secret_name` | string | `dynatrace/<fn>/connection-auth-token` | no |
| `connection_auth_token_secret_arn` | string | `""` | when not creating the secret |
| `connection_auth_token` | string (sensitive) | `""` | plaintext fallback |
| `log_collection_auth_token` | string (sensitive) | `""` | for log collection |
| `auth_token_secret_recovery_window_in_days` | number | `30` | no |
| `create_execution_role` | bool | `true` | no |
| `execution_role_arn` | string | `""` | when not creating the role |
| `execution_role_name` | string | `<fn>-dynatrace-exec` | no |
| `additional_policy_arns` | list(string) | `[]` | no |
| `vpc_subnet_ids` / `vpc_security_group_ids` | list(string) | `[]` | no |
| `dynatrace_layer_publisher_account_id` | string | `585768157899` | no |
| `tags` | map(string) | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `function_name` / `function_arn` / `function_qualified_arn` / `function_invoke_arn` | The instrumented function |
| `environment_variables` (sensitive) | Final env-var map applied to the function |
| `execution_role_arn` / `execution_role_name` | Execution role (created or supplied) |
| `connection_auth_token_secret_arn` / `connection_auth_token_secret_name` | Trace-token secret — write the token here out-of-band |
| `log_collection_enabled` | Whether a log-ingest token was configured |
| `dynatrace_layer_arn` | Layer ARN attached |
