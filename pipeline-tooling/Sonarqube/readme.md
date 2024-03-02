# SonarQube

SonarQube (formerly Sonar) is an open-source platform developed by SonarSource for continuous inspection of code quality to perform automatic reviews with static analysis of code to detect bugs, code smells, and security vulnerabilities on 20+ programming languages. SonarQube offers reports on duplicated code, coding standards, unit tests, code coverage, code complexity, comments, bugs, and security vulnerabilities.

[[SonarQube](https://www.sonarqube.org/)]


## sonarqube - postgress Installation 
====================================

Postgres
--------
0.0 Create the Secret using oc apply:

    oc apply -f postgres-secrets.yaml
    Eg: secret needs updated and converted as base64.
     echo "sonardb" | base64
     
1.0 Create PVC ( update storage type eg: ocs-storagecluster-ceph-rbd):

    oc apply -f postgres-storage.yaml

2.0 Deploying Postgres:

    oc apply -f postgres-deployment.yaml

3.0 Creating Postgres service
    oc apply -f postgres-service.yaml

To connect postgres DB 13.5
--------------------------
connect running by using following example command:

kubectl exec --stdin --tty postgres-85dfcf77ff-67vtx -- /bin/sh
Eg:
login DB
psql -U postgresadmin -w 'admin123'  -d postgres
 
create DB and credentials
    CREATE USER sonardb WITH PASSWORD 'sonardb';
    CREATE DATABASE sonardb WITH OWNER=sonardb ENCODING='UTF8';
    GRANT ALL PRIVILEGES ON DATABASE sonardb TO sonardb;


Sonarqube: lts-enterprise
-------------------------
0.0 Create PVC (storage type eg:ocs-storagecluster-ceph-rbd):

    oc apply -f sonar-pvc-data.yaml

1.0 Create configmaps for URL:

    oc apply -f sonar-configmap.yaml

2.0 Deploy Sonarqube(lts-enterprise):

    oc apply -f sonar-deployment.yaml

3.0 Creating SonarQube service

    oc apply -f sonar-service.yaml


Check secrets:
-------------
    oc get secrets
    oc get configmaps
    oc get pvc
    oc get deploy
    oc get pods
    oc get svc
    
Now Goto Loadbalancer and check whether service comes In service or not, If it comes Inservice copy DNS Name of Loadbalancer and check in web UI

Default Credentials for Sonarqube:
-------
    UserName: admin
    PassWord: admin
    

	

