# Instruction

Create secret data to enable grafana authenticate to istio prometheus. Used for datasource

```bash
oc set data secret/prometheus-creds PROMETHEUS_ISTIO_CTLPLANE_01_PWD=`oc get secret -n istio-ctlplane-01 htpasswd -o jsonpath='{.data.rawPassword}' | base64 -d` -n grafana-operator
```
# To Add PVC to Prometheus Deployment in servicemeshcontrolplane as per Redhat
 
 Redhat case : https://access.redhat.com/support/cases/#/case/03567655

  Only way to enable persistent storage with the ossm embedded Prometheus component is to tweak the deployment after its creation by the Service Mesh Control Plane instance. And then changing the volume type to use a persistent volume claim .also, these modifications won't be overwritten by the operator.

## Login to Openshift using the token gerenrated from the console
```bash
oc login --token=YOUR_TOKEN --server=OC_SERVER_URL
```

## Switch the project to control plane namespace
```bash
oc project <namespace>
```

## Add Volume and Volume Mounts using oc patch command
```bash
oc patch deployment/prometheus -n <namespace> --type='json' -p='[
                {
                  "op": "add",
                  "path": "/spec/template/spec/containers/1/volumeMounts/-",
                  "value": {
                      "mountPath": "/prometheus",
                      "name": "prometheus-db-volume"
                    }
                },
                {
                  "op": "add",
                  "path": "/spec/template/spec/volumes/-",
                  "value": {
                      "name": "prometheus-db-volume",
                      "emptyDir": {}
                    }
                }
               ]'
```

## Create and Update the PVC to deployment
```bash
oc set volume deployment/prometheus -n <namespace> --add --name=prometheus-db-volume --type=persistentVolumeClaim --claim-name=prometheus-db-volume --claim-size=50Gi --claim-class=ocs-storagecluster-cephfs --overwrite
```
Execute the above commands before changing the retention in the control plane YAML file
