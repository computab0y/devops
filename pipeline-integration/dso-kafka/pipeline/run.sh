#!/bin/bash
oc apply -f dso-kafka-pipeline.yaml
oc create -f dso-kafka-pipelinerun.yaml
echo " Pipeline is created!"
