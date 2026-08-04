# Splunk Enterprise Security — AWS Deployment Package

A single, Terraform-based deployment package for **Splunk ES 9.3** on AWS. It provisions a small distributed cluster suitable for production pilot or mid-size SOC workloads.

## Architecture

```
                    ┌─────────────────────────────────────────┐
                    │              AWS VPC (10.20.0.0/16)      │
                    │                                          │
  Internet ────────►│  [Bastion]          [ALB] (optional)     │
                    │     │                  │                 │
                    │     │    ┌─────────────▼──────────┐     │
                    │     └───►│     Search Head          │     │
                    │          │  (Splunk ES runs here)   │     │
                    │          └─────────────┬────────────┘     │
                    │                        │ distributed     │
                    │          ┌─────────────▼────────────┐     │
                    │          │   Indexer Cluster (x2)   │     │
                    │          │  RF=2  SF=2  SmartStore  │     │
                    │          └─────────────┬────────────┘     │
                    │                        │                 │
                    │          ┌─────────────▼────────────┐     │
                    │          │  Cluster Manager +       │     │
                    │          │  Deployment Server       │     │
                    │          └──────────────────────────┘     │
                    │                                          │
                    │  S3: SmartStore buckets + Artifacts      │
                    └─────────────────────────────────────────┘
```

| Component | Role | Default Instance |
|-----------|------|----------------|
| Search Head | Splunk Web UI, ES app, search | m6i.2xlarge |
| Indexer x2 | Data ingestion & storage | m6i.2xlarge + 500 GB EBS |
| Cluster Manager | Indexer cluster coordination | m6i.xlarge |
| Deployment Server | App & config distribution | (same as CM) |
| Bastion | SSH jump host | t3.micro |

## Prerequisites

1. **AWS account** with permissions for EC2, VPC, S3, IAM, Secrets Manager
2. **AWS CLI** configured (`aws configure`)
3. **Terraform** >= 1.5.0
4. **EC2 key pair** created in your target region
5. **Splunk Enterprise 9.3** Linux x86_64 tarball ([download from Splunk](https://www.splunk.com/en_us/download/splunk-enterprise.html))
6. **Splunk ES license** and app package (requires Splunk subscription)
7. **Splunk license file** (.lic) for production use

## Quick Start

### 1. Clone and configure

```powershell
cd C:\Users\HP\splunk-es-aws-deploy
copy terraform\terraform.tfvars.example terraform\terraform.tfvars
# Edit terraform.tfvars with your values
```

### 2. Upload Splunk tarball to S3

After the first `terraform apply`, an artifacts bucket is created. For the initial deploy, create a temporary bucket or pre-create one:

```powershell
# Option A: Apply once to create buckets, then upload
# Option B: Upload to a bucket you specify in tfvars
aws s3 cp splunk-9.3.2-c8a72b66b813-Linux-x86_64.tgz s3://your-artifacts-bucket/
```

### 3. Deploy

```powershell
# Preview changes
.\scripts\deploy.ps1 -Action plan

# Deploy infrastructure
.\scripts\deploy.ps1 -Action apply
```

### 4. Post-deployment

```powershell
# View outputs (URLs, IPs, next steps)
.\scripts\deploy.ps1 -Action output

# Install Splunk ES app (requires ES .spl package from Splunk)
bash scripts/install-es-app.sh <cluster-manager-ip> SplunkEnterpriseSecurity-*.spl

# Health check
bash scripts/health-check.sh <search-head-ip> <admin-password>
```

## Configuration Reference

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region | us-east-1 |
| `splunk_version` | Splunk version | 9.3.2 |
| `key_pair_name` | EC2 SSH key pair | (required) |
| `splunk_admin_password` | Admin password | (required) |
| `splunk_tarball_s3_uri` | S3 path to Splunk tgz | (required) |
| `allowed_cidr_blocks` | Networks allowed to access UI | 10.0.0.0/8 |
| `enable_smartstore` | S3-backed warm/cold storage | true |
| `enable_alb` | Public HTTPS load balancer | false |
| `enable_bastion` | SSH bastion host | true |

See `terraform/terraform.tfvars.example` for the full list.

## Splunk ES Installation Notes

Splunk Enterprise Security is a **licensed add-on** not included in this package. After infrastructure deployment:

1. Obtain the ES app (`.spl` or `.tgz`) from [Splunkbase](https://splunkbase.splunk.com/) or your Splunk account rep
2. Deploy via the Deployment Server using `scripts/install-es-app.sh`
3. Apply your ES license on the Search Head
4. Complete the ES Setup Wizard in Splunk Web
5. Configure correlation searches, notable events, and asset/identity frameworks

## Security Considerations

- All EBS volumes are encrypted
- Splunk credentials stored in AWS Secrets Manager
- Instances run in private subnets (no direct public IP on Splunk nodes)
- Security groups restrict ports 8000/8089/9997 to allowed CIDRs
- S3 buckets block public access
- Use `allowed_cidr_blocks` to limit UI access to your corporate network

## Cost Estimate (us-east-1, on-demand)

| Resource | Approx. Monthly |
|----------|----------------|
| 1x m6i.2xlarge (SH) | ~$280 |
| 2x m6i.2xlarge (Indexers) | ~$560 |
| 1x m6i.xlarge (CM/DS) | ~$140 |
| 2x 500 GB gp3 EBS | ~$80 |
| NAT Gateway | ~$45 |
| S3 SmartStore (varies) | ~$23/TB |
| **Total (compute only)** | **~$1,100/mo** |

Use Reserved Instances or Savings Plans for 30–60% savings.

## Troubleshooting

| Issue | Resolution |
|-------|-----------|
| User-data failed | Check `/var/log/splunk-bootstrap.log` on the instance via bastion SSH |
| Indexer not joining cluster | Verify cluster manager is running; check secret key matches |
| Cannot reach Web UI | Confirm `allowed_cidr_blocks`; use bastion + private IP or enable ALB |
| SmartStore errors | Verify IAM role has S3 permissions; check bucket name in indexes.conf |

## Directory Structure

```
splunk-es-aws-deploy/
├── README.md
├── scripts/
│   ├── deploy.ps1          # Windows deploy wrapper
│   ├── deploy.sh           # Linux/macOS deploy wrapper
│   ├── install-es-app.sh   # Post-deploy ES app install
│   └── health-check.sh     # Cluster health verification
└── terraform/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── terraform.tfvars.example
    └── modules/
        ├── vpc/              # VPC, subnets, NAT
        ├── security/         # Security groups
        ├── s3/               # SmartStore + artifacts buckets
        └── splunk/           # EC2 instances, IAM, ALB
            └── templates/    # User-data bootstrap scripts
```

## License

Infrastructure code is provided as-is. Splunk Enterprise and Splunk ES require separate commercial licenses from Splunk Inc.
