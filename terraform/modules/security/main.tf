variable "name_prefix" { type = string }
variable "vpc_id" { type = string }
variable "allowed_cidr_blocks" { type = list(string) }

resource "aws_security_group" "search_head" {
  name        = "${var.name_prefix}-search-head-sg"
  description = "Splunk Search Head - Web UI and API"
  vpc_id      = var.vpc_id

  ingress {
    description = "Splunk Web UI"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    description = "Splunk Management API"
    from_port   = 8089
    to_port     = 8089
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    description = "KV Store"
    from_port   = 8191
    to_port     = 8191
    protocol    = "tcp"
    cidr_blocks = [var.vpc_id != "" ? data.aws_vpc.main.cidr_block : "10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-search-head-sg" }
}

data "aws_vpc" "main" {
  id = var.vpc_id
}

resource "aws_security_group" "indexer" {
  name        = "${var.name_prefix}-indexer-sg"
  description = "Splunk Indexer - receiving and cluster communication"
  vpc_id      = var.vpc_id

  ingress {
    description = "Splunk receiving (forwarders)"
    from_port   = 9997
    to_port     = 9997
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    description = "Splunk management"
    from_port   = 8089
    to_port     = 8089
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.main.cidr_block]
  }

  ingress {
    description = "Indexer cluster replication"
    from_port   = 9887
    to_port     = 9887
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-indexer-sg" }
}

resource "aws_security_group" "management" {
  name        = "${var.name_prefix}-management-sg"
  description = "Cluster Manager and Deployment Server"
  vpc_id      = var.vpc_id

  ingress {
    description = "Splunk management"
    from_port   = 8089
    to_port     = 8089
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.main.cidr_block]
  }

  ingress {
    description = "Deployment server"
    from_port   = 8089
    to_port     = 8089
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-management-sg" }
}

resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "ALB for Splunk Web UI"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    description = "HTTP redirect"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-alb-sg" }
}

resource "aws_security_group" "bastion" {
  name        = "${var.name_prefix}-bastion-sg"
  description = "SSH bastion host"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-bastion-sg" }
}

# Allow Search Head to receive from ALB
resource "aws_security_group_rule" "search_head_from_alb" {
  type                     = "ingress"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.search_head.id
}

# Allow bastion SSH to all Splunk nodes
resource "aws_security_group_rule" "search_head_ssh_from_bastion" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.search_head.id
}

resource "aws_security_group_rule" "indexer_ssh_from_bastion" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.indexer.id
}

resource "aws_security_group_rule" "management_ssh_from_bastion" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.management.id
}

output "search_head_sg_id" { value = aws_security_group.search_head.id }
output "indexer_sg_id" { value = aws_security_group.indexer.id }
output "management_sg_id" { value = aws_security_group.management.id }
output "alb_sg_id" { value = aws_security_group.alb.id }
output "bastion_sg_id" { value = aws_security_group.bastion.id }
