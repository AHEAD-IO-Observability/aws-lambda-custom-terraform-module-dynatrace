###############################################################################
# Lambda execution role
#
# Created by default. Grants:
#   - CloudWatch Logs (AWSLambdaBasicExecutionRole) so the function can run
#   - secretsmanager:GetSecretValue scoped to the connection-token secret (only
#     when one is in use), which is the only extra permission the layer needs.
# Set create_execution_role = false to bring your own role via execution_role_arn.
###############################################################################

locals {
  execution_role_name = var.execution_role_name != "" ? var.execution_role_name : "${var.function_name}-dynatrace-exec"
  execution_role_arn  = var.create_execution_role ? aws_iam_role.exec[0].arn : var.execution_role_arn
}

data "aws_iam_policy_document" "assume" {
  count = var.create_execution_role ? 1 : 0

  statement {
    sid     = "LambdaAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "exec" {
  count = var.create_execution_role ? 1 : 0

  name               = local.execution_role_name
  description        = "Execution role for Dynatrace-instrumented Lambda ${var.function_name}."
  assume_role_policy = data.aws_iam_policy_document.assume[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "basic" {
  count = var.create_execution_role ? 1 : 0

  role       = aws_iam_role.exec[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Least-privilege read on exactly the connection-token secret (only when one is used).
data "aws_iam_policy_document" "secrets" {
  count = var.create_execution_role && local.use_connection_secret ? 1 : 0

  statement {
    sid       = "DynatraceConnectionTokenRead"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [local.connection_secret_arn]
  }
}

resource "aws_iam_role_policy" "secrets" {
  count = var.create_execution_role && local.use_connection_secret ? 1 : 0

  name   = "${local.execution_role_name}-dynatrace-connection-token"
  role   = aws_iam_role.exec[0].id
  policy = data.aws_iam_policy_document.secrets[0].json
}

resource "aws_iam_role_policy_attachment" "additional" {
  for_each = var.create_execution_role ? toset(var.additional_policy_arns) : toset([])

  role       = aws_iam_role.exec[0].name
  policy_arn = each.value
}
