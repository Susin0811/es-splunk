#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Splunk ES on AWS - Single Deployment Package
# Usage: ./scripts/deploy.sh [plan|apply|destroy]
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
ACTION="${1:-plan}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

check_prerequisites() {
  local missing=0
  for cmd in terraform aws jq; do
    if ! command -v "$cmd" &>/dev/null; then
      log_error "$cmd is not installed"
      missing=1
    fi
  done

  if [ ! -f "$TERRAFORM_DIR/terraform.tfvars" ]; then
    log_error "terraform.tfvars not found. Copy terraform.tfvars.example and configure it."
    missing=1
  fi

  if [ "$missing" -eq 1 ]; then
    exit 1
  fi
}

upload_artifacts() {
  log_info "Checking Splunk tarball in S3..."
  local tarball_uri
  tarball_uri=$(grep splunk_tarball_s3_uri "$TERRAFORM_DIR/terraform.tfvars" | cut -d'"' -f2)
  local bucket key
  bucket=$(echo "$tarball_uri" | sed 's|s3://||' | cut -d'/' -f1)
  key=$(echo "$tarball_uri" | sed 's|s3://||' | cut -d'/' -f2-)

  if aws s3 ls "s3://$bucket/$key" &>/dev/null; then
    log_info "Splunk tarball found at $tarball_uri"
  else
    log_warn "Splunk tarball NOT found at $tarball_uri"
    log_warn "Upload before apply: aws s3 cp <tarball> $tarball_uri"
  fi
}

run_terraform() {
  cd "$TERRAFORM_DIR"

  log_info "Initializing Terraform..."
  terraform init -upgrade

  case "$ACTION" in
    plan)
      log_info "Running terraform plan..."
      terraform plan -out=tfplan
      ;;
    apply)
      upload_artifacts
      log_info "Running terraform apply..."
      terraform apply -auto-approve
      log_info "Deployment complete. Post-deployment steps:"
      terraform output post_deployment_steps
      ;;
    destroy)
      log_warn "Destroying all Splunk ES infrastructure..."
      read -rp "Are you sure? (yes/no): " confirm
      if [ "$confirm" = "yes" ]; then
        terraform destroy -auto-approve
      fi
      ;;
    output)
      terraform output
      ;;
    *)
      log_error "Unknown action: $ACTION. Use plan|apply|destroy|output"
      exit 1
      ;;
  esac
}

check_prerequisites
run_terraform
