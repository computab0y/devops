# Installation of Cloud Native PostgreSQL Operator


# License and License Key 

Following this [doc](https://www.enterprisedb.com/docs/kubernetes/cloud_native_postgresql/license_keys/) 

When instead OLM is used (i.e. on OpenShift or on Kubernetes from OperatorHub), you can choose to install the operator in a single namespace or to make it available in all namespaces.  The second option is the default one, and the operator will be installed in openshift-operators on OpenShift and operators on OperatorHub. We have followed the default option here. The license is stored within the secret __postgresql-operator-controller-manager-config__. 

```
oc create secret generic -n openshift-operators\
    postgresql-operator-controller-manager-config \
    --from-literal=EDB_LICENSE_KEY=[LICENSE_KEY_HERE]
```

**note:** The secret is not shared in this codebase. 

You'll need to delete the current operator pods. New pods will be automatically recreated and will use the secret:

```
oc delete pods -n openshift-operators \
  -l app.kubernetes.io/name=cloud-native-postgresql
```


# References 
- [Dev A Int - Application Dev Integrated - Database](https://confluence.uk.ngridtools.com/display/FBPBLUE/Dev+A+Int+-+Application+Dev+Integrated#DevAIntApplicationDevIntegrated-DatabaseDesign)
- [RDBMS- EDB PostgreSQL](https://confluence.uk.ngridtools.com/display/FBPBLUE/RDBMS-+EDB+PostgreSQL#RDBMSEDBPostgreSQL-Security)


