
# Splunk operator setup

This configuration is to create a splunk operator. THis is not controlled by gitops as this is just a POC. Both operator and instance is setup in asingle namespaces.

run `oc apply -f splunk-operator-namespace.yaml` to install the ooperator

- Namespace: splunk-operator
- operator version: 2.0.0 
- Splunk application version: 9.0.0 [line 14560]


# Splunk instance setup 
Instance should be setup in the same namespace as the operator

- Instance name: s1
- web console: https://splunk-s1.apps.devops.balancing.nationalgrideso.com
- hec endpoint: https://splunk-s1-hec-splunk-operator.apps.devops.balancing.nationalgrideso.com
- Admin password: `oc get secret splunk-s1-standalone-secret-v1 -n splunk-operator -o jsonpath="{.data.password}" | base64 -d`

## Reference
Install Docs: https://splunk.github.io/splunk-operator

