# Operator Instance creation

### 0.0 Create namespace

	eg: dev-registry-edaapp

### 1.0 Red Hat Integration - AMQ Streams (1.8.2) - if not exist
   => select all namespaces

### 1.1 Create a Kafka Cluster (Via AMQ Streams) under dev-registry-edaapp namespace

	oc apply -f Operator/edaapp-cluster.yaml

### 1.2 Create a Kafka Topic 

	oc apply -f Operator/events.yaml

### 2.0 Red Hat Integration - Service Registry Operator (2.3)  - if not exist
    => select all namespaces

### 2.1 Create an instance of Apicurio Registry  

	oc apply -f Operator/dev-registry-edaapp.yaml 

### 3.0 Upload avro schema to apicurio registry
=> Access the route for Apicurio registry and upload the avro schema with the following information: 

	1. Group ID: io.apicurio.example.schema.avro
	2. Artifact ID - Event
        3. attach event.avsc file ( ./Operator/event.avsc )

# Vault Secret Configuration

[Refer here](https://github.com/AccenturePreda/dso-pipeline-tooling/blob/main/External-Secrets/README.md#vault-secret-configuration)

# Kafka deployment

### 0.0 Deploy secrets ( git & quey)

	oc apply -f pipeline/vault-basic-user-auth-git.yaml
	oc apply -f pipeline/vault-basic-user-auth-kafka.yaml

### 0.1 Deploy service accounts

	oc apply -f pipeline/build-bot-kafka.yaml

### 1.0 Create PVC's

	oc apply -f pipeline/maven-kafka-pvc.yaml
    oc apply -f pipeline/maven-settings.yaml

### 2.0  Create 'dso-kafka-build-image' Tekton Task 
	
	oc apply -f pipeline/dso-kafka-build-image.yaml
        
### 2.1  Create 'dso-kafka-push-binary' Tekton Task
    
	oc apply -f pipeline/dso-kafka-push-binary.yaml

### 3.0 create Tekton Pipeline

	oc apply -f pipeline/dso-kafka-pipeline.yaml

### 4.0 Create pipeline run

    oc create -f pipeline/dso-kafka-pipelinerun.yaml


### 5.0 Setup CD & Deploy application

	oc create -f pipeline/applications.yaml

# CI Trigger via GitHub

### 0.0 create trigger binding 

	oc create -f 01_binding.yaml

### 0.1 create trigger template

	oc create -f 02_template.yaml
### 0.2 create trigger

	oc create -f 03_trigger.yaml
### 0.3 create event listner 

	oc create -f 04_event_listener.yaml
### 0.4 expose event listener service 

	oc create -f 05_expose_service.yaml
### Configure webhook on Github

	- Access https://github.com/<organization>/<repository>/settings/hooks
	- Click 'Add webhook'
	- Populate with the host url inside of '05_expose_service.yaml'