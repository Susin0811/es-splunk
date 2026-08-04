#!/bin/bash
# Indexer node bootstrap
set -euo pipefail

SPLUNK_VERSION="${version}"
SPLUNK_BUILD="${build}"
TARBALL_URI="${tarball_uri}"
LICENSE_URI="${license_uri}"
SECRET_ARN="${secret_arn}"
AWS_REGION="${region}"
CLUSTER_MANAGER_IP="${cluster_manager_ip}"
INDEXER_ID="${indexer_id}"
ENABLE_SMARTSTORE="${enable_smartstore}"
SMARTSTORE_BUCKET="${smartstore_bucket}"

exec > >(tee /var/log/splunk-bootstrap.log) 2>&1
echo "=== Splunk Indexer ${indexer_id} bootstrap started at $(date) ==="

dnf install -y awscli jq xfsprogs

# Format and mount data volume
DATA_DEVICE="/dev/xvdf"
if [ -b "$DATA_DEVICE" ]; then
  if ! blkid "$DATA_DEVICE"; then
    mkfs.xfs "$DATA_DEVICE"
  fi
  mkdir -p /splunkdata
  mount "$DATA_DEVICE" /splunkdata
  echo "$DATA_DEVICE /splunkdata xfs defaults,nofail 0 2" >> /etc/fstab
fi

SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --region "$AWS_REGION" --query SecretString --output text)
ADMIN_PASSWORD=$(echo "$SECRET_JSON" | jq -r .admin_password)
SECRET_KEY=$(echo "$SECRET_JSON" | jq -r .secret_key)

TARBALL_PATH="/tmp/splunk.tgz"
aws s3 cp "$TARBALL_URI" "$TARBALL_PATH" --region "$AWS_REGION"

tar -xzf "$TARBALL_PATH" -C /opt/
useradd -r -m -d /opt/splunk splunk || true

# Move hot/warm buckets to data volume
if [ -d /splunkdata ]; then
  mkdir -p /splunkdata/splunk
  chown -R splunk:splunk /splunkdata
fi

chown -R splunk:splunk /opt/splunk
/opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt --seed-passwd "$ADMIN_PASSWORD"
/opt/splunk/bin/splunk enable boot-start -user splunk --accept-license --answer-yes

if [ -n "$LICENSE_URI" ]; then
  aws s3 cp "$LICENSE_URI" /tmp/splunk.lic --region "$AWS_REGION"
  /opt/splunk/bin/splunk add licenser /tmp/splunk.lic -auth admin:"$ADMIN_PASSWORD"
fi

# Configure indexer paths on data volume
if [ -d /splunkdata/splunk ]; then
  /opt/splunk/bin/splunk set index path -auth admin:"$ADMIN_PASSWORD" \
    --homePath '/splunkdata/splunk/\$SPLUNK_DB' \
    --coldPath '/splunkdata/splunk/\$SPLUNK_DB' \
    --thawedPath '/splunkdata/splunk/\$SPLUNK_DB'
fi

# Join indexer cluster as peer
/opt/splunk/bin/splunk edit indexer-cluster master-uri \
  -mode slave \
  -master_uri "https://$CLUSTER_MANAGER_IP:8089" \
  -secret "$SECRET_KEY" \
  -auth admin:"$ADMIN_PASSWORD"

# SmartStore configuration
if [ "$ENABLE_SMARTSTORE" = "true" ] && [ -n "$SMARTSTORE_BUCKET" ]; then
  cat >> /opt/splunk/etc/system/local/indexes.conf << EOF

[volume:s3_volume]
storageType = remote
path = s3://$SMARTSTORE_BUCKET/indexer-$INDEXER_ID
remote.s3.access_key = use_iam_role
remote.s3.secret_key = use_iam_role
remote.s3.endpoint = https://s3.$AWS_REGION.amazonaws.com

[default]
remotePath = volume:s3_volume/$_index_name
EOF
  chown splunk:splunk /opt/splunk/etc/system/local/indexes.conf
fi

# Wait for cluster manager to be ready, then apply bundle
sleep 120
/opt/splunk/bin/splunk apply cluster-bundle --skip-validation -auth admin:"$ADMIN_PASSWORD" || true

/opt/splunk/bin/splunk restart

echo "=== Indexer ${indexer_id} bootstrap complete at $(date) ==="
