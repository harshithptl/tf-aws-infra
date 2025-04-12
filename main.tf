provider "aws" {
  region  = var.region
  profile = var.profile
}

data "aws_caller_identity" "current" {}

resource "random_id" "vpc_suffix" {
  byte_length = 4
}
resource "random_id" "igw_suffix" {
  byte_length = 4
}

resource "random_id" "public_subnet_suffix" {
  count       = length(var.public_subnets)
  byte_length = 4
}

resource "random_id" "private_subnet_suffix" {
  count       = length(var.private_subnets)
  byte_length = 4
}

resource "random_id" "public_route_table_suffix" {
  byte_length = 4
}

resource "random_id" "private_route_table_suffix" {
  byte_length = 4
}

resource "aws_vpc" "main_vpc" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "MainVPC-${random_id.vpc_suffix.hex}"
  }
}

resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "InternetGateway-${random_id.igw_suffix.hex}"
  }
}

resource "aws_subnet" "public_subnets" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = var.public_subnets[count.index].cidr_block
  availability_zone       = var.public_subnets[count.index].az
  map_public_ip_on_launch = true

  tags = {
    Name = "PublicSubnet-${random_id.public_subnet_suffix[count.index].hex}"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = var.private_subnets[count.index].cidr_block
  availability_zone = var.private_subnets[count.index].az

  tags = {
    Name = "PrivateSubnet-${random_id.private_subnet_suffix[count.index].hex}"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "PublicRouteTable-${random_id.public_route_table_suffix.hex}"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main_igw.id
}

resource "aws_route_table_association" "public_assoc" {
  count          = length(var.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "PrivateRouteTable-${random_id.private_route_table_suffix.hex}"
  }
}

resource "aws_route_table_association" "private_assoc" {
  count          = length(var.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_security_group" "lb_sg" {
  name        = "lb-sg"
  description = "Security group for the load balancer"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    description = "Allow HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "LB-SG"
  }
}



#######################################
# EC2 Setup
#######################################

resource "aws_security_group" "app_sg" {
  name        = "app-sg"
  description = "Security group for web application instances"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    description     = "SSH"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
    security_groups = [aws_security_group.lb_sg.id]
  }

  ingress {
    description     = "HTTP"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
  }

  ingress {
    description     = "HTTPS"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
  }

  ingress {
    description     = "Custom app port"
    from_port       = var.application_port
    to_port         = var.application_port
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "App-SG"
  }
}

resource "aws_iam_role" "ec2_role" {
  name = "webapp-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "ec2_secrets_policy" {
  name        = "EC2SecretsPolicy"
  description = "Allows EC2 instances to retrieve DB credentials from Secrets Manager and decrypt them using the secrets KMS key"
  policy      = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "AllowSecretsRetrieval",
        "Effect": "Allow",
        "Action": [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ],
        "Resource": "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:db-secret-*"
      },
      {
        "Sid": "AllowKMSDecryptForSecrets",
        "Effect": "Allow",
        "Action": "kms:Decrypt",
        "Resource": aws_kms_key.secrets_kms.arn
      }
    ]
  })
}


resource "aws_iam_policy" "s3_policy" {
  name        = "webapp-s3-policy"
  description = "Policy for webapp EC2 instance to access S3"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.attachments.arn,
          "${aws_s3_bucket.attachments.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "webapp-instance-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_iam_role_policy_attachment" "attach_ec2_secrets_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_secrets_policy.arn
}

resource "aws_iam_role_policy_attachment" "attach_s3_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_policy.arn
}

resource "aws_iam_policy" "cloudwatch_policy" {
  name        = "webapp-cloudwatch-policy"
  description = "Policy for EC2 instance to publish CloudWatch logs and metrics"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_cloudwatch_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.cloudwatch_policy.arn
}

# Application Load Balancer
resource "aws_lb" "app_alb" {
  name               = "csye6225-app-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = [for subnet in aws_subnet.public_subnets : subnet.id]
  ip_address_type    = "ipv4"

  tags = {
    Name = "App-ALB"
  }
}

# Target Group
resource "aws_lb_target_group" "app_tg" {
  name     = "csye6225-app-tg"
  port     = var.application_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.main_vpc.id

  # Example health check for /health (adjust path as needed)
  health_check {
    protocol = "HTTP"
    path     = "/health"
    port     = var.application_port
  }

  tags = {
    Name = "App-TG"
  }
}

# ALB Listener
resource "aws_lb_listener" "app_http_listener" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

