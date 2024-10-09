

Disabling project self-provisioning 

By default, Openshift allows any authenticated user to create and delete new projects on the cluster. This feature is generally not advisable for a number of reasons

Cost implications - teams may exceed costs for projects they have created themselves
Resource / Quota allocation - If default the default template is deployed then additional resources/quotas would be assigned 
Administrative control - Administrators need to have control of project creation
Multitenancy issues - May be a need to control costs for different teams
 
The self provisioner cluster rolebinding is a rolebinding as a cluster wide (that apply to the entire cluster not only namespace wide) that will allow the cluster to self provisioning any new projects.


Disabling project self-provisioning 
Log in as a user with cluster-admin privileges. Review the subjects in the self-provisioners section. Remove the self-provisioner cluster role from the group system:authenticated:oauth . Edit the self-provisioners cluster role binding to prevent automatic updates to the role.




oc describe clusterrolebinding.rbac self-provisioners

Name:         self-provisioners
Labels:       <none>
Annotations:  rbac.authorization.kubernetes.io/autoupdate: true
Role:
  Kind:  ClusterRole
  Name:  self-provisioner
Subjects:
  Kind   Name                        Namespace
  ----   ----                        ---------
  Group  system:authenticated:oauth
  
 As we can see, the group that is allowed is the system:authenticated:oauth, that is every user that is authenticated in the cluster
 
 
Removing the self-provisioners cluster rolebinding will deny permissions for self-provisioning any new projects



To remove the self-provisioner cluster role from the group system:authenticated:oauth you need to remove that group from the role binding.

oc patch clusterrolebinding.rbac self-provisioners -p '{"subjects": null}'

Disable automatic updates
Automatic updates reset the cluster roles to a default state. In order to disable this, you need to set the annotation rbac.authorization.kubernetes.io/autoupdate to false by running:

oc patch clusterrolebinding.rbac self-provisioners -p '{ "metadata": { "annotations": { "rbac.authorization.kubernetes.io/autoupdate": "false" } } }'
Check that the clusterrolebinding have not the group system:authenticated:oauth among the allowed groups
# oc get clusterrolebinding.rbac self-provisioners -o yaml

apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "false"
  creationTimestamp: "2019-10-30T22:08:21Z"
  name: self-provisioners
  resourceVersion: "4408134"
  selfLink: /apis/rbac.authorization.k8s.io/v1/clusterrolebindings/self-provisioners
  uid: c9117fdf-fb61-11e9-96cb-00505693eda8
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: self-provisioner
  
  
Let’s check out the result of the operation. Login with a normal user and try to create a project:
  




