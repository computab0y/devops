# Intro 

**OpenShift API for Data Protection (OADP)** enables backup, restore, and disaster recovery of applications on an OpenShift cluster. Data that can be protected with OADP include Kubernetes resource objects, persistent volumes, and internal images. The OpenShift API for Data Protection (OADP) is designed to protect Application Workloads on a single OpenShift cluster.

Red Hat OpenShift® Data Foundation is software-defined storage for containers. Engineered as the data and storage services platform for Red Hat OpenShift, Red Hat OpenShift Data Foundation helps teams develop and deploy applications quickly and efficiently across clouds.

The terms Project and namespace maybe used interchangeably in this guide.

See this guideline [How to Backup and Restore Stateful Applications on OpenShift using OADP and ODF](https://cloud.redhat.com/blog/how-to-backup-and-restore-stateful-applications-on-openshift-using-oadp-and-odf). 

# Pre-requisites

- Authenticate as Cluster Admin inside your environment of an OpenShift 4.9 Cluster.
- Your cluster meets the minimum requirement for OpenShift Data Foundation in Internal Mode deployment
    - 3 worker nodes, each with at least:
        - 8 logical CPU
        - 24 GiB memory
        - 1+ storage devices

## Installing OpenShift Data Foundation Operator 

note: already done 

## VERIFY OPENSHIFT DATA FOUNDATION OPERATOR INSTALLATION

You can validate the successful deployment of OpenShift Data Foundationn cluster following Verifying OpenShift Data Foundation deployment in the previous deployment documentation or with the following command:

`$ oc get storagecluster -n openshift-storage ocs-storagecluster -o jsonpath='{.status.phase}{"\n"}'
Ready`

And for the Multi-Cloud Gateway (MCG):

`$ oc get noobaa -n openshift-storage noobaa -o jsonpath='{.status.phase}{"\n"}'
Ready`

## Creating Object Bucket Claim

Object Bucket Claim creates a persistent storage bucket for Velero to store backed up kubernetes manifests.

- Navigate to _Storage > Object Bucket Claim_ and click _Create Object Bucket Claim_. Note the Project you are currently in. You can create a new Project or leave as default

- set the following values:

    - ObjectBucketClaim Name: _oadp-bucket_
    - StorageClass: _openshift-storage.noobaa.io_
    - BucketClass: _noobaa-default-bucket-class_

- Click _Create_. 

When the Status is Bound, the bucket is ready.

## GATHERING INFORMATION FROM OBJECT BUCKET

### Gathering Bucket Name and Host 

- Get bucket name

`$ oc get configmap oadp-bucket -n default -o jsonpath='{.data.BUCKET_NAME}{"\n"}'
oadp-bucket-e2898e60-106a-4929-832d-3b6bf698eeb6`

- Get bucket host

`$ oc get configmap oadp-bucket -n default -o jsonpath='{.data.BUCKET_HOST}{"\n"}'
s3.openshift-storage.svc`

- get the information on the Object Bucket _obc-default-oadp-bucket_ 


```
$ oc get ObjectBucket -n default -o yaml
apiVersion: v1
items:
- apiVersion: objectbucket.io/v1alpha1
  kind: ObjectBucket
  metadata:
    creationTimestamp: "2022-09-15T14:09:46Z"
    finalizers:
    - objectbucket.io/finalizer
    generation: 1
    labels:
      app: noobaa
      bucket-provisioner: openshift-storage.noobaa.io-obc
      noobaa-domain: openshift-storage.noobaa.io
    name: obc-default-oadp-bucket
    resourceVersion: "442485915"
    uid: d93a188e-82ca-4997-af8a-0db25d3a8777
  spec:
    additionalState:
      account: obc-account.oadp-bucket-e2898e60-106a-4929-832d-3b6bf698eeb6.6323322a@noobaa.io
      bucketclass: noobaa-default-bucket-class
      bucketclassgeneration: "1"
    claimRef: {}
    endpoint:
      additionalConfig:
        bucketclass: noobaa-default-bucket-class
      bucketHost: s3.openshift-storage.svc
      bucketName: oadp-bucket-e2898e60-106a-4929-832d-3b6bf698eeb6
      bucketPort: 443
      region: ""
      subRegion: ""
    reclaimPolicy: Delete
    storageClassName: openshift-storage.noobaa.io
  status:
    phase: Bound
kind: List
metadata:
  resourceVersion: ""
  selfLink: ""
```

We are after the following two information 

- bucketHost: s3.openshift-storage.svc
- bucketName: oadp-bucket-e2898e60-106a-4929-832d-3b6bf698eeb6

- Gather oadp-bucket secret

    - Get AWS_ACCESS_KEY

    `$ oc get secret oadp-bucket -n default -o jsonpath='{.data.AWS_ACCESS_KEY_ID}{"\n"}' | base64 -d`

    - Get AWS_SECRET_ACCESS_KEY

    `$ oc get secret oadp-bucket -n default -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}{"\n"}' | base64 -d`

    - check the _Object Bucket Claim_ named _oadp-bucket_ created. 

    ```
    $ oc get ObjectBucketClaim -n default 
    NAME          STORAGE-CLASS                 PHASE   AGE
    oadp-bucket   openshift-storage.noobaa.io   Bound   5d19h
    ```

- Now you should have the following information:

- bucket name
- bucket host
- AWS_ACCESS_KEY_ID
- AWS_SECRET_ACCESS_KEY

## Deploying a Sample Application



## Installing OpenShift API for Data Protection Operator

See [here](gitops/operators/subscription/oadp/)

## CREATE CREDENTIALS SECRET FOR OADP OPERATOR TO USE

We will now create secret _cloud-credentials_ using values obtained from Object Bucket Claim in Project _openshift-adp_.

```
$ oc get secret cloud-credentials -n openshift-adp 
NAME                TYPE     DATA   AGE
cloud-credentials   Opaque   1      5d17h
```

Create the secret with the following details: 

- Secret name: cloud-credentials
- Key: cloud
- Value:
    - Replace the values with your own values from earlier steps and enter it in the value field.
    ```
    [default]
    aws_access_key_id=<INSERT_VALUE>
    aws_secret_access_key=<INSERT_VALUE>
    ```


## CREATE THE DATAPROTECTIONAPPLICATION CUSTOM RESOURCE

Within the installed operator _openshift-adp_, created an instance of the __DataProtectionApplication (DPA)__, called _example-dpa_. 


```
$ oc get DataProtectionApplication -n openshift-adp -o yaml
apiVersion: v1
items:
- apiVersion: oadp.openshift.io/v1alpha1
  kind: DataProtectionApplication
  metadata:
    creationTimestamp: "2022-09-16T11:25:08Z"
    generation: 1
    name: example-dpa
    namespace: openshift-adp
    resourceVersion: "446388841"
    uid: 2eb8cf8a-03f0-4eb2-8721-81e5a6c02077
  spec:
    backupLocations:
    - velero:
        config:
          profile: default
          region: localstorage
          s3ForcePathStyle: "true"
          s3Url: http://s3.openshift-storage.svc/
        credential:
          key: cloud
          name: cloud-credentials
        default: true
        objectStorage:
          bucket: oadp-bucket-e2898e60-106a-4929-832d-3b6bf698eeb6
          prefix: velero
        provider: aws
    configuration:
      velero:
        defaultPlugins:
        - openshift
        - aws
        - csi
        featureFlags:
        - EnableCSI
```

The object storage we are using is an S3 compatible storage provided by OpenShift Data Foundation. We are using custom s3Url capability of the aws velero plugin to access OpenShift Data Foundation local endpoint in velero.

## VERIFY INSTALL

```
$ oc get all -n openshift-adp
NAME                                                    READY   STATUS    RESTARTS        AGE
pod/openshift-adp-controller-manager-6f4d87b9f9-wcnf6   1/1     Running   1 (3d11h ago)   6d1h
pod/velero-676948cbfb-xnzww                             1/1     Running   0               5d1h

NAME                                                       TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/openshift-adp-controller-manager-metrics-service   ClusterIP   172.30.26.182   <none>        8443/TCP   6d1h
service/openshift-adp-velero-metrics-svc                   ClusterIP   172.30.78.64    <none>        8085/TCP   5d1h

NAME                                               READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/openshift-adp-controller-manager   1/1     1            1           6d1h
deployment.apps/velero                             1/1     1            1           5d1h

NAME                                                          DESIRED   CURRENT   READY   AGE
replicaset.apps/openshift-adp-controller-manager-6f4d87b9f9   1         1         1       6d1h
replicaset.apps/velero-676948cbfb                             1         1         1       5d1h
```

## MODIFYING VOLUMESNAPSHOTCLASS

Setting a _DeletionPolicy_ of _Retain_ on the VolumeSnapshotClass will preserve the volume snapshot in the storage system for the lifetime of the Velero backup and will prevent the deletion of the volume snapshot, in the storage system, in the event of a disaster where the namespace with the _VolumeSnapshot_ object may be lost.

The Velero CSI plugin, to backup CSI backed PVCs, will choose the VolumeSnapshotClass in the cluster that has the same driver name and also has the _velero.io/csi-volumesnapshot-class: "true"_ label set on it.

```
oc patch volumesnapshotclass ocs-storagecluster-rbdplugin-snapclass --type=merge -p '{"deletionPolicy": "Retain"}'
oc label volumesnapshotclass ocs-storagecluster-rbdplugin-snapclass velero.io/csi-volumesnapshot-class="true"
```

```
$  oc get VolumeSnapshotClass  ocs-storagecluster-rbdplugin-snapclass -o yaml 
apiVersion: snapshot.storage.k8s.io/v1
deletionPolicy: Retain
driver: openshift-storage.rbd.csi.ceph.com
kind: VolumeSnapshotClass
metadata:
  creationTimestamp: "2022-04-14T15:38:53Z"
  generation: 2
  labels:
    velero.io/csi-volumesnapshot-class: "true"
  name: ocs-storagecluster-rbdplugin-snapclass
  resourceVersion: "442830790"
  uid: f56f7bac-77e9-415c-8d03-8db61070f89e
parameters:
  clusterID: openshift-storage
  csi.storage.k8s.io/snapshotter-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/snapshotter-secret-namespace: openshift-storage
```

here, 

- deletionPolicy: Retain
- labels:
    velero.io/csi-volumesnapshot-class: "true"

## Backup An application

You back up Kubernetes images, internal images, and persistent volumes (PVs) by creating a _Backup_ custom resource (CR).

A sample backup CR is shown on backup.yaml 

See [here](backup-restore/application-backup-restore-oadp/examples/scheduled-backup/) for information on scheduled-backup. 

# Restoring an application

You restore a Backup custom resource (CR) by creating a Restore CR.
An example of that is shown on _restore.yaml_ file. 
