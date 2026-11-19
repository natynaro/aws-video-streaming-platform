########################################
# Networking Outputs
########################################

output "x_projectBKN_public_subnet_id" {
  value = aws_subnet.x_projectBKN_public_subnet.id
}

output "x_projectBKN_private_subnet_id" {
  value = aws_subnet.x_projectBKN_private_subnet.id
}

output "x_projectBKN_web_sg_id" {
  value = aws_security_group.x_projectBKN_web_sg.id
}

output "x_projectBKN_streamer_sg_id" {
  value = aws_security_group.x_projectBKN_streamer_sg.id
}

########################################
# Compute Outputs
########################################

# Permanent public IP (Elastic IP)
output "x_projectBKN_web_public_ip" {
  value = aws_eip.x_projectBKN_web_eip.public_ip
}

output "x_projectBKN_web_private_ip" {
  value = aws_instance.x_projectBKN_web.private_ip
}

output "x_projectBKN_streamer_private_ip" {
  value = try(aws_instance.x_projectBKN_streamer.private_ip, "not-ready")
}

output "x_projectBKN_nat_gateway_id" {
  value       = aws_nat_gateway.x_projectBKN_nat.id
  description = "NAT Gateway for private subnet outbound traffic"
}

output "x_projectBKN_web_certbot_instance_profile" {
  value       = var.enable_dns01_iam ? aws_iam_instance_profile.x_projectBKN_web_certbot[0].name : null
  description = "IAM instance profile for Let's Encrypt DNS-01 (Route53); null when enable_dns01_iam=false"
}

output "x_projectBKN_web_certbot_role_arn" {
  value       = var.enable_dns01_iam ? aws_iam_role.x_projectBKN_web_certbot[0].arn : null
  description = "IAM role ARN used by Web Frontend for Route53 ACME challenges"
}

output "x_projectBKN_certbot_challenge" {
  value       = var.enable_dns01_iam ? "dns-route53" : "webroot"
  description = "ACME challenge type written to ansible inventory"
}

output "x_projectBKN_stream_domain" {
  value       = var.stream_domain
  description = "Route53 HTTPS hostname for the Web Frontend"
}