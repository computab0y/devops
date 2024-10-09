# Intro


# Enabling monitoring for user-defined Projects

According to this (page)[https://docs.openshift.com/container-platform/4.10/monitoring/enabling-monitoring-for-user-defined-projects.html], 

```
In OpenShift Container Platform 4.10, you can enable monitoring for __user-defined projects__ in addition to the default platform monitoring. 
You can monitor your own projects in OpenShift Container Platform without the need for an additional monitoring solution. 
Using this feature centralizes monitoring for core platform components and user-defined projects.
```

**Prerequisites**

- You have access to the cluster as a user with the cluster-admin role.
- You have installed the OpenShift CLI (oc).
- You have created the __cluster-monitoring-config__ ConfigMap object.
- You have optionally created and configured the user-workload-monitoring-config ConfigMap object in the openshift-user-workload-monitoring project. You can add configuration options to this ConfigMap object for the components that monitor user-defined projects.


We are going to use GitOps application-set **operator-instance**. See the file __./gitops/argocd-appsets/operators/instance/module-set.yaml__ for details. 

Once the change is carried out via gitops, Check that the __prometheus-operator__, __prometheus-user-workload__ and __thanos-ruler-user-workload__ pods are running in the openshift-user-workload-monitoring project. It might take a short while for the pods to start:

```
$ oc get pods -n openshift-user-workload-monitoring
NAME                                  READY   STATUS    RESTARTS   AGE
prometheus-operator-c7bdc5c48-nc546   2/2     Running   0          27s
prometheus-user-workload-0            6/6     Running   0          20s
prometheus-user-workload-1            6/6     Running   0          20s
thanos-ruler-user-workload-0          3/3     Running   0          20s
thanos-ruler-user-workload-1          3/3     Running   0          20s
```
