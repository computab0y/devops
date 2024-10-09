# Introduction
This readme is a guide to how grafana is deployed and utilized in the devops cluster

# Pre-requisites

Grafana subscription installed via ArgoCD
- Grafana subscsription ../../subscription/grafana/

# Installation

Grafana instance installed via ArgoCD
- Set grafana application set to ../../../argocd-appsets/operators/instance/module-set.yaml
- Grafana instance, cluster prometheus configuration stored in this repo.
- Grafana configurations from master branch applied to cluster by ArgoCD
- Create secret as it is not managed by ArgoCD 'oc create -f secret.yaml'
- Set token to enable grafana authenticate to central prometheus. Used for datasource

```bash
oc set data secret/prometheus-creds PROMETHEUS_CENTRAL_TOKEN=`oc sa get-token grafana-serviceaccount -n grafana-operator` -n grafana-operator
```

### Why Grafana Requires a Database?
 Grafana requires a database to store and manage its data, including user information, dashboard configurations, and time series data. The database serves as a backend for Grafana to persist and retrieve this information, providing the following benefits:
 1. Data Persistence: By utilizing a database, Grafana ensures that data is persisted even if the application or server restarts, This allows for seamless access to dashboards and metrics without data loss.
 2. Scalability: A database provides a scalable solution for managing Grafana's data. It can handle large amounts of time series data and user information, allowing Grafana to efficiently handle increased user traffic and data volume.
 3. Dashboard Persistence: Dashboards and their configurations are stored in the database, allowing users to create, save, and access their custom dashboards, This ensures that dashboard layout, visualizations, and settings are maintained even after Grafana restarts.

By configuring the database in the Grafana CRD, one can provide the necessary information for Grafana to establish a connection with the database and leverage its capabilities for data storage and management.

### Database and Secrets Configuration
- Grafana requires a database for storing its data like dashboards, we are using PostgreSQL as the database backend.
- We are also passing database secret as an environment variable to the config
- To configure the Grafana database, make sure we have a PostgreSQL database instance available.
- Update the following parameters in the Grafana CRD(Custom Resource Definition) to match the PostgreSQL configuration:
    ~~~
    apiVersion: integreatly.org/v1alpha1
    kind: Grafana
    metadata:
      name: grafana
      namespace: grafana-operator
    spec:
      ...
      config:
          database:
              host: <postgresql-svc-url>:<port-no.5432>
              name: grafana_db 
              password: ${GF_DATABASE_PASSWORD} 
              type: postgres     
              user: grafana 
       deployment:
        env:
         - name: GF_DATABASE_PASSWORD
           valueFrom:
             secretKeyRef:
               key: password
               name: grafana-postgres-secret
      ...
    ~~~
     - `type`: Set the database type to `postgres`
     - `host`: Update the host to match the address and port of the PostgreSQL instance.
     - `name`: Set the name of the Grafana database as defined on Postgresql.
     - `user`: Set the username for accessing the database as defined on Postgresql.
     - `password`: grafana will retrieve the database password from the `GF_DATABASE_PASSWORD` environment variable.
#### Make sure the PostgreSQL database is set up and running before deploying Grafana.
 - In the deployment, we are setting up the environment variable which consists of the PostgreSQL password from secret `grafana-postgres-secret`.
 - The Grafana deployment will use the secret's value for the `GF_DATABASE_PASSWORD` environment variable, allowing Grafana to access the configured PostgreSQL database securely.

### Secret example that needs to be created:
- On the grafana-operator namespace:
    ~~~
    kind: Secret
    apiVersion: v1
    metadata:
      name: grafana-postgres-secret
      namespace: grafana-operator
    data:
      password: <base64-value>
    type: Opaque
    ~~~
- On the Postgresql namespace:
    ~~~
    kind: Secret
    apiVersion: v1
    metadata:
      name: edb-postgres-grafana
      namespace: edb-postgresql-qa-grafana
    data:
      password: <password-for-postgresql-db-base64-value>
      username: <grafana-user-name-base6-value>
    type: kubernetes.io/basic-auth
    ~~~
The Grafana.ini file(in the pod) for the database section will look like as below:
~~~
/usr/share/grafana $ cat /etc/grafana/grafana.ini 
[database]
host = edb-postgresql-grafana-rw.edb-postgresql-qa-grafana.svc.cluster.local:5432
name = grafana_db
password = ${GF_DATABASE_PASSWORD}
type = postgres
user = grafana
~~~

# Reference
* [IG07 - 03 - Visualise tools & Dashboards](https://confluence.uk.ngridtools.com/pages/viewpage.action?pageId=184454010)
* [Runbook](https://confluence.uk.ngridtools.com/display/FBPBLUE/Custom+Grafana)
