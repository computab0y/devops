# Deployment

The instance is deployed via the application named _operator-instance-amq-streams-dev-a-int_. For details, see *ApplicationSet* configuration is file _~gitops/argocd-appsets/operators/instance/module-set.yaml_. 

# Components 

## Zookeeper Configuration

See [here](https://access.redhat.com/documentation/en-us/red_hat_amq/7.7/html/using_amq_streams_on_openshift/assembly-deployment-configuration-str#ref-zookeeper-node-configuration-deployment-configuration-kafka) for **ZooKeeper configuration**. 

```
zookeeper:
    livenessProbe:
      initialDelaySeconds: 30
      timeoutSeconds: 5
    readinessProbe:
      initialDelaySeconds: 60
      timeoutSeconds: 5
    replicas: 3  
    storage:
      type: persistent-claim
      size: 10Gi
      class: ocs-storagecluster-ceph-rbd
      deleteClaim: true
```

**Some useful information about the current configurations:** 

dataDir=/var/lib/zookeeper/data<br>
clientPort=12181<br>

ssl.clientAuth=need <br>
ssl.quorum.clientAuth=need<br>
secureClientPort=2181<br>
sslQuorum=true<br>


**Zookeeper nodes configuration**
- server.1=dev-a-pr-amq-streams-zookeeper-0.dev-a-pr-amq-streams-zookeeper-nodes.dev-a-pr-amq-streams.svc:2888:3888:participant;127.0.0.1:12181
- server.2=dev-a-pr-amq-streams-zookeeper-1.dev-a-pr-amq-streams-zookeeper-nodes.dev-a-pr-amq-streams.svc:2888:3888:participant;127.0.0.1:12181
- server.3=dev-a-pr-amq-streams-zookeeper-2.dev-a-pr-amq-streams-zookeeper-nodes.dev-a-pr-amq-streams.svc:2888:3888:participant;127.0.0.1:12181


## Kafka Brokers


See **Kafka Broker Configuration**  [here](https://access.redhat.com/documentation/en-us/red_hat_amq/7.7/html/using_amq_streams_on_openshift/assembly-deployment-configuration-str#assembly-kafka-broker-configuration-deployment-configuration-kafka). 


**KafkaConfig Values:**

```
advertised.listeners = CONTROLPLANE-9090://dev-a-pr-amq-streams-kafka-0.dev-a-pr-amq-streams-kafka-brokers.dev-a-pr-amq-streams.svc:9090,REPLICATION-9091://dev-a-pr-amq-streams-kafka-0.dev-a-pr-amq-streams-kafka-brokers.dev-a-pr-amq-streams.svc:9091,PLAIN-9092://dev-a-pr-amq-streams-kafka-0.dev-a-pr-amq-streams-kafka-brokers.dev-a-pr-amq-streams.svc:9092,TLS-9093://dev-a-pr-amq-streams-kafka-0.dev-a-pr-amq-streams-kafka-brokers.dev-a-pr-amq-streams.svc:9093
```

## kafka_exporter


See [here](https://access.redhat.com/documentation/en-us/red_hat_amq/7.7/html/using_amq_streams_on_openshift/assembly-deployment-configuration-str#proc-kafka-exporter-configuring-deployment-configuration-kafka) for **Kafka Exporter**. 

port: 9094

```
kafkaExporter:
    topicRegex: ".*"
    groupRegex: ".*"
    readinessProbe:
      initialDelaySeconds: 15
      timeoutSeconds: 5
    livenessProbe:
      initialDelaySeconds: 15
      timeoutSeconds: 5
```

## Entiry Operator

See [here](https://access.redhat.com/documentation/en-us/red_hat_amq/7.7/html/using_amq_streams_on_openshift/assembly-deployment-configuration-str#ref-kafka-entity-operator-deployment-configuration-kafka) for Entiry Operator relatd information. 


## Creation of a Sample Topic

Utilised manifest _kafka-topic.yaml_

```
$ oc get kafkatopic
NAME                                                                                               CLUSTER                   PARTITIONS   REPLICATION FACTOR   READY
consumer-offsets---84e7a678d08f4bd226872e5cdd4eb527fadc1c6a                                        dev-a-pr-amq-streams   50           3                    True
greetings                                                                                          dev-a-pr-amq-streams   3            2                    True
strimzi-store-topic---effb8e3e057afce1ecf67c3f5d8e4e3ff177fc55                                     dev-a-pr-amq-streams   1            3                    True
strimzi-topic-operator-kstreams-topic-store-changelog---b75e702040b99be8a9263134de3507fc0cc4017b   dev-a-pr-amq-streams   1            1                    True
```

# Kafka Connect 

See [here](https://access.redhat.com/documentation/en-us/red_hat_amq/7.7/html/using_amq_streams_on_openshift/assembly-deployment-configuration-str#proc-configuring-kafka-connect-bootstrap-servers-deployment-configuration-kafka-connect). 

## Bootstrap Servers 



## Healthchecks 

See section **Healthchecks** [here](https://access.redhat.com/documentation/en-us/red_hat_amq/7.7/html/using_amq_streams_on_openshift/assembly-deployment-configuration-str). 


# Monitoring

**note:** to be confirmed

## Prerequisites
- deployed the Prometheus metrics configuration using the example YAML files.
- Monitoring for user-defined projects is enabled.
- To monitor user-defined projects, you must have been assigned the monitoring-rules-edit or monitoring-edit role by a cluster administrator. 

## Deploying Prometheus Resources 

- Check that monitoring for user-defined projects is enabled:**


`oc get pods -n openshift-user-workload-monitoring`


- define _PodMonitor_ resources 


Please see the page [Logging and Monitoring](https://confluence.uk.ngridtools.com/display/FBPBLUE/Red+Hat+Integration+-+AMQ+Streams#RedHatIntegrationAMQStreams-LoggingandMonitoring).

# References 

* [AMQ streams deployment](https://jira.uk.ngridtools.com/browse/FBCPROG-587)
* [Red Hat Integration - AMQ Streams](https://confluence.uk.ngridtools.com/display/FBPBLUE/Red+Hat+Integration+-+AMQ+Streams#RedHatIntegrationAMQStreams-Introduction)
* [amq-streams-ocp-demo](https://github.com/johnkim76/amq-streams-ocp-demo)