## EDb Cluster Information 

cluster-name: edb-postgresql-dev-pr <br>
cluster service endpoints: 
- edb-postgresql-dev-pr-rw
- edb-postgresql-dev-pr-ro
- edb-postgresql-dev-pr-r
- edb-postgresql-dev-pr-any

For initial login details, look for the secret named __edb-postgresql-dev-pr-superuser__. 

## Connecting from an application

`psql -h edb-postgresql-dev-pr-rw.edb-postgresql-dev-pr.svc -U postgres -W `

See [here](https://www.enterprisedb.com/docs/kubernetes/cloud_native_postgresql/applications/)  for information

The password for username **postgres** is saved in [Azure Vault](https://eso-prd-uks-kv-03.vault.azure.net/secrets/edb-postgresql-dev-pr-postgres/1712de0a63224625b095768f912ce6f5)


## Scheduling 

Scheduling is done via namespace annotations 

```
  annotations:
    argocd.argoproj.io/sync-wave: "1"
    openshift.io/node-selector: "node-role.kubernetes.io/infra="
    scheduler.alpha.kubernetes.io/defaultTolerations: '[{"Key": "node.workload.openshift.io/infra", "Operator": "Equal", "Value": "true", "Effect": "NoSchedule"}]'
```

## PostgresSQL Configuration 

See [here](https://www.enterprisedb.com/docs/kubernetes/cloud_native_postgresql/postgresql_conf/)

## Back up and Recovery 
See [here](https://www.enterprisedb.com/docs/kubernetes/cloud_native_postgresql/backup_recovery/) 

## References 
- [RDBMS- EDB PostgreSQL](https://confluence.uk.ngridtools.com/display/FBPBLUE/RDBMS-+EDB+PostgreSQL#RDBMSEDBPostgreSQL-Security)
- [Cloud Native PostgreSQL](https://www.enterprisedb.com/docs/kubernetes/cloud_native_postgresql/)
- [onfiguration Samples](https://www.enterprisedb.com/docs/kubernetes/cloud_native_postgresql/samples/)