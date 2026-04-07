terraform {
  required_version = ">= 1.0"
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

variable "pull_secret_path" {
  type        = string
  description = "Path to the OpenShift pull secret file"
  default     = "~/Downloads/pull-secret.txt"
}

variable "github_token" {
  type        = string
  description = "GitHub Personal Access Token for Argo CD repository access"
  sensitive   = true
}

resource "null_resource" "crc_cluster" {
  # This resource handles the lifecycle of the CRC VM
  provisioner "local-exec" {
    command = <<EOT
      crc config set memory 16384
      crc config set cpus 4
      crc start --pull-secret-file ${var.pull_secret_path}
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "crc stop || true && crc delete -f"
  }
}

resource "null_resource" "gitops_bootstrap" {
  depends_on = [null_resource.crc_cluster]

  triggers = {
    github_token = var.github_token
  }

  provisioner "local-exec" {
    command = <<EOT
      #!/bin/bash
      set -e
      eval $(crc oc-env)
      
      echo "Waiting for CRC API to stabilize..."
      sleep 30
      
      # Extract kubeadmin password from crc console output
      KUBEADMIN_PASS=$(crc console --credentials | grep "kubeadmin" | grep -o ' -p [^ ]*' | cut -d' ' -f3)
      
      # Login
      oc login -u kubeadmin -p $KUBEADMIN_PASS https://api.crc.testing:6443 --insecure-skip-tls-verify
      
      # Install OpenShift GitOps Operator
      oc create namespace openshift-gitops-operator --dry-run=client -o yaml | oc apply -f -
      
      cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-gitops-operator
  namespace: openshift-gitops-operator
spec:
  upgradeStrategy: Default
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-gitops-operator
spec:
  channel: latest
  installPlanApproval: Automatic
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

      echo "Waiting for OpenShift GitOps operator to finish installing..."
      for i in {1..60}; do
        if oc get csv -n openshift-gitops-operator 2>/dev/null | grep -q "Succeeded"; then
          echo "GitOps Operator installed."
          break
        fi
        sleep 10
      done

      # Wait for Argo CD server to be ready
      sleep 30

      # Create Argo CD Repository Secret
      cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: repo-github-computab0y-devops
  namespace: openshift-gitops
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: https://github.com/computab0y/devops.git
  password: ${var.github_token}
  username: computab0y
EOF

      # Grant cluster-admin to Argo CD controller so it can manage cluster-wide resources
      oc adm policy add-cluster-role-to-user cluster-admin -z openshift-gitops-argocd-application-controller -n openshift-gitops
      oc patch argocd openshift-gitops -n openshift-gitops --type='merge' -p '{"spec":{"resourceTrackingMethod":"annotation"}}' || true

      # Apply all Applications
      for APP in tekton sso grafana vault external-secrets; do
        DEST_NS=\$APP
        if [ "\$APP" = "tekton" ]; then DEST_NS="openshift-pipelines-operator"; fi
        if [ "\$APP" = "sso" ]; then DEST_NS="keycloak"; fi
        if [ "\$APP" = "grafana" ]; then DEST_NS="grafana-operator"; fi
        if [ "\$APP" = "external-secrets" ]; then DEST_NS="openshift-external-secrets-operator"; fi

        cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: devops-\$APP
  namespace: openshift-gitops
  labels:
    app.kubernetes.io/instance: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/computab0y/devops.git
    targetRevision: HEAD
    path: operators/subscription/\$APP/base
  destination:
    server: https://kubernetes.default.svc
    namespace: \$DEST_NS
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
      done
      
      echo "All initial GitOps applications configured."
    EOT
  }
}
