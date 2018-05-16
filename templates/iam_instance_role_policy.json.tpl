{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ],
        "Effect": "Allow",
        "Resource": "${db_credstash_arn}"
      },
      {
        "Effect": "Allow",
        "Action": [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ],
        "Resource": [ "arn:aws:s3:::${resource_name_prefix}-backup" ]
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
        "Resource": [ "arn:aws:s3:::${resource_name_prefix}-backup/*" ]
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
