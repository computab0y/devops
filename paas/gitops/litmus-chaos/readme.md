## Introduction 

[LitmusChaos](https://docs.litmuschaos.io/docs/introduction/what-is-litmus) is a Cloud-Native Chaos Engineering Framework with cross-cloud support. It is a CNCF Sandbox project with adoption across several organizations. Its mission is to help Kubernetes SREs and Developers to find weaknesses in both Non-Kubernetes as well as platforms and applications running on Kubernetes by providing a complete Chaos Engineering framework and associated Chaos Experiments.

Litmus can be used to run chaos experiments initially in the staging environment and eventually in production to find bugs and vulnerabilities, fixing which leads to an increased resilience of the system. Litmus adopts a Kubernetes-native approach to define chaos intent in a declarative manner via custom resources.

### LitmusChaos instalation

Deployment doesn't follow design pattern: [LitmusChaos#Deployment](https://confluence.uk.ngridtools.com/display/FBPBLUE/LitmusChaos#LitmusChaos-Deployment). LitmusChaos is deployed to single namespace.

1. LitmusChaos up to some point deployed using GitOps approach.
2. Login to litmus and change default password
   ```
   oc get route -n litmus
   ```
3. Add password to management keu vault, secret name: [litmus-chaoscenter-frontend-devops-admin](https://portal.azure.com/#@nationalgridplc.onmicrosoft.com/resource/subscriptions/f8dd3b2a-c78c-4c05-848c-72e03a7a9f57/resourceGroups/eso-prd-uks-osj-rg/providers/Microsoft.KeyVault/vaults/eso-prd-uks-kv-02/secrets)
4. Self agent created in 10minutes after first login. 
   ```
   $ oc get deployment
   NAME                       READY   UP-TO-DATE   AVAILABLE   AGE
   chaos-exporter             0/1     0            0           4m
   chaos-operator-ce          0/1     0            0           2m
   event-tracker              0/1     0            0           1m
   litmusportal-auth-server   1/1     1            1           10m
   litmusportal-frontend      1/1     1            1           10m
   litmusportal-server        1/1     1            1           10m
   subscriber                 0/1     0            0           3s
   workflow-controller        0/1     0            0           10s
   ```

5. Patch newly created deployments to run under restricted scc
   ```
   oc patch deployment chaos-exporter chaos-operator-ce event-tracker subscriber workflow-controller  --type json --patch '[{ "op": "remove", "path": "/spec/template/spec/containers/0/securityContext" }]'
   ```
6. Patch oauthclient dex
   ```
   dex_token=`oc sa get-token dex-oauth`; oc patch oauthclient dex --type='json' -p='[{"op": "replace", "path": "/secret", "value":"'"$dex_token"'"}]'
   ```
   This part can be automated by creating job or init container to run bash script required configuration
7. Setup GitOps
   - a. Go to: ChaosCenter → Settings → GitOps → Git Repository
   - b. Put Litmus generated SSH key to BitBucket repo [1], give read/write access.
   - c. Add Exemption to BitBucket repo [1] for Jira issues for `litmus` and `workflow` term

   1 - [BitBucket Repo](https://confluence.uk.ngridtools.com/pages/createpage.action?spaceKey=FBPBLUE&title=1&linkCreation=true&fromPageId=167641459)

8. Setup local ChaosHubs (Optional)
9. Setup custom image registry (Required only if default registry used in experiments)
   - a. Go to: ChaosCenter → Settings → Image Registry → Use custom values
   - b. Registry Server:  jfrog-dev.uk.ngridtools.com/docker-public-proxy
   - c. Registry: litmuschaos

## Login

Go to https://<route>/auth/dex/login, you should be prompted with OpenShift login.

## Important Links
- [IG03-06 - Litmus Chaos Engineering](https://confluence.uk.ngridtools.com/display/FBPBLUE/IG03-06+-+Litmus+Chaos+Engineering)
- [Runbook: Litmus Chaos Engineering](https://confluence.uk.ngridtools.com/display/FBPBLUE/Litmus+Chaos+Engineering)