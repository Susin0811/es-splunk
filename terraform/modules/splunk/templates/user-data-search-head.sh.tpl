#!/bin/bash
# Search Head bootstrap (Splunk ES target node)
set -euo pipefail

SPLUNK_VERSION="${version}"
SPLUNK_BUILD="${build}"
TARBALL_URI="${tarball_uri}"
LICENSE_URI="${license_uri}"
SECRET_ARN="${secret_arn}"
AWS_REGION="${region}"
CLUSTER_MANAGER_IP="${cluster_manager_ip}"
INDEXER_IPS="${indexer_ips}"

exec > >(tee /var/log/splunk-bootstrap.log) 2>&1
echo "=== Splunk Search Head bootstrap started at $(date) ==="

dnf install -y awscli jq

SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --region "$AWS_REGION" --query SecretString --output text)
ADMIN_PASSWORD=$(echo "$SECRET_JSON" | jq -r .admin_password)

TARBALL_PATH="/tmp/splunk.tgz"
aws s3 cp "$TARBALL_URI" "$TARBALL_PATH" --region "$AWS_REGION"

tar -xzf "$TARBALL_PATH" -C /opt/
useradd -r -m -d /opt/splunk splunk || true
chown -R splunk:splunk /opt/splunk

/opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt --seed-passwd "$ADMIN_PASSWORD"
/opt/splunk/bin/splunk enable boot-start -user splunk --accept-license --answer-yes

if [ -n "$LICENSE_URI" ]; then
  aws s3 cp "$LICENSE_URI" /tmp/splunk.lic --region "$AWS_REGION"
  /opt/splunk/bin/splunk add licenser /tmp/splunk.lic -auth admin:"$ADMIN_PASSWORD"
fi

# Configure distributed search - connect to indexer cluster
IFS=',' read -ra IDX_ARRAY <<< "$INDEXER_IPS"
for ip in "$${IDX_ARRAY[@]}"; do
  /opt/splunk/bin/splunk add search-server "https://$ip:8089" -remoteUsername admin -remotePassword "$ADMIN_PASSWORD" -auth admin:"$ADMIN_PASSWORD" || true
done

# Register with deployment server for app deployment (ES app)
/opt/splunk/bin/splunk set deploy-poll "$CLUSTER_MANAGER_IP:8089" -auth admin:"$ADMIN_PASSWORD"

# Enable SSL for Web UI
/opt/splunk/bin/splunk enable ssl webserver -auth admin:"$ADMIN_PASSWORD"

# Create placeholder for ES app deployment
mkdir -p /opt/splunk/etc/apps/SplunkEnterpriseSecuritySuite/local
cat > /opt/splunk/etc/apps/SplunkEnterpriseSecuritySuite/local/app.conf << 'EOF'
[install]
state = disabled
EOF

chown -R splunk:splunk /opt/splunk/etc/apps

/opt/splunk/bin/splunk restart

echo "=== Search Head bootstrap complete at $(date) ==="
echo "Next: Install Splunk ES app via Deployment Server or manual upload"
