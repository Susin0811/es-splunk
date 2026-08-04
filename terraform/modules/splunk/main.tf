variable "name_prefix" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "public_subnet_ids" { type = list(string) }

variable "security_group_ids" {
  type = object({
    search_head = string
    indexer     = string
    management  = string
    alb         = string
    bastion     = string
  })
}

variable "key_pair_name" { type = string }

variable "splunk_version" { type = string }
variable "splunk_build" { type = string }
variable "splunk_tarball_s3_uri" { type = string }
variable "splunk_license_uri" { type = string }
variable "splunk_secret_arn" { type = string }

variable "replication_factor" { type = number }
variable "search_factor" { type = number }

variable "search_head_instance_type" { type = string }
variable "indexer_instance_type" { type = string }
variable "management_instance_type" { type = string }
variable "root_volume_size_gb" { type = number }
variable "indexer_data_volume_size_gb" { type = number }

variable "smartstore_bucket_arn" { type = string }
variable "artifacts_bucket_arn" { type = string }
variable "enable_smartstore" { type = bool }

variable "enable_alb" { type = bool }
variable "enable_bastion" { type = bool }
variable "splunk_domain" { type = string }
variable "acm_certificate_arn" { type = string }

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

data "aws_region" "current" {}

locals {
  splunk_common = {
    version        = var.splunk_version
    build          = var.splunk_build
    tarball_uri    = var.splunk_tarball_s3_uri
    license_uri    = var.splunk_license_uri
    secret_arn     = var.splunk_secret_arn
    region         = data.aws_region.current.name
    replication_factor = var.replication_factor
    search_factor      = var.search_factor
    enable_smartstore  = var.enable_smartstore
    smartstore_bucket  = replace(var.smartstore_bucket_arn, "arn:aws:s3:::", "")
  }
}

# ---------------------------------------------------------------------------
# IAM
# ---------------------------------------------------------------------------
resource "aws_iam_role" "splunk" {
  name = "${var.name_prefix}-splunk-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "splunk" {
  name = "${var.name_prefix}-splunk-policy"
  role = aws_iam_role.splunk.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          var.artifacts_bucket_arn,
          "${var.artifacts_bucket_arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [var.splunk_secret_arn]
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = var.enable_smartstore ? [
          var.smartstore_bucket_arn,
          "${var.smartstore_bucket_arn}/*"
        ] : ["arn:aws:s3:::none"]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "splunk" {
  name = "${var.name_prefix}-splunk-profile"
  role = aws_iam_role.splunk.name
}

# ---------------------------------------------------------------------------
# Cluster Manager + Deployment Server (combined)
# ---------------------------------------------------------------------------
resource "aws_instance" "cluster_manager" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.management_instance_type
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [var.security_group_ids.management]
  key_name               = var.key_pair_name
  iam_instance_profile   = aws_iam_instance_profile.splunk.name

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = base64encode(templatefile("${path.module}/templates/user-data-cluster-manager.sh.tpl", merge(local.splunk_common, {
    role = "cluster_manager"
  })))

  tags = {
    Name = "${var.name_prefix}-cluster-manager"
    Role = "cluster-manager"
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

# ---------------------------------------------------------------------------
# Indexers (2 nodes)
# ---------------------------------------------------------------------------
resource "aws_instance" "indexer" {
  count                  = 2
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.indexer_instance_type
  subnet_id              = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  vpc_security_group_ids = [var.security_group_ids.indexer]
  key_name               = var.key_pair_name
  iam_instance_profile   = aws_iam_instance_profile.splunk.name

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = base64encode(templatefile("${path.module}/templates/user-data-indexer.sh.tpl", merge(local.splunk_common, {
    role              = "indexer"
    indexer_id        = count.index + 1
    cluster_manager_ip = aws_instance.cluster_manager.private_ip
  })))

  tags = {
    Name = "${var.name_prefix}-indexer-${count.index + 1}"
    Role = "indexer"
  }

  depends_on = [aws_instance.cluster_manager]

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_ebs_volume" "indexer_data" {
  count             = 2
  availability_zone = aws_instance.indexer[count.index].availability_zone
  size              = var.indexer_data_volume_size_gb
  type              = "gp3"
  encrypted         = true

  tags = { Name = "${var.name_prefix}-indexer-${count.index + 1}-data" }
}

resource "aws_volume_attachment" "indexer_data" {
  count       = 2
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.indexer_data[count.index].id
  instance_id = aws_instance.indexer[count.index].id
}

# ---------------------------------------------------------------------------
# Search Head
# ---------------------------------------------------------------------------
resource "aws_instance" "search_head" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.search_head_instance_type
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [var.security_group_ids.search_head]
  key_name               = var.key_pair_name
  iam_instance_profile   = aws_iam_instance_profile.splunk.name

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = base64encode(templatefile("${path.module}/templates/user-data-search-head.sh.tpl", merge(local.splunk_common, {
    role               = "search_head"
    cluster_manager_ip = aws_instance.cluster_manager.private_ip
    indexer_ips        = join(",", [for i in aws_instance.indexer : i.private_ip])
  })))

  tags = {
    Name = "${var.name_prefix}-search-head"
    Role = "search-head"
  }

  depends_on = [aws_instance.indexer]

  lifecycle {
    ignore_changes = [ami]
  }
}

# ---------------------------------------------------------------------------
# Bastion
# ---------------------------------------------------------------------------
resource "aws_instance" "bastion" {
  count                  = var.enable_bastion ? 1 : 0
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = var.public_subnet_ids[0]
  vpc_security_group_ids = [var.security_group_ids.bastion]
  key_name               = var.key_pair_name

  tags = { Name = "${var.name_prefix}-bastion" }

  lifecycle {
    ignore_changes = [ami]
  }
}

# ---------------------------------------------------------------------------
# Application Load Balancer (optional)
# ---------------------------------------------------------------------------
resource "aws_lb" "search_head" {
  count              = var.enable_alb ? 1 : 0
  name               = "${var.name_prefix}-sh-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.security_group_ids.alb]
  subnets            = var.public_subnet_ids

  tags = { Name = "${var.name_prefix}-search-head-alb" }
}

resource "aws_lb_target_group" "search_head" {
  count    = var.enable_alb ? 1 : 0
  name     = "${var.name_prefix}-sh-tg"
  port     = 8000
  protocol = "HTTPS"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/en-US/account/login"
    protocol            = "HTTPS"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 10
    interval            = 30
  }
}

resource "aws_lb_target_group_attachment" "search_head" {
  count            = var.enable_alb ? 1 : 0
  target_group_arn = aws_lb_target_group.search_head[0].arn
  target_id        = aws_instance.search_head.id
  port             = 8000
}

resource "aws_lb_listener" "https" {
  count             = var.enable_alb ? 1 : 0
  load_balancer_arn = aws_lb.search_head[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.search_head[0].arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  count             = var.enable_alb ? 1 : 0
  load_balancer_arn = aws_lb.search_head[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

output "search_head_private_ip" { value = aws_instance.search_head.private_ip }
output "search_head_instance_id" { value = aws_instance.search_head.id }
output "indexer_private_ips" { value = aws_instance.indexer[*].private_ip }
output "cluster_manager_private_ip" { value = aws_instance.cluster_manager.private_ip }
output "bastion_public_ip" { value = var.enable_bastion ? aws_instance.bastion[0].public_ip : null }
output "alb_dns_name" { value = var.enable_alb ? aws_lb.search_head[0].dns_name : null }
