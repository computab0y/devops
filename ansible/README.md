# CRC Cluster Ansible Automation

This Ansible playbook automates the lifecycle of your OpenShift CRC cluster and the bootstrapping of your GitOps ecosystem.

## Prerequisites
* `ansible` installed on your Mac.
* `crc` installed and set up.
* `oc` CLI installed.

## Usage

### 1. Provision Cluster and Applications
This will start the CRC VM, install the GitOps operator, and sync all applications from GitHub.
Pass your GitHub token as an environment variable or extra var:
```bash
export GITHUB_TOKEN=your_token_here
ansible-playbook playbook.yml --tags provision
# OR
ansible-playbook playbook.yml --tags provision -e "github_token=your_token_here"
```

### 2. Destroy Cluster
This will stop and completely delete the CRC instance from your Mac.
```bash
ansible-playbook playbook.yml --tags destroy
```

## Configuration
You can adjust memory, CPU, and other settings in the `vars.yml` file.
