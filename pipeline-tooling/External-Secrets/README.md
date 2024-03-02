
# ExternalSecrets Installation to Red Hat OpenShift via Helm

This installation requires the  [OpenShift command-line interface (CLI)](https://docs.openshift.com/container-platform/4.2/cli_reference/openshift_cli/getting-started-cli.html)  and the  [Helm CLI](https://helm.sh/docs/helm/)  installed,  [OpenShift](https://minikube.sigs.k8s.io/)  and additional configuration to bring it all together. Ensure Hashicorp vault is already installed and setup. 

1. helm install external-secrets external-secrets/kubernetes-external-secrets -n default --set env.VAULT_ADDR=http://vault.default.svc.cluster.local:8200

2. RSH into the vault pod 
> oc rsh vault-0

3. Ensure Kubernetes Auth is enabled
> vault auth enable kubernetes

4. Configure Kubernetes Auth to use service account token mounted in pod and certificate of the kubernetes cluster
> vault write auth/kubernetes/config token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt issuer=https://kubernetes.default.svc

# Creating a secret and setting permissions 

1. Create a secure secret with the required information (replace the information with relevent information / paths)

> vault kv put secret/dso-github-user username="Some-Secret-Username" password="S0me-Secret-Password123"

2. Write an access policy for the above secreet

```
vault policy write dso-github-user - << EOF
path "secret/data/dso-github-user"
  { capabilities = ["read"]
}
EOF
```

3. Create roles to associate namespace with the required service account

```
vault write auth/kubernetes/role/dso-github-user bound_service_account_names=external-secrets-kubernetes-external-secrets bound_service_account_namespaces=default policies=dso-github-user ttl=60m
```

## Test connection 
```
# Use this to test connection and then delete this role.
vault write auth/kubernetes/role/dso-github-user-vault-test bound_service_account_names=vault bound_service_account_namespaces=default policies=dso-github-user ttl=60m

oc rsh vault-0
OCP_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
wget --no-check-certificate -q -O- --post-data '{"jwt": "'"$OCP_TOKEN"'", "role": "dso-github-user-vault-test"}' http://vault:8200/v1/auth/kubernetes/login

# Expected result is similar to below
> {"request_id":"53cbf879-d32f-a254-fd26-e11ddbb5d4ea","lease_id":"","renewable":false,"lease_duration":0,"data":null,"wrap_info":null,"warnings":null,"auth":{"client_token":"s.ge6vGPcXoU8ZpiL4jAFcS8Wq","accessor":"5pUv58zLVM0Kfat08qrmxbva","policies":["default","dso-github-user"],"token_policies":["default","dso-github-user"],"metadata":{"role":"dso-github-user-vault-test","service_account_name":"vault","service_account_namespace":"default","service_account_secret_name":"","service_account_uid":"34857370-35ff-438e-9f63-29b9084bd772"},"lease_duration":3600,"renewable":true,"entity_id":"ce4fd480-8967-08b2-f79f-6de9097c9f71","token_type":"service","orphan":true}}
```


# Create External Secret 

> oc apply -f ./ExternalSecret.yaml

Note: Update the yaml with the namespace / keys where your data should go. 
