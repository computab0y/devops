### Setting up API Manager for 3Scale ###

Create empty project for 3scale

Subscribe to operator

Deploy operator (rbd for all PVCs except system-storage which needs fs)
....keep managed-premium as default SC

oc get route -n three-scale | grep system-provider

oc get secret system-seed -n three-scale -o json | jq -r .data.ADMIN_USER | base64 -d

oc get secret system-seed -n three-scale -o json | jq -r .data.ADMIN_PASSWORD | base64 -d

