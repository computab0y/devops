# Scheduling backups

We are following the guideline stated [here](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.6/html-single/backup_and_restore/index#oadp-scheduling-backups_backing-up-applications). 

#  Scheduling backups

We are following the guideline stated [here](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.6/html-single/backup_and_restore/index#oadp-scheduling-backups_backing-up-applications). 

## Prerequisites

You must install the OpenShift API for Data Protection (OADP) Operator.
The DataProtectionApplication CR must be in a Ready state.


## Procedure 

- Retrieve the backupStorageLocations CRs

```
$ oc get backupStorageLocations -n openshift-adp NAME            PHASE       LAST VALIDATED   AGE     DEFAULT
example-dpa-1   Available   6s               5d22h   true
```

- Created a Schedule CR

```
$ oc get schedule schedule-backup -n openshift-adp 
NAME              STATUS    SCHEDULE     LASTBACKUP   AGE
schedule-backup   Enabled   55 9 * * *                4m56s
```

- Verify that the status of the Schedule CR is Completed after the scheduled backup runs:

```
$ oc get schedule -n openshift-adp schedule-backup -o jsonpath='{.status.phase}'
Enabled
```

note: we are supposed to see the status changed to _Completed_ once the backup is complted. The above commenad output didn't return as Completed, however we have seen that a resouce named _schedule-backup-20220922095545_ with status status as _Completed_ been created. 
