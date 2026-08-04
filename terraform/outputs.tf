output "vpc_id" {
  description = "Splunk VPC ID"
  value       = module.vpc.vpc_id
}

output "search_head_private_ip" {
  description = "Search Head private IP address"
  value       = module.splunk.search_head_private_ip
}

output "search_head_instance_id" {
  description = "Search Head EC2 instance ID"
  value       = module.splunk.search_head_instance_id
}

output "indexer_private_ips" {
  description = "Indexer private IP addresses"
  value       = module.splunk.indexer_private_ips
}

output "cluster_manager_private_ip" {
  description = "Cluster Manager / Deployment Server private IP"
  value       = module.splunk.cluster_manager_private_ip
}

output "bastion_public_ip" {
  description = "Bastion host public IP (if enabled)"
  value       = module.splunk.bastion_public_ip
}

output "splunk_web_url" {
  description = "Splunk Web UI URL"
  value       = var.enable_alb ? "https://${module.splunk.alb_dns_name}" : "https://${module.splunk.search_head_private_ip}:8000"
}

output "splunk_credentials_secret_arn" {
  description = "Secrets Manager ARN for Splunk credentials"
  value       = aws_secretsmanager_secret.splunk_credentials.arn
}

output "smartstore_bucket_name" {
  description = "S3 bucket for SmartStore"
  value       = module.s3.smartstore_bucket_name
}

output "artifacts_bucket_name" {
  description = "S3 bucket for Splunk artifacts (tarballs, licenses, apps)"
  value       = module.s3.artifacts_bucket_name
}

output "ssh_command" {
  description = "Example SSH command via bastion to Search Head"
  value       = var.enable_bastion ? "ssh -J ec2-user@${module.splunk.bastion_public_ip} ec2-user@${module.splunk.search_head_private_ip}" : "ssh ec2-user@${module.splunk.search_head_private_ip}"
}

output "post_deployment_steps" {
  description = "Manual steps required after Terraform apply"
  value       = <<-EOT
    1. Upload Splunk ES app to Deployment Server: /opt/splunk/etc/deployment-apps/
    2. Configure ES license on Search Head via Splunk Web or CLI
    3. Verify indexer cluster status: splunk show cluster-bundle-status
    4. Install and configure forwarders pointing to indexers (port 9997)
    5. Run ES setup wizard at ${var.enable_alb ? "https://${module.splunk.alb_dns_name}" : "https://<search-head-ip>:8000"}
  EOT
}
