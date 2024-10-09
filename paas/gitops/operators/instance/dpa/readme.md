# DataProtectionApplication

**DataProtectionApplication** is a Custom Resource (CR) to define the backup configuration for the OADP operator. Once defined it makes the Velero server running also syncs the applications to the backup storage as per schedule defined in the oadp operator 

_At least one DataProtectionApplication CR to be created in oadp namespace_ to get Velero server running and syncing backups from the defined backup location. We are using Azure blob containers to backup applications. Hence,we need to create azure blob containers for each applications that would be backed up and configure Azure credentials in oadp namespace.

## Credentials
Create credentials-velero file on local path:
```
AZURE_SUBSCRIPTION_ID=
AZURE_TENANT_ID=f98a6a53-25f3-4212-901c-c7787fcd3495
#AZURE_CLIENT_ID=
#AZURE_CLIENT_SECRET=
AZURE_RESOURCE_GROUP=
AZURE_STORAGE_ACCOUNT_ACCESS_KEY=
AZURE_CLOUD_NAME=AzurePublicCloud
```
(commented parameters refer to role credentials, since we're using Restic backups we don't need them, but leaving for reference in the future, tenant ID is same across whole NG)


# Reference
* [OADP](https://docs.openshift.com/container-platform/4.10/backup_and_restore/application_backup_and_restore/installing/installing-oadp-ocs.html#configuring-dpa-ocs)
* [Velero Document](https://velero.io/docs/v1.11/disaster-case/)
