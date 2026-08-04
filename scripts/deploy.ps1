#Requires -Version 5.1
<#
.SYNOPSIS
    Splunk ES on AWS - Single Deployment Package (PowerShell)
.DESCRIPTION
    Deploys a small distributed Splunk ES cluster on AWS using Terraform.
.PARAMETER Action
    Terraform action: plan, apply, destroy, or output
.EXAMPLE
    .\scripts\deploy.ps1 -Action plan
    .\scripts\deploy.ps1 -Action apply
#>
param(
    [ValidateSet("plan", "apply", "destroy", "output")]
    [string]$Action = "plan"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$TerraformDir = Join-Path $ProjectRoot "terraform"

function Write-Info($msg)  { Write-Host "[INFO]  $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Check prerequisites
foreach ($cmd in @("terraform", "aws")) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Err "$cmd is not installed or not in PATH"
        exit 1
    }
}

$TfVars = Join-Path $TerraformDir "terraform.tfvars"
if (-not (Test-Path $TfVars)) {
    Write-Err "terraform.tfvars not found. Copy terraform.tfvars.example to terraform.tfvars and configure it."
    exit 1
}

Set-Location $TerraformDir

Write-Info "Initializing Terraform..."
terraform init -upgrade

switch ($Action) {
    "plan" {
        Write-Info "Running terraform plan..."
        terraform plan -out=tfplan
    }
    "apply" {
        Write-Info "Running terraform apply..."
        terraform apply -auto-approve
        Write-Info "Deployment complete!"
        terraform output post_deployment_steps
    }
    "destroy" {
        $confirm = Read-Host "Destroy all Splunk ES infrastructure? (yes/no)"
        if ($confirm -eq "yes") {
            terraform destroy -auto-approve
        }
    }
    "output" {
        terraform output
    }
}
