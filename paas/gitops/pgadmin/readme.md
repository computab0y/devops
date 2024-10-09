## Introduction 

pgAdmin is an open-source project management tool for the PostgreSQL (http://www.postgresql.org) database. We want do a PoC deployment of PGadmin on to the DevOps cluster, and test connectivity to an EDB database running on the same cluster.  This can be later deployed to other clusters and can be used by application teams to add their database and manage it thru pgAdmin

## Installation

pgAdmin4 does not have a openshift installation documentation reference . Kubernetes refrences link given in the referecne section is modified to Deploy the pgAdmin4. PgAdmin4 is deployed in a single namespace

## Pre-req:

Do application registration by raising a snow request get the client id and client secret


## Deployment:

Pgadmin deployment is done as a standalone deployment, no servers are added now
Users can  register the server. once they register it, it will be availble in our persistent storage
Azure AD is added to pgadmin, Users own azure AD groups will be used for login

to configure OIDC authentication with Azure AD below file is referred
https://www.pgadmin.org/docs/pgadmin4/latest/oauth2.html
https://www.pgadmin.org/docs/pgadmin4/development/config_py.html


Following configurations were added in the Deployment file to enable to Oauth

            - name: PGADMIN_CONFIG_AUTHENTICATION_SOURCES
              value: "['oauth2','internal']"
            - name: PGADMIN_CONFIG_OAUTH2_AUTO_CREATE_USER
              value: "True"
            - name: PGADMIN_CONFIG_OAUTH2_CONFIG
              value: |
                [ 
                  {
                    'OAUTH2_NAME': 'azure',
                    'OAUTH2_DISPLAY_NAME': 'Azure Active Directory',
                    'OAUTH2_CLIENT_ID': '$(CLIENT_ID)',
                    'OAUTH2_CLIENT_SECRET': '$(CLIENT_SECRET)',
                    'OAUTH2_TOKEN_URL': 'https://login.microsoftonline.com/$(TENANT_ID)/oauth2/v2.0/token',
                    'OAUTH2_AUTHORIZATION_URL': 'https://login.microsoftonline.com/$(TENANT_ID)/oauth2/v2.0/authorize',
                    'OAUTH2_API_BASE_URL': 'https://graph.microsoft.com/v1.0',
                    'OAUTH2_USERINFO_ENDPOINT': 'https://graph.microsoft.com/oidc/userinfo',
                    'OAUTH2_SCOPE': 'User.Read email openid profile',
                    'OAUTH2_SERVER_METADATA_URL': 'https://login.microsoftonline.com/$(TENANT_ID)/v2.0/.well-known/openid-configuration'
                  }
                ]  

Mater password is set to false since we are using oauth authentication

   - name: PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED
      value: "False"

pgAdmin4 thru configmap file is created for reference,
This can be modified later to add more servers

Secrets will be moved to Azure vault in gitops deployment later

## References:
https://www.enterprisedb.com/blog/how-deploy-pgadmin-kubernetes
https://www.enterprisedb.com/blog/how-configure-oauth-20-pgadmin-4