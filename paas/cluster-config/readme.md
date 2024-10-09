**TO CREATE MANAGED CLUSTER WITH ACM**

In Mgmt Cluster, create a namespace to run managed cluster creation from:
`oc new-project ${namespace for cluster creation}`

Enter that newly created namespace:
`oc project ${namespace for cluster creation}`

Configure deploy-config.yaml to use the namespace created above

Create secret for the Azure Service Principal (loaded onto Bastion):
`oc create secret generic azure-service-principal --from-file=osServicePrincipal.json=./osServicePrincipal.json`

Create a secret for the Cluster Install Config (loaded onto Bastion):
`oc create secret generic devops-install-config --from-file=install-config.yaml=./install-config.yaml`

Create a secret for the Pull Secret (loaded onto Bastion):
`oc create secret generic pull-secret --from-file=.dockerconfigjson=pull-secret --type=kubernetes.io/dockerconfigjson`

Set the OpenShift cluster image (loaded onto Bastion):
`oc apply -f cluster-image-set.yaml`

Execute the Deploy Config Manifest:
`oc create -f deploy-config.yaml`

Wait as the cluster is now building within a container...

Login to ACM on Mgmt Cluster > Infrastructure > Clusters

Select the recently built cluster > Import the cluster via button

**TO OBTAIN SECRETS FOR MANAGED CLUSTER**

In the Mgmt Cluster, list secrets and identify the kubeconfig and admin-password secrets for below commands:
`oc get secret -n ${namespace for cluster creation}`

Retrieve kubeconfig:
`oc get secret ${MANAGED_CLUSTER_NAME}-admin-kubeconfig -n ${namespace for cluster creation} -ojsonpath='{.data.kubeconfig}' | base64 -d > kubeconfig`

Retrieve kubeadmin password:
`oc get secret ${MANAGED_CLUSTER_NAME}-admin-password -n ${namespace for cluster creation} -ojsonpath='{.data.password}' | base64 -d > kubeadmin_password`

Lists pods and identify the cluster creation pod:
`oc get pods`

Retrieve the console URL:
`oc logs {pod name} hive`

**IMPORT MANAGED CLUSTER INTO MGMT CLUSTER....WHERE THE MANAGED CLUSTER WAS BUILT OUTSIDE ACM**

In the Mgmt Cluster, create a namespace for the cluster import:
`oc new-project ${MANAGED_CLUSTER_NAME}`

Label the namespace:
`oc label namespace ${MANAGED_CLUSTER_NAME} cluster.open-cluster-management.io/managedCluster=${MANAGED_CLUSTER_NAME}`

Define the managed cluster resource:
`oc apply -f managed-cluster.yaml`

Apply the klusterlet addon file:
`oc apply -f klusterlet-addon-config.yaml`

Retrieve the kluster-crd secret and insert into a YAML:
`oc get secret ${MANAGED_CLUSTER_NAME}-import -n ${MANAGED_CLUSTER_NAME} -o jsonpath={.data.crds\.yaml} | base64 --decode > klusterlet-crd.yaml`

Retrieve the import secret and insert into a YAML:
`oc get secret ${MANAGED_CLUSTER_NAME}-import -n ${MANAGED_CLUSTER_NAME} -o jsonpath={.data.import\.yaml} | base64 --decode > import.yaml`

In the Managed Cluster, apply the klusterlet manifest:
`oc apply -f klusterlet-crd.yaml`

Apply the import manifest:
`oc apply -f import.yaml`

Validate the pod status:
`oc get pod -n open-cluster-management-agent`

Validate the status of the imported cluster:
`oc get managedcluster -n ${CLUSTER_NAME}`

Observe the ACM UI in the Mgmt Cluster, the new managed cluster should be visible

**Reference Docs**

NG Confluence Doc: https://confluence.uk.ngridtools.com/pages/viewpage.action?pageId=85263086

RH Doc: https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.0/html/manage_cluster/importing-a-target-managed-cluster-to-the-hub-cluster#importing-a-managed-cluster-with-the-cli