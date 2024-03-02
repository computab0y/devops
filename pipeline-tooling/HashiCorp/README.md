# HashiCorp Vault

HashiCorp Vault is designed to help organizations manage access to secrets and transmit them safely within an organization. Secrets are defined as any form of sensitive credentials that need to be tightly controlled and monitored and can be used to unlock sensitive information. Secrets could be in the form of passwords, API keys, SSH keys, RSA tokens, or OTP.

HashiCorp Vault makes it very easy to control and manage access by providing you with a unilateral interface to manage every secret in your infrastructure. Not only that, you can also create detailed audit logs and keep track of who accessed what.

# Vault Installation to Red Hat OpenShift via Helm

This installation requires the  [OpenShift command-line interface (CLI)](https://docs.openshift.com/container-platform/4.2/cli_reference/openshift_cli/getting-started-cli.html)  and the  [Helm CLI](https://helm.sh/docs/helm/)  installed,  [OpenShift](https://minikube.sigs.k8s.io/)  and additional configuration to bring it all together.

This tutorial was last tested 9th December 2021 using this configuration.

CodeReady Containers version.

```
$ crc version
Code Ready Containers version: 1.12.0+6710aff
OpenShift version: 4.4.8 (embedded in binary)
```
Helm version.
```
$ helm version
version.BuildInfo{Version:"v3.7.2", GitCommit:"663a896f4a815053445eec4153677ddc24a0a361", GitTreeState:"clean", GoVersion:"go1.17.3"}
```
These are recommended software versions and the output displayed may vary depending on your environment and the software versions you use.

First, follow the directions to  [install CodeReady Containers](https://cloud.redhat.com/openshift/install/crc/installer-provisioned).

Next, install the  [helm CLI](https://github.com/helm/helm#install).

## Homebrew on OS X

Install `helm` with Homebrew.
```
$  brew install helm
```
Next, retrieve the web application and additional configuration by cloning the [hashicorp/vault-guides](https://github.com/hashicorp/vault-guides) repository from GitHub.
```
$  git clone https://github.com/hashicorp/vault-guides.git
```
This repository contains supporting content for all of the Vault learn guides. The content specific to this tutorial can be found within a sub-directory.

Go into the  `vault-guides/operations/provision-vault/kubernetes/openshift`  directory.

```shell-session
$ cd vault-guides/operations/provision-vault/kubernetes/openshift
```

**Working directory:**  This installation assumes that the remainder of commands are executed within this directory.
## Configure and start the OpenShift cluster

[CloudReady Containers (CRC)](https://learn.hashicorp.com/tutorials/vault/kubernetes-openshift?in=vault/kubernetes)  is a CLI tool that provisions and manages the lifecycle of OpenShift clusters running on your local system.

Configure CloudReady Containers.

```shell-session
$ crc setup
```

Start the OpenShift cluster,

```shell-session
$ crc start

## ...INFOINFO To access the cluster, first set up your environment by following 'crc oc-env' instructionsINFO Then you can access it by running 'oc login -u developer -p developer https://api.crc.testing:6443'INFO To login as an admin, run 'oc login -u kubeadmin -p fq66o-KsVBU-cnKBU-xLpqd https://api.crc.testing:6443'INFO## ...
```

**Image Pull Secret:**  This secret is generated and stored in your  [Red Hat account](https://cloud.redhat.com/openshift/install/crc/installer-provisioned).

The cluster starts and describes how to setup the environment and login as an administrator.

Apply the  `oc-env`  into the current shell session.

```shell-session
$ eval $(crc oc-env)
```

The OpenShift CLI is accessed using the command  `oc`. From here, you can administrate the entire OpenShift cluster and deploy new applications. The CLI exposes the underlying Kubernetes orchestration system with the enhancements made by OpenShift.

Login to the OpenShift cluster with as the user admin with the command provided by the  `crc start`  command.

**Example:**

```shell-session
$ oc login -u kubeadmin -p fq66o-KsVBU-cnKBU-xLpqd https://api.crc.testing:6443

##...Login successful.
You have access to 57 projects, the list has been suppressed. You can list all projects with 'oc projects'
Using project "default".
```

The output displays that you are logged in as an admin within the  `default`  project.
## Install the Vault Helm chart

The recommended way to run Vault on OpenShift is via the Helm chart. Helm is a package manager that installs and configures all the necessary components to run Vault in several different modes. To install Vault via the Helm chart in the next step requires that you are logged in as administrator within a project.

Add the Hashicorp Helm repository.

```shell-session
$ helm repo add hashicorp https://helm.releases.hashicorp.com
```

Update all the repositories to ensure  `helm`  is aware of the latest versions.

```shell-session
$ helm repo update

Hang tight while we grab the latest from your chart repositories......Successfully got an update from the "hashicorp" chart repositoryUpdate Complete. ⎈Happy Helming!⎈
```

Install the latest version of the Vault server running in development mode configured to work with OpenShift.

```shell-session
$ helm install vault hashicorp/vault --set "global.openshift=true" --set "server.dev.enabled=true"
```

The Vault pod and Vault Agent Injector pod are deployed in the default namespace.

Display all the pods within the default namespace.

```shell-session
$ oc get pods
NAME                                    READY   STATUS    RESTARTS   AGE
vault-0                                 1/1     Running   0          45s
vault-agent-injector-777b86fbbd-cxrgb   1/1     Running   0          45s
```

The  `vault-0`  pod runs a Vault server in development mode. The  `vault-agent-injector`  pod performs the injection based on the annotations present or patched on a deployment.

Wait until the  `vault-0`  pod and  `vault-agent-injector`  pod are running and ready (`1/1`).

## [»](https://learn.hashicorp.com/tutorials/vault/kubernetes-openshift?in=vault/kubernetes#configure-kubernetes-authentication)Configure Kubernetes authentication

Vault provides a Kubernetes authentication method that enables clients to authenticate with Vault within an OpenShift cluster. This authentication method configuration requires the location of the Kubernetes host, a JSON web token, and a certificate to prove authenticity. These values are available in an environment variable and files on the Vault pod.

Start an interactive shell session on the  `vault-0`  pod.

```shell-session
$ oc exec -it vault-0 -- /bin/sh/ 

#
```

Your system prompt is replaced with a new prompt  `/ #`. Commands issued at this prompt are executed on the  `vault-0`  container.

Enable the Kubernetes authentication method.

```shell-session
$ vault auth enable kubernetes

Success! Enabled kubernetes auth method at: kubernetes/
```

Configure the Kubernetes authentication method to use the service account token, the location of the Kubernetes host, and its certificate.

```shell-session
$ vault write auth/kubernetes/config token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"  kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

Success! Data written to: auth/kubernetes/config
```

The authentication method is now configured.

Exit the  `vault-0`  pod.

```shell-session
$ exit
```

## [»](https://learn.hashicorp.com/tutorials/vault/kubernetes-openshift?in=vault/kubernetes#deployment-request-secrets-directly-from-vault)Deployment: Request secrets directly from Vault

Applications on pods can directly communicate with Vault to authenticate and request secrets. An application needs:

-   a service accont
-   a Vault secret
-   a Vault policy to read the secret
-   a Kubernetes authentication role

### [»](https://learn.hashicorp.com/tutorials/vault/kubernetes-openshift?in=vault/kubernetes#create-the-service-account)Create the service account

Display the service account defined in  `service-account-webapp.yml`.

```shell-session
$ cat service-account-webapp.yml

apiVersion: v1
kind: ServiceAccountmetadata:
name: webapp
```

This definition of the service account creates the account with the name  `webapp`.

Apply the service account.

```shell-session
$ oc apply --filename service-account-webapp.yml

serviceaccount/webapp created
```

Get all the service accounts within the default namespace.

```shell-session
$ oc get serviceaccounts
NAME                   SECRETS   AGE
builder                2         24d
default                2         24d
deployer               2         24d
vault                  2         2m54s
vault-agent-injector   2         2m54s
webapp                 2         10s
```

The  `webapp`  service account is displayed.

### [»](https://learn.hashicorp.com/tutorials/vault/kubernetes-openshift?in=vault/kubernetes#create-the-secret)Create the secret

Start an interactive shell session on the  `vault-0`  pod.

```shell-session
$ oc exec -it vault-0 -- /bin/sh
```

Your system prompt is replaced with a new prompt  `/ #`. Commands issued at this prompt are executed on the  `vault-0`  container.

Create a secret at path  `secret/webapp/config`  with a  `username`  and  `password`.

```shell-session
$ vault kv put secret/webapp/config username="static-user" password="static-password"

Key              Value
---              -----
created_time     2020-07-14T20:20:04.315677226Z
deletion_time    n/a
destroyed        false
version          1
```

Get the secret at path  `secret/webapp/config`.

```shell-session
$ vault kv get secret/webapp/config

====== Metadata ======
Key              Value
---              -----
created_time     2020-07-14T20:20:04.315677226Z
deletion_time    n/a
destroyed        false
version          1

====== Data ======
Key         Value
---         -----
password    static-password
username    static-user
```

The secret with the username and password is displayed.

### [»](https://learn.hashicorp.com/tutorials/vault/kubernetes-openshift?in=vault/kubernetes#define-the-read-policy)Define the read policy

Write out the policy named  `webapp`  that enables the  `read`  capability for secrets at path  `secret/data/webapp/config`.

```shell-session
$ vault policy write webapp - <<EOF
path "secret/data/webapp/config" {  
  capabilities = ["read"]
}
EOF

Success! Uploaded policy: webapp
```

The policy  `webapp`  is used in the Kubernetes authentication role definition.

### [»](https://learn.hashicorp.com/tutorials/vault/kubernetes-openshift?in=vault/kubernetes#create-a-kubernetes-authentication-role)Create a Kubernetes authentication role

Create a Kubernetes authentication role, named  `webapp`, that connects the Kubernetes service account name and  `webapp`  policy.

```shell-session
$ vault write auth/kubernetes/role/webapp bound_service_account_names=webapp bound_service_account_namespaces=default policies=webapp ttl=24h

Success! Data written to: auth/kubernetes/role/webapp
```

The role connects the Kubernetes service account,  `webapp`, the namespace,  `default`, with the Vault policy,  `webapp`. The tokens returned are valid for 24 hours.

Exit the  `vault-0`  pod.

```shell-session
$ exit
```

### [»](https://learn.hashicorp.com/tutorials/vault/kubernetes-openshift?in=vault/kubernetes#deploy-the-application)Deploy the application

Display the webapp deployment defined in  `deployment-webapp.yml`.

```shell-session
$ cat deployment-webapp.yml
```

deployment-webapp.yml

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:  
  name: webapp  
  labels:    
    app: webapp
spec:  
  replicas: 1  
  selector:    
    matchLabels:      
      app: webapp  
  template:    
    metadata:      
      labels:        
        app: webapp    
    spec:      
      serviceAccountName: webapp
      containers:
        - name: app          
          image: burtlo/exampleapp-ruby:k8s
          imagePullPolicy: Always
          env:            
            - name: VAULT_ADDR
              value: 'http://vault:8200'
            - name: JWT_PATH
              value: '/var/run/secrets/kubernetes.io/serviceaccount/token'
            - name: SERVICE_PORT              
              value: '8080'
```

The deployment deploys a pod with a web application running under the  `webapp`  service account that talks directly to the Vault service created by the Vault Helm chart  `http://vault:8200`.

Apply the webapp deployment.

```shell-session
$ oc apply --filename deployment-webapp.yml

deployment.apps/webapp created
```

Display all the pods within the default namespace.

```shell-session
$ oc get pods

NAME                                    READY   STATUS    RESTARTS   AGE
vault-0                                 1/1     Running   0          7m16s
vault-agent-injector-777b86fbbd-cxrgb   1/1     Running   0          7m16s
webapp-7b5c8d8ddd-x6lwz                 1/1     Running   0          2m55s
```

Wait until the  `webapp`  pod is running and ready (`1/1`).

This web application runs an HTTP service that listens on port 8080.

Perform a  `curl`  request at  `http://localhost:8080`  on the  `webapp`  pod.

```shell-session
$ oc exec $(oc get pod --selector='app=webapp' --output='jsonpath={.items[0].metadata.name}') --container app -- curl -s http://localhost:8080 ; echo{"password"=>"static-password", "username"=>"static-user"}
```

The web application running on port 8080 in the  _webapp_  pod:

-   authenticates with the Kubernetes service account token
-   receives a Vault token with the read capability at the  `secret/data/webapp/config`  path
-   retrieves the secrets from  `secret/data/webapp/config`  path
-   displays the secrets as JSON

## [»](https://learn.hashicorp.com/tutorials/vault/kubernetes-openshift?in=vault/kubernetes#deployment-secrets-through-annotations)Deployment: Secrets through Annotations

Applications on pods can remain Vault unaware if they provide deployment annotations that the Vault Agent Injector detects. This injector service leverages the Kubernetes mutating admission webhook to intercept pods that define specific annotations and inject a Vault Agent container to manage these secrets. An application needs:

-   a service accont
-   a Vault secret
-   a Vault policy to read the secret
-   a Kubernetes authentication role
-   a deployment with Vault Agent Injector annotations

### [»](https://learn.hashicorp.com/tutorials/vault/kubernetes-openshift?in=vault/kubernetes#create-the-service-account-1)Create the service account

Display the service account defined in  `service-account-issues.yml`.

```shell-session
$ cat service-account-issues.yml

apiVersion: v1
kind: ServiceAccount
metadata:
  name: issues
```

This definition of the service account creates the account with the name  `issues`.

Apply the service account.

```shell-session
$ oc apply --filename service-account-issues.yml

serviceaccount/issues created
```

Get all the service accounts within the default namespace.

```shell-session
$ oc get serviceaccounts

NAME                   SECRETS   AGE
builder                2         24d
default                2         24d
deployer               2         24d
issues                 2         8s
vault                  2         7m56s
vault-agent-injector   2         7m56s
webapp                 2         5m12s
```

The  `issues`  service account is displayed.

### [»](https://learn.hashicorp.com/tutorials/vault/kubernetes-openshift?in=vault/kubernetes#create-the-secret-1)Create the secret

Start an interactive shell session on the  `vault-0`  pod.

```shell-session
$ oc exec -it vault-0 -- /bin/sh
```

Your system prompt is replaced with a new prompt  `/ #`. Commands issued at this prompt are executed on the  `vault-0`  container.

Create a secret at path  `secret/issues/config`  with a  `username`  and  `password`.

```shell-session
$ vault kv put secret/issues/config username="annotation-user" password="annotation-password"

Key              Value
---              -----
created_time     2020-07-14T20:25:24.043709599Z
deletion_time    n/a
destroyed        false
version          1
```

Copy

Get the secret at path  `secret/issues/config`.

```shell-session
$ vault kv get secret/issues/config

====== Metadata ======
Key              Value
---              -----
created_time     2020-07-14T20:25:24.043709599Z
deletion_time    n/a
destroyed        false
version          1

====== Data ======
Key         Value
---         -----
password    annotation-password
username    annotation-user
```

The secret with the username and password is displayed.

### [»](https://learn.hashicorp.com/tutorials/vault/kubernetes-openshift?in=vault/kubernetes#define-the-read-policy-1)Define the read policy

Write out the policy named  `issues`  that enables the  `read`  capability for secrets at path  `secret/data/issues/config`.

```shell-session
$ vault policy write issues - <<EOF
path "secret/data/issues/config" {  
  capabilities = ["read"]
} 
EOF

Success! Uploaded policy: issues
```

The policy  `issues`  is used in the Kubernetes authentication role definition.

### [»](https://learn.hashicorp.com/tutorials/vault/kubernetes-openshift?in=vault/kubernetes#create-a-kubernetes-authentication-role-1)Create a Kubernetes authentication role

Create a Kubernetes authentication role, named  `issues`, that connects the Kubernetes service account name and  `issues`  policy.

```shell-session
$ vault write auth/kubernetes/role/issues bound_service_account_names=issues bound_service_account_namespaces=default policies=issues ttl=24h

Success! Data written to: auth/kubernetes/role/issue
```

The role connects the Kubernetes service account,  `issues`, the namespace,  `default`, with the Vault policy,  `issues`. The tokens returned are valid for 24 hours.

Exit the  `vault-0`  pod.

```shell-session
$ exit
```

### [»](https://learn.hashicorp.com/tutorials/vault/kubernetes-openshift?in=vault/kubernetes#deploy-the-application-1)Deploy the application

Display the issues deployment defined in  `deployment-issues.yml`.

```shell-session
$ cat deployment-issues.yml
```

deployment-issues.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:  
  name: issues
  labels:    
    app: issues
spec:  
  selector:    
    matchLabels:
      app: issues  
    replicas: 1  
  template:    
    metadata:      
      annotations:        
        vault.hashicorp.com/agent-inject: 'true'
        vault.hashicorp.com/role: 'issues'
        vault.hashicorp.com/agent-inject-secret-issues-config.txt: 'secret/data/issues/config'
        vault.hashicorp.com/agent-inject-template-issues-config.txt: |          
          {{- with secret "secret/data/issues/config" -}}          
          postgresql://{{ .Data.data.username }}:{{ .Data.data.password }}@postgres:5432/wizard          
          {{- end -}}      
      labels:        
        app: issues
    spec:      
      serviceAccountName: issues
      containers:
        - name: issues
          image: jweissig/app:0.0.1
```

The Vault Agent Injector service reads the metadata annotations prefixed with  `vault.hashicorp.com`.

-   [`agent-inject`](https://learn.hashicorp.com/tutorials/vault/kubernetes-openshift?in=vault/kubernetes#agent-inject)  enables the Vault Agent injector service
-   [`role`](https://learn.hashicorp.com/tutorials/vault/kubernetes-openshift?in=vault/kubernetes#role)  is the Vault Kubernetes authentication role
-   [`agent-inject-secret-FILEPATH`](https://learn.hashicorp.com/tutorials/vault/kubernetes-openshift?in=vault/kubernetes#agent-inject-secret-filepath)  prefixes the path of the file,  `issues-config.txt`  written to the  `/vault/secrets`  directory. The value is the path to the Vault secret.
-   [`agent-inject-template-FILEPATH`](https://learn.hashicorp.com/tutorials/vault/kubernetes-openshift?in=vault/kubernetes#agent-inject-template-filepath)  formats the secret with a provided template.

Apply the issues deployment.

```shell-session
$ oc apply --filename deployment-issues.yml

deployment.apps/issues created
```

Display all the pods within the default namespace.

```shell-session
$ oc get pods

NAME                                    READY   STATUS    RESTARTS   AGE
issues-75d794c744-x9gnf                 2/2     Running   0          17s
vault-0                                 1/1     Running   0          9m53s
vault-agent-injector-777b86fbbd-cxrgb   1/1     Running   0          9m53s
webapp-7b5c8d8ddd-x6lwz                 1/1     Running   0          5m32s
```

Wait until the  `issues`  pod is running and ready (`2/2`).

This new pod now launches two containers. The application container, named  `issues`, and the Vault Agent container, named  `vault-agent`.

Display the logs of the  `vault-agent`  container in the  `issues`  pod.

```shell-session
$ oc logs $(oc get pod -l app=issues -o jsonpath="{.items[0].metadata.name}") --container vault-agent

==> Vault server started! Log data will stream in below:
==> Vault agent configuration:
Cgo: disabled
Log Level: info
Version: Vault v1.4.2
                     
[INFO]  sink.file: creating file sink
[INFO]  sink.file: file sink configured: path=/home/vault/.vault-token mode=-rw-r-----
[INFO]  auth.handler: starting auth handler[INFO]  auth.handler: authenticating
[INFO]  template.server: starting template server
[INFO] (runner) creating new runner (dry: false, once: false)
[INFO] (runner) creating watcher[INFO]  sink.server: starting sink server
[INFO]  auth.handler: authentication successful, sending token to sinks
[INFO]  auth.handler: starting renewal process
[INFO]  template.server: template server received new token
[INFO] (runner) stopping
[INFO] (runner) creating new runner (dry: false, once: false)
[INFO] (runner) creating watcher
[INFO] (runner) starting
[INFO]  sink.file: token written: path=/home/vault/.vault-token
[INFO]  auth.handler: renewed auth token
```

Display the secret written to the  `issues`  container.

```shell-session
$ oc exec $(oc get pod -l app=issues -o jsonpath="{.items[0].metadata.name}") --container issues -- cat /vault/secrets/issues-config.txt ; echopostgresql://annotation-user:annotation-password@postgres:5432/wizard
```

The secrets are rendered in a PostgreSQL connection string is present on the container.
