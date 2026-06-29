# Validation record

**Date:** 2026-06-29
**Providers:** `hashicorp/aws` v5.100.0, `hashicorp/archive` v2.8.0 · Terraform v1.14.0
**AWS account:** lab account (12-digit, redacted) · **Region:** us-east-1
**Module:** `modules/dynatrace-lambda-instrumentation` via `examples/python-function`

## Mechanism validated: current-generation (exec-wrapper + collector)

This module targets the **current** OneAgent Lambda layer (account `585768157899`),
which instruments via `AWS_LAMBDA_EXEC_WRAPPER=/opt/dynatrace` (LD_PRELOAD) and a
bundled collector — **not** the classic `dtlambdainstrument.handler_wrap` handler swap.

The correct configuration was confirmed against a **live Dynatrace layer (v1.339)** and
the Hub deployment wizard for a real tenant:
- `AWS_LAMBDA_EXEC_WRAPPER=/opt/dynatrace`, handler **unchanged**
- `DT_TENANT`, `DT_CLUSTER`, `DT_CONNECTION_BASE_URL=https://<tenant>.live.dynatrace.com`
- `DT_CONNECTION_AUTH_TOKEN` (trace, `openTelemetryTrace.ingest`) — via Secrets Manager
- `DT_LOG_COLLECTION_AUTH_TOKEN` (`logs.ingest`) — required by the with-collector layer
  (its absence makes the collector fail: `dynatracelogs: endpoint is required` → no-op)

The collector was observed healthy with the full config on a live function
(`dynatrace-collector State: Ready`, `DynatraceLambdaExtension State: Ready`,
no export errors).

## Stand-in layer note

The lab AWS account has no Dynatrace tenant, so the live `apply` used a **stand-in
layer** providing a passthrough `/opt/dynatrace` exec-wrapper script in place of the
real OneAgent layer. The module treats any layer ARN identically; swapping in the real
ARN is a one-variable change.

## Results — PASS

| Check | Result |
|---|---|
| `terraform fmt -recursive` | PASS |
| `terraform init` / `validate` | PASS |
| Live apply (5 resources) | PASS — 5 added, 0 changed, 0 destroyed |
| Handler left **unchanged** (`app.handler`) | PASS |
| `AWS_LAMBDA_EXEC_WRAPPER=/opt/dynatrace` set | PASS |
| `DT_TENANT` / `DT_CLUSTER` / `DT_CONNECTION_BASE_URL` set | PASS |
| `DT_CONNECTION_AUTH_TOKEN_SECRETS_MANAGER_ARN` → created secret | PASS |
| IAM inline policy = `secretsmanager:GetSecretValue` scoped to the one secret | PASS |
| Invoke with exec wrapper active | **PASS — 200, no FunctionError**, app body returned (wrapper does not break execution) |
| `terraform destroy` | PASS — 5 destroyed |

## Bug found and fixed during validation

- **`Output refers to sensitive values`** on `log_collection_enabled`: the boolean
  derives from the sensitive `log_collection_auth_token`, so it inherited sensitivity.
  Fixed with `nonsensitive(var.log_collection_auth_token != "")` in the module output —
  whether logs are enabled is not itself secret.

## What the live test does NOT cover

- Real Dynatrace trace ingestion / service auto-discovery — requires a real tenant, the
  real layer ARN, and the two ingest tokens. Those are a one-variable layer swap plus
  the out-of-band token writes.

## Environment gotchas (carried into the deliverable)

- **Credential bridge for `aws login` / SSO wrapper sessions** (Terraform: "No valid
  credential sources found"): `eval "$(aws configure export-credentials --format env)"`.
- Set `auth_token_secret_recovery_window_in_days = 0` in lab/test so `destroy` removes
  the secret immediately and the name can be reused (default 30 in prod).
