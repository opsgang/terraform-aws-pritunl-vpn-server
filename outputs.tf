output "vpn_instance_private_ip_address" {
  value = aws_instance.pritunl.private_ip
}

output "vpn_public_ip_address" {
  value = aws_eip.pritunl.public_ip
}

output "vpn_management_ui" {
  value = "https://${aws_eip.pritunl.public_ip}"
}
