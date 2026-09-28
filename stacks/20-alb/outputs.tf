output "alb_arn" {
  description = "ALB ARN (the edge stack's VPC origin points here)"
  value       = module.alb.alb_arn
}

output "alb_dns_name" {
  description = "Internal DNS name of the ALB"
  value       = module.alb.alb_dns_name
}

output "alb_security_group_id" {
  description = "ALB security group (the edge stack adds the CloudFront inbound rule)"
  value       = module.alb.security_group_id
}

output "listener_port" {
  description = "ALB HTTP listener port"
  value       = module.alb.listener_port
}

output "target_group_arn" {
  description = "Empty IP target group for EKS (M3)"
  value       = module.alb.target_group_arn
}