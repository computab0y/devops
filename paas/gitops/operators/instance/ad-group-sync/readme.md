### Azure Active Directory Group Sync Operator ###

Before the Group Sync instance can be deployed, a secret is needed which contains the credentials of the Azure AD

oc create secret generic azure-group-sync -n group-sync-operator --from-literal=AZURE_TENANT_ID=<AZURE_TENANT_ID> --from-literal=AZURE_CLIENT_ID=<AZURE_CLIENT_ID> --from-literal=AZURE_CLIENT_SECRET=<AZURE_CLIENT_SECRET>