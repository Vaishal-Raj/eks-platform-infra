output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}

output "plan_role_arn" {
  value = aws_iam_role.plan.arn
}

output "apply_role_arns" {
  value = { for env, role in aws_iam_role.apply : env => role.arn }
}