data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  backup_bucket_name = var.s3_bucket_name != "" ? var.s3_bucket_name : format("%s-%s", var.resource_name_prefix, "backup")
}

data "template_file" "user_data" {
  template = templatefile("${path.module}/templates/user_data.sh.tpl",
    {
      aws_region          = data.aws_region.current.name
      s3_backup_bucket    = local.backup_bucket_name
      healthchecks_io_key = "/pritunl/${var.resource_name_prefix}/healthchecks-io-key"
    }
  )
}

data "template_file" "kms_policy" {
  template = templatefile("${path.module}/templates/key_policy.json.tpl", {
    resource_name_prefix = var.resource_name_prefix
    account_id           = data.aws_caller_identity.current.account_id
    key_admin_arn        = aws_iam_role.role.arn
    }
  )
}

data "template_file" "iam_instance_role_policy" {
  template = templatefile("${path.module}/templates/iam_instance_role_policy.json.tpl", {
    s3_backup_bucket     = local.backup_bucket_name
    resource_name_prefix = var.resource_name_prefix
    aws_region           = data.aws_region.current.name
    account_id           = data.aws_caller_identity.current.account_id
    ssm_key_prefix       = "/pritunl/${var.resource_name_prefix}/*"
    }
  )
}

resource "null_resource" "waiter" {
  depends_on = [aws_iam_instance_profile.ec2_profile]

  provisioner "local-exec" {
    command = "sleep 15"
  }
}

resource "aws_kms_key" "parameter_store" {
  depends_on = [null_resource.waiter]

  description = "Parameter store and backup key for ${var.resource_name_prefix}"

  policy                  = data.template_file.kms_policy.rendered
  deletion_window_in_days = 30
  is_enabled              = true
  enable_key_rotation     = true

  tags = merge(
    map("Name", format("%s-%s", var.resource_name_prefix, "parameter-store")),
    var.tags,
  )
}

resource "aws_kms_alias" "parameter_store" {
  depends_on = [aws_kms_key.parameter_store]

  name          = "alias/${var.resource_name_prefix}-parameter-store"
  target_key_id = aws_kms_key.parameter_store.key_id
}

resource "aws_ssm_parameter" "healthchecks_io_key" {
  name      = "/pritunl/${var.resource_name_prefix}/healthchecks-io-key"
  type      = "SecureString"
  value     = var.healthchecks_io_key
  key_id    = aws_kms_key.parameter_store.arn
  overwrite = true

  tags = merge(
    map("Name", format("%s/%s/%s", "pritunl", var.resource_name_prefix, "healthchecks-io-key")),
    var.tags,
  )
}

resource "aws_s3_bucket" "backup" {
  depends_on = [aws_kms_key.parameter_store]

  bucket = local.backup_bucket_name

  acl = "private"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.parameter_store.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  lifecycle_rule {
    prefix  = "backups"
    enabled = true

    expiration {
      days = 30
    }

    abort_incomplete_multipart_upload_days = 7
  }

  tags = merge(
    map("Name", local.backup_bucket_name),
    var.tags,
  )
}

# ec2 iam role
resource "aws_iam_role" "role" {
  name = var.resource_name_prefix

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "policy" {
  depends_on = [aws_iam_role.role]

  name   = "${var.resource_name_prefix}-instance-policy"
  role   = aws_iam_role.role.id
  policy = data.template_file.iam_instance_role_policy.rendered
}

resource "aws_iam_instance_profile" "ec2_profile" {
  depends_on = [aws_iam_role.role, aws_iam_role_policy.policy]

  name = "${var.resource_name_prefix}-instance"
  role = aws_iam_role.role.name
}

resource "aws_security_group" "pritunl" {
  name        = "${var.resource_name_prefix}-vpn"
  description = "${var.resource_name_prefix}-vpn"
  vpc_id      = var.vpc_id

  # HTTP access for Let's Encrypt validation
  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"

    cidr_blocks = var.whitelist_http
  }

  # VPN WAN access
  ingress {
    from_port   = 10000
    to_port     = 19999
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    map("Name", format("%s-%s", var.resource_name_prefix, "vpn")),
    var.tags,
  )
}

resource "aws_security_group" "allow_from_office" {
  name        = "${var.resource_name_prefix}-whitelist"
  description = "Allows HTTP(s) connections from whitelisted IPs"
  vpc_id      = var.vpc_id

  # HTTPS access
  ingress {
    description = "Allow HTTPS access to the web console"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.whitelist
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    map("Name", format("%s-%s", var.resource_name_prefix, "whitelist")),
    var.tags,
  )
}

resource "aws_instance" "pritunl" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.aws_key_name
  ebs_optimized = var.ebs_optimized
  user_data     = data.template_file.user_data.rendered

  vpc_security_group_ids = [
    aws_security_group.pritunl.id,
    aws_security_group.allow_from_office.id,
  ]

  subnet_id            = var.public_subnet_id
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  tags = merge(
    map("Name", format("%s-%s", var.resource_name_prefix, "vpn")),
    var.tags,
  )
}

resource "aws_eip" "pritunl" {
  instance = aws_instance.pritunl.id
  vpc      = true
}
