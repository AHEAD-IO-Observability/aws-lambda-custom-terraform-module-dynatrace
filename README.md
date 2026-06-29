# aws-lambda-custom-terraform-module-dynatrace

Terraform automation for **Dynatrace OneAgent distributed tracing on net-new AWS
Lambda functions**. One `terraform apply` produces a function that is fully
instrumented at deploy time — no application code changes, no OpenTelemetry
pipeline, and no manual steps in the Dynatrace console.

Targets the **current-generation, collector-based** OneAgent Lambda layer (Dynatrace
AWS account `585768157899`).

> Implements the AHEAD *Dynatrace Tracing Instrumentation for AWS Lambda* architecture
> (internal AHEAD document, not included in this public repository).

## How it works

The Dynatrace OneAgent AWS Lambda **layer** does the instrumentation. Terraform
attaches the layer and sets `AWS_LAMBDA_EXEC_WRAPPER=/opt/dynatrace`, which
`LD_PRELOAD`s the native OneAgent — the **handler is not changed**. Terraform also
wires the connection variables, creates the execution role, and creates the Secrets
Manager secret for the trace token. The token **value** is written out-of-band
(Ansible / pipeline) and resolved by the layer once during init, so it never lives in
plaintext. Dynatrace auto-discovers the function as a service on its first
instrumented invocation.

```
┌── Pipeline (Terraform) ───────────────┐   ┌── AWS account (runtime) ──────────────┐
│ Lambda + OneAgent layer (collector)   │   │ unchanged function code + handler     │
│ AWS_LAMBDA_EXEC_WRAPPER=/opt/dynatrace │──▶│ OneAgent LD_PRELOADed (acct 585768…)  │
│ IAM execution role                     │   │ DT_TENANT / DT_CLUSTER /              │
│ Secrets Manager secret (trace token)   │   │ DT_CONNECTION_BASE_URL                │
└────────────────────────────────────────┘   │ trace token ← Secrets Mgr @ init     │──▶ Dynatrace
   Ansible / pipeline: writes token value, sets env per environment                  (auto-discovered)
```

## ⚠️ Mechanism note (classic vs current)

The AHEAD *Dynatrace_Lambda_Tracing_Architecture* document describes the **classic**
mechanism: a handler swap to `dtlambdainstrument.handler_wrap` with `ORIGINAL_HANDLER`
(classic layer, account `725887861453`). The current layer (account `585768157899`)
that the Dynatrace Hub/Deployment API hands out today does **not** ship that module —
it instruments via `AWS_LAMBDA_EXEC_WRAPPER` and a bundled collector. This module
implements the **current** mechanism, validated against a live layer (v1.339). If your
pipeline still uses the classic layer, the variable shape differs (handler wrap +
`DT_CONNECTION_POINT`/`DT_CONNECTION_AUTH_TOKEN`).

## Component ownership

| Component | Where it lives | Owned by |
|---|---|---|
| OneAgent layer (ARN) | Lambda function | **Terraform** (this module) |
| `AWS_LAMBDA_EXEC_WRAPPER` | Lambda configuration | **Terraform** |
| `DT_TENANT`, `DT_CLUSTER`, `DT_CONNECTION_BASE_URL` | Lambda configuration | **Terraform** (doc assigns env to Ansible; here it's IaC) |
| Connection (trace) token **value** | AWS Secrets Manager | Ansible / pipeline (out-of-band) |
| Trace-token **secret + IAM** | AWS Secrets Manager / IAM | **Terraform** |
| Log-ingest token `DT_LOG_COLLECTION_AUTH_TOKEN` | Lambda configuration | **Terraform** (sensitive var) |
| IAM execution role | AWS IAM | **Terraform** |
| Traces, logs, Davis AI, Smartscape | Dynatrace | automatic, zero deploy-time config |

## Tokens (two distinct ones)

| Env var | Purpose | Scope |
|---|---|---|
| `DT_CONNECTION_AUTH_TOKEN` (or `…_SECRETS_MANAGER_ARN`) | trace ingest — creates the service | `openTelemetryTrace.ingest` |
| `DT_LOG_COLLECTION_AUTH_TOKEN` | log ingest | `logs.ingest` |

The with-collector layer needs the log token or its collector runs no-op
(`dynatracelogs: endpoint is required`). Use a without-collector layer for trace-only.

## Layout

```
modules/dynatrace-lambda-instrumentation/   # the reusable module
examples/python-function/                    # runnable example (zips ./src, instruments it)
VALIDATION.md                                # live end-to-end test record
```

## Quick start

```bash
cd examples/python-function
cp terraform.tfvars.example terraform.tfvars   # set layer ARN + dt_tenant/dt_cluster/dt_connection_base_url
terraform init && terraform apply

aws secretsmanager put-secret-value \
  --secret-id "$(terraform output -raw connection_auth_token_secret_arn)" \
  --secret-string 'dt0c01.XXXX...'             # openTelemetryTrace.ingest token
```

See [`modules/dynatrace-lambda-instrumentation/README.md`](./modules/dynatrace-lambda-instrumentation/README.md)
for the full input/output reference.

## Out of scope

- Container-image packaging (the layer mechanism here targets Zip packages).
- The optional ActiveGate and the optional CloudWatch metric link.
- Lambda **SnapStart** — Secrets Manager token resolution is not supported with SnapStart.
