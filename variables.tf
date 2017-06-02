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

variable "office_ip_cidrs" {
  description = "[List] Office IP CIDRs for SSH and HTTPS"
  type        = "list"
}

variable "tag_product" {}
variable "tag_env" {}
variable "tag_purpose" {}
variable "tag_role" {}
