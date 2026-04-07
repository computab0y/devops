# CRC Cluster Terraform Setup

This Terraform module automates the process of creating and destroying an OpenShift CRC cluster on macOS, as well as bootstrapping it with the OpenShift GitOps Operator (Argo CD) and deploying all the applications (Pipelines, Keycloak SSO, Grafana, Vault, and External Secrets) directly from this repository.

## Requirements
* `terraform` installed
* `crc` installed and set up
* OpenShift pull secret downloaded (default: `~/Downloads/pull-secret.txt`)
* A GitHub Personal Access Token (PAT) with repository access.

## Usage

1. Initialize Terraform:
   ```bash
   terraform init
   ```

2. Apply the configuration (this will start the CRC VM and deploy the GitOps operator + applications):
   ```bash
   terraform apply -var="github_token=YOUR_GITHUB_PAT"
   ```

3. Destroy the cluster (this will run `crc delete` and wipe the VM):
   ```bash
   terraform destroy
   ```