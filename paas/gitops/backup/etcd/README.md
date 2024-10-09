# ETCD Backup CronJob with resources

This cronjob takes care of making ETCD backup and shipping it to Azure Blob Storage.

TODO: CNI version of this script

## Manual steps

*Notice:* most of this applies to Azure environments.

As image used in this CJ is on private JFrog registry, make sure `imagePullSecret` called `artifactory-image-pull` is present on the namespace and is same as working one on other namespaces.
It also uses secret called `azure-creds`, which needs value of `storage-acc-name` (Storage Account Name) and `storage-acc-key` (Storage Account Key) from Azure. Make sure it's valid and present before scheduled Job runs.

## Logic behind the script

First, master nodes are listed, backup is shortly taken by entering debug pod and launching etcd backup script as described in RedHat documentation. Then similar pod is being created via oc apply to be able to get the file to pod, which then is sent to azure blob store using azcli.