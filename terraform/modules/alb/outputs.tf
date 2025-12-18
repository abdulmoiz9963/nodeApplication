output "alb_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.main.dns_name
}

output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "target_group_arns" {
  description = "ARNs of the target groups"
  value = {
    gateway = aws_lb_target_group.gateway.arn
    worker  = aws_lb_target_group.worker.arn
  }
}
