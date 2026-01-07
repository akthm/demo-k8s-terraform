/**
 * ==============================================================================
 * IAM Resources - AWS Load Balancer Controller (DEPRECATED)
 * ==============================================================================
 *
 * This file previously created IAM Role for the AWS LB Controller.
 * 
 * CHANGE: Now using NGINX Ingress Controller instead of AWS LB Controller.
 * NGINX doesn't require AWS IAM integration.
 * 
 * Commenting out below for reference. Can be deleted if AWS LB not needed.
 */

# Create IAM role for the LB controller with IRSA trust relationship
# resource "aws_iam_role" "aws_load_balancer_controller" {
#   name = "EKS-AWSLoadBalancerController-Role-${var.cluster_name}"
#
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRoleWithWebIdentity"
#         Effect = "Allow"
#         Principal = {
#           Federated = var.cluster_oidc_provider_arn
#         }
#         Condition = {
#           StringEquals = {
#             "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
#             "${replace(var.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
#           }
#         }
#       }
#     ]
#   })
# }
#
# # Attach AWS managed policy for ALB/NLB controller
# # This policy grants permissions to create/manage load balancers
# resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
#   role       = aws_iam_role.aws_load_balancer_controller.name
#   policy_arn = "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess"
# }
#
# # Output the role ARN for use in Helm chart configuration
# output "aws_lb_controller_role_arn" {
#   description = "ARN of the IAM role for AWS Load Balancer Controller"
#   value       = aws_iam_role.aws_load_balancer_controller.arn
# }