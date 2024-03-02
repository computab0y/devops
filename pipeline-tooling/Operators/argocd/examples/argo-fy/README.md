## Argo Fu<k Yourself!!


> Knock, knock, Who's there? Argo. Argo who? Argo fu<k yourself.

Series of Kustomize manifests to deploy and configure a namespaced instance of ArgoCD to OpenShift, using the OpenShift GitOps operator.


### GitOps Operator

OpenShift ships with the GitOps Operator which enables the use of ArgoCD as a key enabling tool to adopt GitOps processes within OpenShift.

The GitOps Operator deploys an opinionated version of ArgoCD using a Custom Resource Definition, which enables developers to deploy and manage their own ArgoCD instances.

To deploy and use ArgoCD, developers simply define and submit Custom Resources (CRs) using the Kubernetes API, which the Operator then creates and manages the entire lifecycle of the instance.


### Default Operation

By default the Operator assumes that the developer is deploying to the same single namespace that the ArgoCD is created within. For larger projects that is sometimes not suitable.


### Multi-Project Operation

When deploying to multiple OpenShift projects/namespaces, ArgoCD needs a appropriate ClusterRole and RoleBinding to be created and configured so that ArgoCD can create resources in the target namespaces.

In this example, Kustomize manaifests are provided to create the core ArgoCD resources, including the needed ServiceAccount and ClusterRole. 


### Kustomize Manifests

The following manifests are included, and are used to setup an ArgoCD instance and deploy the application using ArgoCD. 
To deploy simply use...

`$ oc apply -k argo-fy/base`
to deploy the ArgoCD instance, and

`$ oc apply -k petclinic-ns-setup`
to setup and configure the petclinic namespace. 

ArgoCD will then automagically deploy the petclinic application.

```
.
├── README.md
├── argo-fy
│   └── base
│       ├── argo-fy-argocr.yaml
│       ├── argo-fy-doer-clusterrole.yaml
│       ├── argo-fy-doer-sa.yaml
│       ├── argo-fy-namespace.yaml
│       └── kustomization.yaml
├── petclinic-ns-setup
|   ├── argo-fy-doer-petclinic-rb.yaml
|   ├── argo-fy-petclinic-appcr.yaml
|   ├── argo-fy-petclinic-ns.yaml
|   └── kustomization.yaml
└── petclinic
    └── base
        ├── kustomization.yaml
        ├── petclinic-deployment.yaml
        ├── petclinic-route.yaml
        └── petclinic-service.yaml
```

#### `argo-fy`

`argo-fy` sets up and configures the initial namespaced ArgoCD instance. This includes...
* Create `argo-fy` namespace
* Create `argo-fy-doer` ServiceAccount
* Create `argo-fy-doer` ClusterRole
* Create `argo-fy` ArgoCD Custom Resource

#### `petclinic-ns-setup`

`petclinic-ns-setup` sets up and configures an OpenShift project that will host the sample Petclinic application. This includes...
* Create `petclinic` namespace
* Create `argo-fy-doer` RoleBinding, binding the argo-fy ArgoCD instance, ServiceAccount, ClusterRole and namespaces together
* Create the `petclinic` ArgoCD Application CR

#### `petclinic`

`petclinic` deploys the sample petclinic app. The application is deployed through the use of the ArgoCD Application CR, and includes...
* Create Deployment
* Create Service 
* Create Route

