#!/usr/bin/env bash
# Post-deployment: Install Splunk Enterprise Security app
set -euo pipefail

DEPLOY_SERVER="${1:?Usage: $0 <deployment-server-ip> <es-app-tarball-path>}"
ES_APP_TAR="${2:?Provide path to SplunkEnterpriseSecurity-*.spl archive}"

echo "Uploading Splunk ES app to Deployment Server at $DEPLOY_SERVER..."

scp "$ES_APP_TAR" "ec2-user@$DEPLOY_SERVER:/tmp/"

ssh "ec2-user@$DEPLOY_SERVER" << REMOTE
  sudo tar -xf /tmp/$(basename "$ES_APP_TAR") -C /opt/splunk/etc/deployment-apps/
  sudo chown -R splunk:splunk /opt/splunk/etc/deployment-apps/SplunkEnterpriseSecuritySuite
  sudo /opt/splunk/bin/splunk restart
REMOTE

echo "ES app deployed. Search Heads will receive the app on next poll cycle."
echo "Force immediate deployment: splunk apply shcluster-bundle (if using SH cluster)"
echo "Or on Search Head: /opt/splunk/bin/splunk reload deploy-server"
