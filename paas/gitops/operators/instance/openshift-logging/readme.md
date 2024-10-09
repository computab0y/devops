## Additional setup

The operator is currently configured to create 3 PVCs of 500 GB . 

```
      storage:
        storageClassName: ocs-storagecluster-ceph-rbd 
        size: 500G
```

Due to limitations of ODF, the thin provisoned RBDs do to recover space after the file is deleted. To remedy this, a sheduled trim job should be configured for all 3 PVCs. This can be done by annoting the PVC with below annotation 

`reclaimspace.csiaddons.openshift.io/schedule: "@midnight"`

The value of the annotation follows standard cron format and should contain apropriate values. Case should be taken so that trim jobs for PVCs do not overlap.

Below are the annotions addedd for the 3 PVCs

PVC-1: `reclaimspace.csiaddons.openshift.io/schedule: 10 0 * * *`

PVC-2: `reclaimspace.csiaddons.openshift.io/schedule: 25 0 * * *`

PVC-3: `reclaimspace.csiaddons.openshift.io/schedule: 40 0 * * *`

## ClusterLogForwarder


Object: instance 


See [here](https://confluence.uk.ngridtools.com/display/FBPBLUE/ClusterLogForwarding+and+JSON+Parsing#ClusterLogForwardingandJSONParsing-AboutClusterLogForwarder) for further information. 



## JSON parsing 




**Creating Sample Index**

- index: app-quarkus-json-* <br>

Run the following query via the Devtools

`GET /_cat/indices?v&index=app-quarkus-json-*`

Additional considerations: 

- The Elasticsearch index for structured records is formed by prepending "app-" to the structured type and appending "-write".

**Viewing logging collector pods**

`$ oc get pods --selector component=collector -o wide -n openshift-logging`

## External References

- [Chapter 6. Forwarding logs to third party systems](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.6/html/logging/cluster-logging-external)
- [Enabling JSON logging](https://docs.openshift.com/container-platform/4.10/logging/cluster-logging-enabling-json-logging.html)
