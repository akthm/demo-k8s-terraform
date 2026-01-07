/**
 * ==============================================================================
 * IAM Resources - External Secrets Operator
 * ==============================================================================
 *
 * This file creates a dedicated IAM Role for the ESO controller
 * using the IRSA (IAM Roles for Service Accounts) pattern.
 */

# Define the IAM policy that ESO needs.
# This grants read-only access to Secrets Manager and SSM Parameters.
# BEST PRACTICE: Restrict this policy further!
# You can restrict 'Resource' to specific secret ARN patterns, e.g.:
# "Resource": "arn:aws:secretsmanager:*:*:secret:staging/*"
data "aws_iam_policy_document" "external_secrets" {
  statement {
    sid    = "AllowSecretManagerRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecrets" // Required for 'findByTag'
    ]
    resources = ["*"] # WARNING: Make this more specific for production!
  }

  statement {
    sid    = "AllowSSMParameterRead"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath"
    ]
    resources = ["*"] # WARNING: Make this more specific for production!
  }
}

# Create the IAM policy resource from the document above
resource "aws_iam_policy" "external_secrets" {
  name        = "EKS-ExternalSecrets-Policy-${var.cluster_name}"
  description = "Allows ESO to read secrets from AWS Secrets Manager and SSM"
  policy      = data.aws_iam_policy_document.external_secrets.json
}

# Create the IRSA Role for the ESO controller
resource "aws_iam_role" "external_secrets" {
  name = "EKS-ExternalSecrets-Role-${var.cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = var.cluster_oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:external-secrets:external-secrets-controller"
            "${replace(var.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "external_secrets" {
  role       = aws_iam_role.external_secrets.name
  policy_arn = aws_iam_policy.external_secrets.arn
}

# Output the ARN of the created role so 'main.tf' can use it
output "external_secrets_role_arn" {
  value = aws_iam_role.external_secrets.arn
}