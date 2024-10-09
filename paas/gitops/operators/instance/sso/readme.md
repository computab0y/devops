# Intro 

Accessing sso-obp

- url: https://keycloak-sso.apps.devops.balancing.nationalgrideso.com

Create your own username and password in the master realm in order to administer keycloak. We can then disable the generic admin user.
- login id: username-admin
- password: your password

# Components 

## Keycloak instance

name: sso-obp

# KeycloakRealm

name: OBPSSOPoc

## KeycloakClient: 

name: sso-obp

The standardFlowEnabled: true so that service accounts can authentication to our service (keycloak!) with a service token. 

The authorizationServicesEnabled so that we can add advanced role based access control to our resources in application! 

# TODOs:

- Keys: we can create Keys that apps can use to integrate with keycloak. But we need to find a use-case or a sample app. 



# References 

- [https://www.redhat.com/en/blog/openshift-single-sign-sso](OpenShift Single Sign On SSO)
- [https://access.redhat.com/documentation/en-us/red_hat_single_sign-on/7.4/html/server_installation_and_configuration_guide/operator#install_by_olm](Installing using the Operator Lifecycle Manager)
