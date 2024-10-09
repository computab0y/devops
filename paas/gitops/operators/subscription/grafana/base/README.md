# Instruction

## Instalation
Grafana subscription configured via ArgoCD

- Enable grafana subscription control by ArgoCD at ../../../../argocd-appsets/operators/subscription/module-set.yaml
- Grafana operator configuration from master branch applied to cluster by ArgoCD
- Check install plan name
`oc get installplan -n grafana-operator`
- Patch install plans to approve
`oc patch installplan <installplan-name> -n grafana-operator --type merge --patch '{"spec":{"approved":true}}'`
- Patch grafana-operator csv to use proxy for image
`oc patch csv grafana-operator.v4.10.0 --type='json' -p='[{"op": "replace", "path": "/spec/install/spec/deployments/0/spec/template/spec/containers/0/image", "value":"jfrog.uk.ngridtools.com/public-proxy-gcr/kubebuilder/kube-rbac-proxy:v0.8.0"}]'`
- Wait 5 - 10 minutes until pod with new image will start

# DOCS
* [IG07 - 03 - Visualise tools & Dashboards](https://confluence.uk.ngridtools.com/pages/viewpage.action?pageId=184454010)
* [Runbook](https://confluence.uk.ngridtools.com/display/FBPBLUE/Custom+Grafana)
