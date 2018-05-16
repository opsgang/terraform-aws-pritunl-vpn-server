variable "aws_key_name" {
  description = "SSH keypair name for the VPN instance"
}

variable "vpc_id" {
  description = "Which VPC VPN server will be created in"
}

variable "public_subnet_id" {
  description = "One of the public subnet id for the VPN instance"
}

variable "ami_id" {
  description = "AMI ID of Amazon Linux"
}

variable "instance_type" {
  description = "Instance type for VPN Box"
}

variable "whitelist" {
  description = "[List] Office IP CIDRs for SSH and HTTPS"
  type        = "list"
}

variable "tags" {
  description = "A map of tags to add to all resources"
  default     = {}
}

variable "resource_name_prefix" {
  description = "All the resources will be prefixed with this varible"
  default     = "pritunl"
}
