# JFrog Artifactory
JFrog Artifactory is a universal DevOps solution providing end-to-end automation and management of binaries and artifacts through the application delivery process that improves productivity across your development ecosystem. It enables freedom of choice supporting 25+ software build packages, all major CI/CD platforms, and DevOps tools you already use. Artifactory is Kubernetes ready supporting containers, Docker, Helm Charts, and is your Kubernetes and Docker registry and comes with full CLI and REST APIs customizable to your ecosystem.
[[JFrog Artifactory](https://www.jfrog.com/confluence/display/JFROG/JFrog+Artifactory)]

## postgres
========

0.1 Run the secrets file

	oc apply -f postgres-jfrog-secrets.yaml

0.2. create PVC ( Open the file and modify storageClassName if required)

	oc apply -f postgres-jfrog-pvc.yaml

1.0 Deploy postgres:10.3

	oc apply -f postgres-jfrog-deployment.yaml

2.0 Run the service

	oc apply -f postgres-jfrog-service.yaml


Additional tasks
Login to DB and Run the following commands for the permissions

	psql -U postgres

	CREATE USER artifactory WITH PASSWORD 'artifactory';
	CREATE DATABASE artifactory WITH OWNER=artifactory ENCODING='UTF8';
	GRANT ALL PRIVILEGES ON DATABASE artifactory TO artifactory;


	CREATE USER postgres WITH PASSWORD 'postgres';
	CREATE DATABASE postgres WITH OWNER=postgres ENCODING='UTF8';
	GRANT ALL PRIVILEGES ON DATABASE postgres TO postgres;

JFrog
=====

0.0  ssl -cert

oc apply -f ssl-cert.yaml


1.0 Create JFrog HA instance

      update in openshiftartifactoryha.yaml
      ---------------------------------------
line 13-14
----------
      joinKey: 636ae72bf2bc3ff57ca42c168cfd3a53b233cce332158923e38c4841977469cf
      masterKey: 3ff56aa840d96a9e4a1c5ef4cfe6044a855cf98af7648aa429cb1412001ff2f4

	Example on how to generate

	export MASTER_KEY=$(openssl rand -hex 32)
	echo ${MASTER_KEY}
	3ff56aa840d96a9e4a1c5ef4cfe6044a855cf98af7648aa429cb1412001ff2f4
	kubectl create secret generic my-masterkey-secret -n dso-tooling-jfrog --from-literal=master-key=${MASTER_KEY}
	secret/my-masterkey-secret created

	export JOIN_KEY=$(openssl rand -hex 32)
	echo ${JOIN_KEY}
	636ae72bf2bc3ff57ca42c168cfd3a53b233cce332158923e38c4841977469cf
	kubectl create secret generic my-joinkey-secret -n dso-tooling-jfrog --from-literal=join-key=${JOIN_KEY}
	secret/my-joinkey-secret created

line 21-26
----------
    database:
      driver: org.postgresql.Driver
      password: artifactory
      type: postgresql
      url: 'jdbc:postgresql://172.30.127.192:5432/artifactory'
      user: artifactory

line 44
----------
   tlsSecretName: app-certs-001


	oc apply -f openshiftartifactoryha.yaml

2.0 Validate if services are up and running

     oc get svc

3.0 Expose the service

    oc expose svc <service>
eg: oc expose svc openshiftartifactoryha-nginx

4.0 Validate WILDCARD

   oc get route 

Eg: openshiftartifactoryha-nginx-dso-tooling-jfrog.apps.ocp1.azure.dso.digital.mod.uk 

5.0 For JFrog UI

Open the browser and paste the url

  eg:  http://openshiftartifactoryha-nginx-dso-tooling-jfrog.apps.ocp1.azure.dso.digital.mod.uk/ui/packages