resource "aws_launch_template" "csye6225_asg" {
  depends_on = [aws_kms_key.ec2_kms]
  name_prefix   = "csye6225-asg-"
  image_id      = var.custom_ami
  instance_type = var.aws_instance_type

  vpc_security_group_ids = [aws_security_group.app_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_instance_profile.name
  }

  key_name = var.key_pair

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20
      volume_type           = "gp2"
      encrypted             = true
      kms_key_id            = aws_kms_key.ec2_kms.arn
      delete_on_termination = true
    }
  }

  user_data = base64encode(
    templatefile(
      "./user_data.sh",
      {
        db_endpoint = aws_db_instance.db_instance.endpoint
        db_name     = var.dbname
        s3_bucket   = aws_s3_bucket.attachments.bucket
        region      = var.region
        secret_id   = aws_secretsmanager_secret.db_secret.name
      }
    )
  )

  tag_specifications {
    resource_type = "instance" # Changed from "load-balancer-instance" to "instance"
    tags = {
      Name = "LB-Instance"
    }
  }
}


resource "aws_autoscaling_group" "app_asg" {
  name                = "csye6225-app-asg"
  max_size            = 5
  min_size            = 3
  desired_capacity    = 3
  vpc_zone_identifier = [for subnet in aws_subnet.public_subnets : subnet.id]

  launch_template {
    id      = aws_launch_template.csye6225_asg.id
    version = "$Latest"
  }

  target_group_arns = [
    aws_lb_target_group.app_tg.arn
  ]

  tag {
    key                 = "Name"
    value               = "csye6225-asg-instance"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}


########################################
# SCALE OUT POLICY & ALARM
########################################
resource "aws_autoscaling_policy" "app_scale_out" {
  name                   = "csye6225-scale-out"
  policy_type            = "SimpleScaling"
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
  scaling_adjustment     = 1
  cooldown               = 60
}

resource "aws_cloudwatch_metric_alarm" "high_cpu_alarm" {
  alarm_name          = "csye6225-high-cpu"
  alarm_description   = "Alarm when CPU usage > 5%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 5

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app_asg.name
  }

  alarm_actions = [
    aws_autoscaling_policy.app_scale_out.arn
  ]
}

########################################
# SCALE IN POLICY & ALARM
########################################
resource "aws_autoscaling_policy" "app_scale_in" {
  name                   = "csye6225-scale-in"
  policy_type            = "SimpleScaling"
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
  scaling_adjustment     = -1
  cooldown               = 60
}

resource "aws_cloudwatch_metric_alarm" "low_cpu_alarm" {
  alarm_name          = "csye6225-low-cpu"
  alarm_description   = "Alarm when CPU usage < 3%"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 3

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app_asg.name
  }

  alarm_actions = [
    aws_autoscaling_policy.app_scale_in.arn
  ]
}


#######################################
# S3 Bucket Setup
#######################################

resource "random_uuid" "attachments_s3_name" {
}

resource "aws_s3_bucket" "attachments" {
  bucket        = random_uuid.attachments_s3_name.result
  force_destroy = true

  tags = {
    Name = "Attachments-Bucket"
  }
}

