data "aws_region" "current" {
  current = true
}

data "template_file" "user_data" {
  template = "${file("${path.module}/templates/user_data.sh.tpl")}"

  vars {
    aws_region           = "${aws_region.current.name}"
    s3_backup_bucket     = "${var.tag_product}-${var.tag_env}-backup"
    credstash_table_name = "credstash-${var.tag_product}-${var.tag_env}"
  }
}

resource "aws_s3_bucket" "backup" {
  bucket = "${var.tag_product}-${var.tag_env}-backup"
  acl = "private"

  lifecycle_rule {
    prefix  = "backups"
    enabled = true

    expiration {
      days = 30
    }

    abort_incomplete_multipart_upload_days = 7
  }

  tags {
    Name    = "${var.tag_product}-${var.tag_env}-backup"
    product = "${var.tag_product}"
    env     = "${var.tag_env}"
    purpose = "${var.tag_purpose}"
    role    = "${var.tag_role}"
  }
}

# ec2 iam role
resource "aws_iam_role" "role" {
  name               = "${var.tag_product}-${var.tag_env}"
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

  name   = "${var.tag_product}-${var.tag_env}"
  role   = "${aws_iam_role.role.id}"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
      {
          "Effect": "Allow",
          "Action": [
              "kms:*",
              "dynamodb:*"
          ],
          "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Action": [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ],
        "Resource": [ "arn:aws:s3:::${var.tag_product}-${var.tag_env}-backup" ]
      },
      {
        "Effect": "Allow",
        "Action": [
          "s3:AbortMultipartUpload",
          "s3:PutObject*",
          "s3:Get*",
          "s3:List*",
          "s3:DeleteObject"
        ],
        "Resource": [ "arn:aws:s3:::${var.tag_product}-${var.tag_env}-backup/*" ]
      },
      {
        "Effect": "Allow",
        "Action": [
            "ssm:DescribeAssociation",
            "ssm:GetDocument",
            "ssm:ListAssociations",
            "ssm:UpdateAssociationStatus",
            "ssm:UpdateInstanceInformation"
        ],
        "Resource": "*"
      },
      {
          "Effect": "Allow",
          "Action": [
              "ec2messages:AcknowledgeMessage",
              "ec2messages:DeleteMessage",
              "ec2messages:FailMessage",
              "ec2messages:GetEndpoint",
              "ec2messages:GetMessages",
              "ec2messages:SendReply"
          ],
          "Resource": "*"
      },
      {
          "Effect": "Allow",
          "Action": [
              "cloudwatch:PutMetricData"
          ],
          "Resource": "*"
      },
      {
          "Effect": "Allow",
          "Action": [
              "ec2:DescribeInstanceStatus"
          ],
          "Resource": "*"
      },
      {
          "Effect": "Allow",
          "Action": [
              "ds:CreateComputer",
              "ds:DescribeDirectories"
          ],
          "Resource": "*"
      },
      {
          "Effect": "Allow",
          "Action": [
              "logs:CreateLogGroup",
              "logs:CreateLogStream",
              "logs:DescribeLogGroups",
              "logs:DescribeLogStreams",
              "logs:PutLogEvents"
          ],
          "Resource": "*"
      }
    ]
}
EOF
}

resource "aws_iam_instance_profile" "ec2_profile" {

  depends_on = ["aws_iam_role.role", "aws_iam_role_policy.policy"]

  name  = "${var.tag_product}-${var.tag_env}"
  roles = ["${aws_iam_role.role.name}"]
}

resource "aws_security_group" "pritunl" {
  name        = "${var.tag_product}-${var.tag_env}-pritunl-vpn"
  description = "${var.tag_product}-${var.tag_env}-pritunl-vpn"
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

  tags {
    Name    = "${var.tag_product}-${var.tag_env}-pritunl-vpn"
    product = "${var.tag_product}"
    env     = "${var.tag_env}"
    purpose = "${var.tag_purpose}"
    role    = "${var.tag_role}"
  }
}

resource "aws_security_group" "allow_from_office" {
  name        = "${var.tag_product}-${var.tag_env}-allow-from-office"
  description = "Allows SSH connections and HTTP(s) connections from office"
  vpc_id      = "${var.vpc_id}"

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.office_ip_cidrs}"]
  }

  # HTTP access
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["${var.office_ip_cidrs}"]
  }

  # ICMP
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["${var.office_ip_cidrs}"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name    = "${var.tag_product}-${var.tag_env}-allow-from-office"
    product = "${var.tag_product}"
    env     = "${var.tag_env}"
    purpose = "${var.tag_purpose}"
    role    = "${var.tag_role}"
  }
}

resource "aws_instance" "pritunl" {
  ami                    = "${var.ami_id}"
  instance_type          = "${var.instance_type}"
  key_name               = "${var.aws_key_name}"
  user_data              = "${data.template_file.user_data.rendered}"
  vpc_security_group_ids = [
    "${aws_security_group.pritunl.id}",
    "${aws_security_group.allow_from_office.id}"
  ]
  subnet_id              = "${var.public_subnet_id}"
  iam_instance_profile   = "${aws_iam_instance_profile.ec2_profile.name}"

  tags {
    Name    = "${var.tag_product}-${var.tag_env}-vpn"
    product = "${var.tag_product}"
    env     = "${var.tag_env}"
    purpose = "${var.tag_purpose}"
    role    = "${var.tag_role}"
  }
}

resource "aws_eip" "pritunl" {
    instance = "${aws_instance.pritunl.id}"
    vpc      = true
}
