# ---------------------------------------------------------------------------
# General
# ---------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used as prefix for resource naming"
  type        = string
  default     = "splunk-es"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "prod"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the Splunk VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs (leave empty to auto-detect first two in region)"
  type        = list(string)
  default     = []
}

variable "enable_nat_gateway" {
  description = "Deploy NAT gateway for private subnet outbound access"
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access Splunk Web UI (port 8000) and management (8089)"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "key_pair_name" {
  description = "Existing EC2 key pair name for SSH access"
  type        = string
}

# ---------------------------------------------------------------------------
# Splunk Configuration
# ---------------------------------------------------------------------------
variable "splunk_version" {
  description = "Splunk Enterprise version to install"
  type        = string
  default     = "9.3.2"
}

variable "splunk_build" {
  description = "Splunk Enterprise build number"
  type        = string
  default     = "c8a72b66b813"
}

variable "splunk_admin_password" {
  description = "Splunk admin password (min 8 chars). Stored in Secrets Manager."
  type        = string
  sensitive   = true
}

variable "splunk_tarball_s3_uri" {
  description = "S3 URI to Splunk Enterprise Linux x86_64 tarball (e.g. s3://my-bucket/splunk-9.3.2.tgz). Upload tarball before deploy."
  type        = string
}

variable "splunk_license_uri" {
  description = "Optional S3 URI to Splunk license file (.lic). Required for production."
  type        = string
  default     = ""
}

variable "indexer_replication_factor" {
  description = "Indexer cluster replication factor"
  type        = number
  default     = 2
}

variable "indexer_search_factor" {
  description = "Indexer cluster search factor"
  type        = number
  default     = 2
}

# ---------------------------------------------------------------------------
# EC2 Instance Sizing
# ---------------------------------------------------------------------------
variable "search_head_instance_type" {
  description = "EC2 instance type for Search Head (ES requires adequate memory)"
  type        = string
  default     = "m6i.2xlarge"
}

variable "indexer_instance_type" {
  description = "EC2 instance type for Indexer nodes"
  type        = string
  default     = "m6i.2xlarge"
}

variable "management_instance_type" {
  description = "EC2 instance type for Cluster Manager + Deployment Server"
  type        = string
  default     = "m6i.xlarge"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB for all Splunk instances"
  type        = number
  default     = 100
}

variable "indexer_data_volume_size_gb" {
  description = "Additional EBS data volume size in GB per indexer"
  type        = number
  default     = 500
}

# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------
variable "enable_smartstore" {
  description = "Enable S3 SmartStore for indexer warm/cold buckets"
  type        = bool
  default     = true
}

variable "smartstore_retention_days" {
  description = "S3 lifecycle retention for SmartStore objects (0 = no expiration)"
  type        = number
  default     = 365
}

# ---------------------------------------------------------------------------
# Optional Features
# ---------------------------------------------------------------------------
variable "enable_alb" {
  description = "Deploy Application Load Balancer in front of Search Head Web UI"
  type        = bool
  default     = false
}

variable "enable_bastion" {
  description = "Deploy a bastion host in public subnet for SSH jump access"
  type        = bool
  default     = true
}

variable "splunk_domain" {
  description = "Optional domain name for ALB (requires ACM certificate ARN)"
  type        = string
  default     = ""
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS on ALB"
  type        = string
  default     = ""
}
