#!/usr/bin/env bash
# Health check script - run from bastion or any node with SSH access
set -euo pipefail

SEARCH_HEAD_IP="${1:?Usage: $0 <search-head-ip> [admin-password]}"
ADMIN_PASS="${2:-}"

echo "=== Splunk ES Cluster Health Check ==="
echo ""

check_node() {
  local name="$1" ip="$2"
  echo -n "[$name] $ip - "
  if curl -sk --connect-timeout 5 "https://$ip:8089/services/server/info" -u "admin:$ADMIN_PASS" &>/dev/null; then
    echo "OK"
  else
    echo "UNREACHABLE"
  fi
}

if [ -z "$ADMIN_PASS" ]; then
  echo "Provide admin password as second argument for API checks"
  echo "Basic connectivity check only..."
fi

check_node "Search Head" "$SEARCH_HEAD_IP"

echo ""
echo "Run these on Search Head for detailed status:"
echo "  splunk show cluster-status -auth admin:<password>"
echo "  splunk list deploy-server-clients -auth admin:<password>"
echo "  splunk btool check -auth admin:<password>"
