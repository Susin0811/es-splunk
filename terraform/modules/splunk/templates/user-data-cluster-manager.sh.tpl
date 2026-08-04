#!/bin/bash
# Cluster Manager + Deployment Server bootstrap
set -euo pipefail

SPLUNK_VERSION="${version}"
SPLUNK_BUILD="${build}"
TARBALL_URI="${tarball_uri}"
LICENSE_URI="${license_uri}"
SECRET_ARN="${secret_arn}"
AWS_REGION="${region}"
REPLICATION_FACTOR="${replication_factor}"
SEARCH_FACTOR="${search_factor}"

exec > >(tee /var/log/splunk-bootstrap.log) 2>&1
echo "=== Splunk Cluster Manager bootstrap started at $(date) ==="

# Install dependencies
dnf install -y awscli jq

# Mount and format if needed (root only for management node)
mkdir -p /opt/splunk

# Download Splunk credentials from Secrets Manager
SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --region "$AWS_REGION" --query SecretString --output text)
ADMIN_PASSWORD=$(echo "$SECRET_JSON" | jq -r .admin_password)
SECRET_KEY=$(echo "$SECRET_JSON" | jq -r .secret_key)

# Download Splunk tarball from S3
TARBALL_PATH="/tmp/splunk.tgz"
aws s3 cp "$TARBALL_URI" "$TARBALL_PATH" --region "$AWS_REGION"

# Install Splunk
tar -xzf "$TARBALL_PATH" -C /opt/
useradd -r -m -d /opt/splunk splunk || true
chown -R splunk:splunk /opt/splunk

# Start Splunk and set credentials
/opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt --seed-passwd "$ADMIN_PASSWORD"

# Enable boot-start
/opt/splunk/bin/splunk enable boot-start -user splunk --accept-license --answer-yes

# Apply license if provided
if [ -n "$LICENSE_URI" ]; then
  aws s3 cp "$LICENSE_URI" /tmp/splunk.lic --region "$AWS_REGION"
  /opt/splunk/bin/splunk add licenser /tmp/splunk.lic -auth admin:"$ADMIN_PASSWORD"
fi

# Configure as Cluster Manager (master)
/opt/splunk/bin/splunk edit indexer-cluster master-uri -mode master \
  -replication_factor "$REPLICATION_FACTOR" \
  -search_factor "$SEARCH_FACTOR" \
  -secret "$SECRET_KEY" \
  -auth admin:"$ADMIN_PASSWORD"

# Configure as Deployment Server
/opt/splunk/bin/splunk set deploy-poll $(hostname -f) -auth admin:"$ADMIN_PASSWORD"

# Create deployment-apps directory structure for ES
mkdir -p /opt/splunk/etc/deployment-apps/SplunkEnterpriseSecuritySuite/local
mkdir -p /opt/splunk/etc/deployment-apps/all_indexer_base/local
mkdir -p /opt/splunk/etc/deployment-apps/all_search_base/local

# Base indexer outputs.conf
cat > /opt/splunk/etc/deployment-apps/all_indexer_base/local/outputs.conf << 'EOF'
[tcpout:splunk_indexers]
defaultGroup = splunk_indexers

[tcpout]
disabled = false

[tcpout:splunk_indexers]
servers = PLACEHOLDER_INDEXERS
EOF

chown -R splunk:splunk /opt/splunk/etc/deployment-apps

# Restart to apply cluster manager config
/opt/splunk/bin/splunk restart

echo "=== Cluster Manager bootstrap complete at $(date) ==="
