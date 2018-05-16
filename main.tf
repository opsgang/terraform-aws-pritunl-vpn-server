data "aws_region" "current" {
  current = true
}

data "aws_caller_identity" "current" {}

data "template_file" "user_data" {
  template = "${file("${path.module}/templates/user_data.sh.tpl")}"

  vars {
    aws_region           = "${data.aws_region.current.name}"
    s3_backup_bucket     = "${var.resource_name_prefix}-backup"
    credstash_table_name = "${var.resource_name_prefix}-credstash"
  }
}

data "template_file" "credstash_policy" {
  template = "${file("${path.module}/templates/key_policy.json.tpl")}"

  vars {
    resource_name_prefix = "${var.resource_name_prefix}"
    key_admin_arn        = "${aws_iam_role.role.arn}"
    account_id           = "${data.aws_caller_identity.current.account_id}"
  }
}

data "template_file" "iam_instance_role_policy" {
  template = "${file("${path.module}/templates/iam_instance_role_policy.json.tpl")}"

  vars {
    resource_name_prefix = "${var.resource_name_prefix}"
    db_credstash_arn     = "${aws_dynamodb_table.db_credstash.arn}"
  }
}

resource "aws_dynamodb_table" "db_credstash" {
  name           = "${var.resource_name_prefix}-credstash"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "name"
  range_key      = "version"

  attribute {
    name = "name"
    type = "S"
  }

  attribute {
    name = "version"
    type = "S"
  }

  tags = "${
            merge(
              map("Name", format("%s-%s", var.resource_name_prefix, "credstash")),
              var.tags,
            )
          }"
}

resource "null_resource" "waiter" {
  depends_on = ["aws_iam_instance_profile.ec2_profile"]

  provisioner "local-exec" {
    command = "sleep 15"
  }
}

resource "aws_kms_key" "credstash" {
  depends_on = ["null_resource.waiter"]

  description = "Credstash space for ${var.resource_name_prefix}"

  policy                  = "${data.template_file.credstash_policy.rendered}"
  deletion_window_in_days = 7
  is_enabled              = true
  enable_key_rotation     = true

  tags = "${
            merge(
              map("Name", format("%s-%s", var.resource_name_prefix, "credstash")),
              var.tags,
            )
          }"
}

resource "aws_kms_alias" "credstash" {
  depends_on = ["aws_kms_key.credstash"]

  name          = "alias/${var.resource_name_prefix}-credstash"
  target_key_id = "${aws_kms_key.credstash.key_id}"
}

resource "aws_s3_bucket" "backup" {
  bucket = "${var.resource_name_prefix}-backup"
  acl    = "private"

  lifecycle_rule {
    prefix  = "backups"
    enabled = true

    expiration {
      days = 30
    }

    abort_incomplete_multipart_upload_days = 7
  }

  tags = "${
            merge(
              map("Name", format("%s-%s", var.resource_name_prefix, "backup")),
              var.tags,
            )
          }"
}

# ec2 iam role
resource "aws_iam_role" "role" {
  name = "${var.resource_name_prefix}"

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
  depends_on = ["aws_iam_role.role"]

  name   = "${var.resource_name_prefix}-instance-policy"
  role   = "${aws_iam_role.role.id}"
  policy = "${data.template_file.iam_instance_role_policy.rendered}"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  depends_on = ["aws_iam_role.role", "aws_iam_role_policy.policy"]

  name = "${var.resource_name_prefix}-instance"
  role = "${aws_iam_role.role.name}"
}

resource "aws_security_group" "pritunl" {
  name        = "${var.resource_name_prefix}-vpn"
  description = "${var.resource_name_prefix}-vpn"
  vpc_id      = "${var.vpc_id}"

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  # HTTP access
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  # VPN WAN access
  ingress {
    from_port   = 10000
    to_port     = 19999
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ICMP
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = "${
            merge(
              map("Name", format("%s-%s", var.resource_name_prefix, "vpn")),
              var.tags,
            )
          }"
}

resource "aws_security_group" "allow_from_office" {
  name        = "${var.resource_name_prefix}-whitelist"
  description = "Allows SSH connections and HTTP(s) connections from office"
  vpc_id      = "${var.vpc_id}"

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.whitelist}"]
  }

  # HTTP access
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["${var.whitelist}"]
  }

  # ICMP
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["${var.whitelist}"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = "${
            merge(
              map("Name", format("%s-%s", var.resource_name_prefix, "whitelist")),
              var.tags,
            )
          }"
}

resource "aws_instance" "pritunl" {
  ami           = "${var.ami_id}"
  instance_type = "${var.instance_type}"
  key_name      = "${var.aws_key_name}"
  user_data     = "${data.template_file.user_data.rendered}"

  vpc_security_group_ids = [
    "${aws_security_group.pritunl.id}",
    "${aws_security_group.allow_from_office.id}",
  ]

  subnet_id            = "${var.public_subnet_id}"
  iam_instance_profile = "${aws_iam_instance_profile.ec2_profile.name}"

  tags = "${
            merge(
              map("Name", format("%s-%s", var.resource_name_prefix, "vpn")),
              var.tags,
            )
          }"
}

resource "aws_eip" "pritunl" {
  instance = "${aws_instance.pritunl.id}"
  vpc      = true
}
