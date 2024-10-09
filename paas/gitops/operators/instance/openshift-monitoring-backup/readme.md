# Introduction
This readme is a guide on how to backup all components related to openshift monitoring
we are backing up the following components:
- openshift-monitoring
- openshift-user-workload-monitoring
- openshift-workspaces-monitoring

we are backing up all pods,yaml etc.. including the pvcs of the above components, in azure blob storage. For backup restic integrated velero tool is used by oadp operator.
# Pre-requisites
- Azure blob container should be created to store backup files
Azure blob container details are updated in the page https://confluence.uk.ngridtools.com/display/FBPBLUE/Backup+Scratch+Pad

- [DataProtectionApplication](../dpa/) is already created under the oadp operator  

# Steps

- create a Backup Storage Location in openshift-adp namespace for each componenet in the openshift monitoring with azure blob container configurations. In Backup storage location we need to specify the blob container name and the credentials to store the backup.
~~~
apiVersion: velero.io/v1
kind: BackupStorageLocation
metadata:
  name: openshift-monitoring
  namespace: openshift-adp
spec:
  config:                                    # Azure Storage account configuration
    resourceGroup: eso-dev-uks-edbbackup-rg
    storageAccount: esodevuksedbbackup
    storageAccountKeyEnvVar: AZURE_STORAGE_ACCOUNT_ACCESS_KEY
    subscriptionId: 7b4738c8-68b5-4c75-ac10-9682cbc4b398
  credential:                                    # Azure Storage account credential
    key: cloud
    name: cloud-credentials-azure
  objectStorage:
    bucket: openshift-monitoring # Azure blob container name
    prefix: openshift-monitoring       # repository to store the backup in the container
  provider: azure
~~~

- Add  schedule for the backup storage location in openshift-adp namespace for each namespace.
~~~
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: openshift-monitoring
  namespace: openshift-adp
spec:
  schedule: 30 02 * * * # backup schedule currently setup daily at 02:30 hrs
  template:
    defaultVolumesToRestic: true
    includedNamespaces:
      - openshift-monitoring
    ttl: 168h0m0s  # retention period for the backup is 7 days
~~~

# Reference
* [IG03-04 - Backup and Restore](https://confluence.uk.ngridtools.com/display/FBPBLUE/IG03-04+-+Backup+and+Restore)
* [Design Document](https://confluence.uk.ngridtools.com/pages/viewpage.action?pageId=129208302#id-5B&R:Backup&RestoreDesign-Prometheus)