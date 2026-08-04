data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 2)

  name_prefix = "${var.project_name}-${var.environment}"

  splunk_tarball_filename = "splunk-${var.splunk_version}-${var.splunk_build}-Linux-x86_64.tgz"
}

# ---------------------------------------------------------------------------
# Secrets
# ---------------------------------------------------------------------------
resource "random_password" "splunk_secret_key" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "splunk_credentials" {
  name                    = "${local.name_prefix}-splunk-credentials"
  description             = "Splunk admin credentials and secret key"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "splunk_credentials" {
  secret_id = aws_secretsmanager_secret.splunk_credentials.id
  secret_string = jsonencode({
    admin_password = var.splunk_admin_password
    secret_key     = random_password.splunk_secret_key.result
  })
}

# ---------------------------------------------------------------------------
# Modules
# ---------------------------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  availability_zones = local.azs
  enable_nat_gateway = var.enable_nat_gateway
}

module "security" {
  source = "./modules/security"

  name_prefix         = local.name_prefix
  vpc_id              = module.vpc.vpc_id
  allowed_cidr_blocks = var.allowed_cidr_blocks
}

module "s3" {
  source = "./modules/s3"

  name_prefix               = local.name_prefix
  enable_smartstore         = var.enable_smartstore
  smartstore_retention_days = var.smartstore_retention_days
}

module "splunk" {
  source = "./modules/splunk"

  name_prefix = local.name_prefix
  vpc_id      = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids

  security_group_ids = {
    search_head = module.security.search_head_sg_id
    indexer     = module.security.indexer_sg_id
    management  = module.security.management_sg_id
    alb         = module.security.alb_sg_id
    bastion     = module.security.bastion_sg_id
  }

  key_pair_name = var.key_pair_name

  splunk_version        = var.splunk_version
  splunk_build          = var.splunk_build
  splunk_tarball_s3_uri = var.splunk_tarball_s3_uri
  splunk_license_uri    = var.splunk_license_uri
  splunk_secret_arn     = aws_secretsmanager_secret.splunk_credentials.arn

  replication_factor = var.indexer_replication_factor
  search_factor      = var.indexer_search_factor

  search_head_instance_type  = var.search_head_instance_type
  indexer_instance_type      = var.indexer_instance_type
  management_instance_type     = var.management_instance_type
  root_volume_size_gb          = var.root_volume_size_gb
  indexer_data_volume_size_gb  = var.indexer_data_volume_size_gb

  smartstore_bucket_arn = module.s3.smartstore_bucket_arn
  artifacts_bucket_arn  = module.s3.artifacts_bucket_arn
  enable_smartstore     = var.enable_smartstore

  enable_alb    = var.enable_alb
  enable_bastion = var.enable_bastion
  splunk_domain = var.splunk_domain
  acm_certificate_arn = var.acm_certificate_arn
}
