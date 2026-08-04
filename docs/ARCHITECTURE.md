# Splunk ES AWS Architecture

## Deployment Topology

This package deploys a **small distributed** Splunk Enterprise Security environment:

- **1 Search Head** — hosts Splunk Web, ES correlation searches, dashboards
- **2 Indexers** — form an indexer cluster with RF=2, SF=2
- **1 Cluster Manager** — coordinates indexer cluster bundle pushes
- **1 Deployment Server** — co-located with Cluster Manager; distributes apps and configs

## Network Layout

| Subnet | CIDR | Purpose |
|--------|------|---------|
| Public AZ-a | 10.20.0.0/20 | Bastion, NAT Gateway, ALB |
| Public AZ-b | 10.20.1.0/20 | ALB (multi-AZ) |
| Private AZ-a | 10.20.8.0/20 | Search Head, Indexer 1, CM/DS |
| Private AZ-b | 10.20.9.0/20 | Indexer 2 |

## Port Reference

| Port | Protocol | Source | Destination | Purpose |
|------|----------|--------|-------------|---------|
| 8000 | TCP | Allowed CIDRs / ALB | Search Head | Splunk Web UI |
| 8089 | TCP | VPC CIDR | All Splunk nodes | Management API |
| 9997 | TCP | Allowed CIDRs | Indexers | Forwarder data input |
| 9887 | TCP | VPC CIDR | Indexers | Cluster replication |
| 8191 | TCP | VPC CIDR | Search Head | KV Store |
| 22 | TCP | Allowed CIDRs | Bastion | SSH |

## Bootstrap Sequence

1. **Cluster Manager** starts first — installs Splunk, enables cluster manager mode
2. **Indexers** join as peers — mount data volumes, configure SmartStore, apply cluster bundle
3. **Search Head** last — adds indexers as search peers, registers with deployment server

Each node pulls its Splunk tarball and credentials from S3/Secrets Manager via IAM instance profile.

## SmartStore

When enabled, warm/cold buckets are stored in S3 rather than local EBS. Benefits:

- Lower storage cost for historical data
- Faster bucket recovery after indexer failure
- Independent scaling of compute and storage

Hot buckets remain on local EBS (`/splunkdata`) for write performance.

## High Availability Notes

This topology provides:

- Data redundancy via replication factor 2
- Multi-AZ indexer placement
- Encrypted EBS and S3

It does **not** include:

- Search Head clustering (single SH — add SHC module for HA search)
- Multi-region DR
- Automatic failover for Cluster Manager

For production HA, consider adding Search Head Cluster (3 members) and a dedicated Cluster Manager with standby.

## ES-Specific Configuration

After infrastructure deployment, configure these ES components manually or via Deployment Server apps:

| Component | Location | Notes |
|-----------|----------|-------|
| ES App | Search Head | Deploy via DS; requires ES license |
| Correlation searches | ES app | Enabled via ES Setup Wizard |
| Asset & Identity | ES app | Configure inputs for AD, CMDB, etc. |
| Notable events | ES app | Review index retention (default 90 days) |
| CIM data models | All indexers | Ensure field extractions are deployed |

## Scaling Path

| Growth Stage | Action |
|--------------|--------|
| More data volume | Add indexers (update Terraform `indexer` count) |
| More concurrent searches | Add Search Head Cluster members |
| More forwarders | Indexers auto-balance; add indexers if ingestion lag |
| Longer retention | Increase SmartStore retention or add archive tier |