resource "aws_s3_bucket_public_access_block" "attachments_block_public" {
  bucket                  = aws_s3_bucket.attachments.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "attachments_encryption" {
  depends_on = [aws_kms_key.s3_kms]
  bucket = aws_s3_bucket.attachments.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_kms.arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "attachments_lifecycle" {
  bucket = aws_s3_bucket.attachments.id

  rule {
    id     = "transition-to-standard-ia"
    status = "Enabled"
    filter {
      prefix = ""
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

#######################################
# DATABASE SECURITY GROUP
#######################################
resource "aws_security_group" "db_sg" {
  name        = "db-sg"
  description = "Security group for the RDS instance"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    description     = "Postgres Ingress from App SG"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "DB-SG"
  }
}

#######################################
# DB PARAMETER GROUP
#######################################
resource "aws_db_parameter_group" "db_pg" {
  name        = "postgres-custom-pg"
  family      = "postgres17"
  description = "Custom parameter group for Postgres 17"
}

#######################################
# DB SUBNET GROUP
#######################################
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "csye6225-db-subnet-group"
  subnet_ids = [for subnet in aws_subnet.private_subnets : subnet.id]

  tags = {
    Name = "DB-Subnet-Group"
  }
}

#######################################
# RDS INSTANCE
#######################################
resource "aws_db_instance" "db_instance" {
  depends_on = [aws_kms_key.rds_kms]
  identifier             = "csye6225"
  engine                 = "postgres"
  engine_version         = "17.4"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  max_allocated_storage  = 100
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  storage_encrypted      = true
  kms_key_id             = aws_kms_key.rds_kms.arn

  # Basic config
  multi_az            = false
  publicly_accessible = false
  storage_type        = "gp2"

  # Parameter group
  parameter_group_name = aws_db_parameter_group.db_pg.name

  # Credentials
  username = var.dbuser
  password = random_password.db_pass.result

  # Database name
  db_name = var.dbname


  skip_final_snapshot = true
  deletion_protection = false

  tags = {
    Name = "HealthzDb"
  }
}

data "aws_route53_zone" "my_domain" {
  name         = var.hosted_zone
  private_zone = false
}


resource "aws_route53_record" "lb_alias" {
  zone_id = data.aws_route53_zone.my_domain.zone_id

  name = var.instancetld

  type = "A"

  alias {
    name                   = aws_lb.app_alb.dns_name
    zone_id                = aws_lb.app_alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_kms_key" "ec2_kms" {
  description         = "KMS key for encrypting EC2 volumes"
  enable_key_rotation = true
  policy = <<-EOF
{
  "Version": "2012-10-17",
  "Id": "ec2-kms-policy",
  "Statement": [
    {
      "Sid": "Allow administration of the key",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${data.aws_caller_identity.current.arn}"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "Allow Auto Scaling to use the key",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
      },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Allow Auto Scaling to create grants for encrypted volumes",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
      },
      "Action": "kms:CreateGrant",
      "Resource": "*",
      "Condition": {
        "Bool": {
          "kms:GrantIsForAWSResource": "true"
        }
      }
    }
  ]
}
EOF

  tags = {
    Name = "ec2-kms-key"
  }
}



resource "aws_kms_key" "rds_kms" {
  description         = "KMS key for encrypting RDS"
  enable_key_rotation = true
  policy              = <<-EOF
{
  "Version": "2012-10-17",
  "Id": "rds-kms-policy",
  "Statement": [
    {
      "Sid": "Allow administration of the key",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${data.aws_caller_identity.current.arn}"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "Allow RDS to use the key for encryption of RDS resources",
      "Effect": "Allow",
      "Principal": {
        "Service": "rds.amazonaws.com"
      },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    }
  ]
}
EOF

  tags = {
    Name = "rds-kms-key"
  }
}


resource "aws_kms_key" "s3_kms" {
  description         = "KMS key for S3 bucket encryption"
  enable_key_rotation = true
  policy              = <<-EOF
{
  "Version": "2012-10-17",
  "Id": "s3-kms-policy",
  "Statement": [
    {
      "Sid": "Allow administration of the key",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${data.aws_caller_identity.current.arn}"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "Allow S3 to use the key",
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
        "kms:CreateGrant"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Allow EC2 role to use the key",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::225989346736:role/webapp-ec2-role"
      },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
        "kms:CreateGrant"
      ],
      "Resource": "*"
    }
  ]
}
EOF

  tags = {
    Name = "s3-kms-key"
  }
}



resource "aws_kms_key" "secrets_kms" {
  description         = "KMS key for Secrets Manager"
  enable_key_rotation = true
  policy              = <<-EOF
{
  "Version": "2012-10-17",
  "Id": "secrets-kms-policy",
  "Statement": [
    {
      "Sid": "Allow administration of the key",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${data.aws_caller_identity.current.arn}"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "Allow Secrets Manager to use the key",
      "Effect": "Allow",
      "Principal": {
        "Service": "secretsmanager.amazonaws.com"
      },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowInstanceRoleToDecrypt",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/webapp-ec2-role"
      },
      "Action": "kms:Decrypt",
      "Resource": "*"
    }
  ]
}
EOF

  tags = {
    Name = "secrets-kms-key"
  }
}

resource "random_id" "db_secret_suffix" {
  byte_length = 4
}

resource "aws_secretsmanager_secret" "db_secret" {
  depends_on = [aws_kms_key.secrets_kms]
  name        = "db-secret-${random_id.db_secret_suffix.hex}"
  kms_key_id  = aws_kms_key.secrets_kms.arn
  description = "Stores the database credentials"

  # Optionally define a recovery window
  recovery_window_in_days = 7
  tags = {
    Name = "db-secret"
  }
}

resource "random_password" "db_pass" {
  length           = 16
  special          = true
  override_special = "!#$%*"
}

resource "aws_secretsmanager_secret_version" "db_secret_v" {
  secret_id = aws_secretsmanager_secret.db_secret.id
  secret_string = jsonencode({
    username = var.dbuser
    password = random_password.db_pass.result
  })
}

resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08" # You may choose another policy as needed
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}







