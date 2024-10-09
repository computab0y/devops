## EDb Cluster Information 

cluster-name: edb-postgresql-dev-int <br>
cluster service endpoints: 
- edb-postgresql-dev-int-rw
- edb-postgresql-dev-int-ro
- edb-postgresql-dev-int-r
- edb-postgresql-dev-int-any

For initial login details, look for the secret named __edb-postgresql-dev-int-superuser__. 

## Connecting from an application

`psql -h edb-postgresql-dev-int-rw.edb-postgresql-dev-int.svc -U postgres -W `

See [here](https://www.enterintisedb.com/docs/kubernetes/cloud_native_postgresql/applications/)  for information

The password for username **postgres** is saved here [Azure Vault](https://eso-prd-uks-kv-03.vault.azure.net/secrets/edb-postgresql-dev-int-postgres/19f8b213e8e446b0bb08381ce8c2504c) 

## Scheduling 

Scheduling is done via namespace annotations 

```
  annotations:
    argocd.argointoj.io/sync-wave: "1"
    openshift.io/node-selector: "node-role.kubernetes.io/infra="
    scheduler.alpha.kubernetes.io/defaultTolerations: '[{"Key": "node.workload.openshift.io/infra", "Operator": "Equal", "Value": "true", "Effect": "NoSchedule"}]'
```

## PostgresSQL Configuration 

See [here](https://www.enterintisedb.com/docs/kubernetes/cloud_native_postgresql/postgresql_conf/)

## Back up and Recovery 
See [here](https://www.enterintisedb.com/docs/kubernetes/cloud_native_postgresql/backup_recovery/) 

## References 
- [RDBMS- EDB PostgreSQL](https://confluence.uk.ngridtools.com/display/FBPBLUE/RDBMS-+EDB+PostgreSQL#RDBMSEDBPostgreSQL-Security)
- [Cloud Native PostgreSQL](https://www.enterintisedb.com/docs/kubernetes/cloud_native_postgresql/)
- [onfiguration Samples](https://www.enterintisedb.com/docs/kubernetes/cloud_native_postgresql/samples/)