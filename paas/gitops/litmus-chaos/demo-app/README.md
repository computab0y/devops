# Introduction
This project and app:demo-app used for LitmusChaos experiment demo.

## Prerequisite

To run experiment is mandatory to have up and running Litmus Chaos Center

## Installation guide

1. Apply kustomization from demo dir: `oc apply -k .`
2. Update cluster_id value for `pod-delete-namespace-demo.yaml`
   Value is same as Chaos Delegate in Chaos center.
   Go to: ChaosCenter -> Chaos Delegates -> Press three dots next to your agent -> Copy Chaos Delegate ID
3. Push LitmusChaos scenario `pod-delete-namespace-demo.yaml` to [litmus-chaos--scenario](https://bitbucket.uk.ngridtools.com/projects/EFE/repos/litmus-chaos--scenario/browse?at=refs%2Fheads%2Ffeature%2FPRGBATR-12855-chaos-engineering-poc-on-devops-cluster)/litmus/{project id}/
4. Project ID available at Litmus Chaos Center url, after login looks like http://litmusportal-frontend-service-litmus.apps.devops.balancing.nationalgrideso.com/home?projectID=e8cbd145-1185-42c6-bb8d-8ef947df60f7&projectRole=Owner
5. After push first run initiates after Chaos Scenario sync, next run should be triggered via Chaos Center.
6. When you are done, clean up.