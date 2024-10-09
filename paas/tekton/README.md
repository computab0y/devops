# Tekton Pipeline on openShift 4 Cluster
This repository provides a template and instructions to set up a Tekton pipeline on an OpenShift 4 cluster.

## Prerequisites
- OpenShift 4 cluster up and running
- Tekton installed on the OpenShift cluster

## Components
The following components needs to be in repository:

- `pipeline.yaml`: Define the structure and stages of the Tekton pipeline.
- `tasks/`: Contains individual tasks used in the pipeline
- `resources/`: Contains the input and output resources for the pipeline.
- `pipelines/`: Contains pre-defined pipelines.

## Explanation
1. Tekton Installation: Ensure that Tekton is properly installed on the Cluster.
   - Following things can be checked:
        ~~~
        $ oc project
        Using project "openshift-pipelines" on server "https://api.ort1.balancing.nationalgrideso.com:6443".
        
        $ oc get csv  | grep pipe
        openshift-pipelines-operator-rh.v1.7.3   Red Hat OpenShift Pipelines                      1.7.3      openshift-pipelines-operator-rh.v1.7.2   Succeeded
        
        $ oc project openshift-pipelines
        Already on project "openshift-pipelines" on server "https://api.ort1.balancing.nationalgrideso.com:6443".
        
        $ oc get pods
        NAME                                                 READY   STATUS      RESTARTS      AGE
        el-pipelines-as-code-interceptor-7758cbdb6c-dbjl6    1/1     Running     2 (49d ago)   51d
        pipelines-as-code-pr-cleanup-28069140-mwbvm          0/1     Completed   0             43m
        tekton-chains-controller-54694d8548-hzwzd            1/1     Running     0             3h13m
        tekton-operator-proxy-webhook-5849797cd8-w5b49       1/1     Running     1             51d
        tekton-pipelines-controller-54d745889b-jrkqt         1/1     Running     1             51d
        tekton-pipelines-webhook-6db69bff7f-556pm            1/1     Running     1             51d
        tekton-triggers-controller-c49d6bd84-9c85f           1/1     Running     1             51d
        tekton-triggers-core-interceptors-76c5676fbb-5mm4n   1/1     Running     1             51d
        tekton-triggers-webhook-679dd5664f-bfvp6             1/1     Running     1             51d
        tkn-cli-serve-58ddb68b74-www9g                       1/1     Running     1             51d
        
        $ oc get tektonconfig config
        NAME     VERSION   READY   REASON
        
        
        $ oc get tektonpipeline,tektontrigger,tektonaddon
        NAME                                          VERSION   READY   REASON
        tektonpipeline.operator.tekton.dev/pipeline   v0.33.2   True
        
        NAME                                        VERSION   READY   REASON
        tektontrigger.operator.tekton.dev/trigger   v0.19.0   True
        
        NAME                                    VERSION   READY   REASON
        tektonaddon.operator.tekton.dev/addon   1.7.3     True
        
        $ oc get tektonchains.operator.tekton.dev
        NAME    VERSION   READY   REASON
        chain   v0.8.0    True
        
        $  oc get cm chains-config
        NAME            DATA   AGE
        chains-config   3      3h16m
        ~~~
2. Access Permission: Make sure you have the necessary permission to create and manage resources in your OpenShift project/namespace where you plan to deploy the Tekton pipeline.
3. pipeline Configuration: Customize the `pipeline.yaml`file to define the structure and stages of your pipeline. Modify the tasks and resources as per the requirements. Also create seperate task and resource files and include them in pipeline if needed.
4. Task Definations: Create task defination YAML files in the `tasks/` directory. Each task respresents a specific unit of work in the pipeline, such as building, testing. or deploying an application. Configure the tasks to execute the necessary steps or commands.
5. Resource Definations: Define the input and output resources for the pipeline in the `resources/` directory. Resources can represent source code repositories, Dockerimages, or any other artifacts used in the pipeline. Update the resource YAML files with the appropriate details.
6. Pipeline Triggering: Determine how you want to trigger your pipeline. Onecan manually trigger it using the OpenShift CLI or web console, or set up an event-based trigger using webhooks or other mechanisms.
7. Pipeline Execution: Once the pipeline is triggered, it will execute the defined tasks and process the resources. Monitor the pipeline execution using the Tekton CLI(`tkn`) or OpenSHift web console. You can view logs, status and troubleshoot any issue that may arise during pipeline execution.
8. Intergration with OpenShift: Leverage OpenShift features like image stream, build configuration, and deployment configuration within the pipeline tasks for building and deploying applications.



## Setup Instructions
1. Clone the repository in local machine:
    ~~~~~
      $ git clone <repo-url>
      $ cd <repo-dir>
    ~~~~~~
2. Create the required resources:
    ~~~
    $ oc apply -f resources/
    ~~~
3. Create the tasks:
    ~~~
    $ oc apply -f tasks/
    ~~~
4. Create the pipeline:
    ~~~
    $ oc apply -f pipeline.yaml
    ~~~
5. Verify that the pipeline is created successfully:
    ~~~
    $ oc get pipelines
    ~~~
## Usage
To trigger the pipeline, make changes to the input resources and run the pipeline using the OpenShift CLI or go through the OpenShift web console.

For example, to manually trigger the pipeline using the openShift CLI:
6. Update the input resource YAML files with  the necessary changes.
7. Apply the changes:
    ~~~
    $ oc apply -f resources/
    ~~~
8. Start the pipeline:
    ~~~
    $ tkn pipeline start <pipeline_name>
    ~~~
## Customization
Feel free to customize the pipeline, tasks, and resources according to your project requirements. Refer to the Tekton Documentation or OpenShift documentation.

************************************************************************************

## Sample YAML
1. Create a new file called `pipeline.yaml` with the following content:
    ~~~
    apiVersion: tekton.dev/v1beta1
    kind: pipeline
    metadata:
      name: test-pipeline
    spec:
      tasks:
        - name: build-task
          taskRef:
            name: build-task
          resources:
            inputs:
              - name: source
                resourceRef:
                  name: git-source
            outputs:
              - name: built-image
                resourceRef:
                  name: docker-image
        - name: test-task
          taskRef:
            name: test-task
          resources:
            inputs:
              - name: app-image
                resourceRef:
                  name: docker-image
    ~~~
2. Create a new file called `build-task.yaml` withthe following content:
    ~~~
    apiVersdion: tekton.dev/v1beta1
    kind: Task
    metadata:
      name: build-task
    spec:
      steps:
        - name: build
          image: golang:1.17
          workingDir: /workspace/source
          command:
            - go
          args:
            - build
            - -o 
            - /workspace/built-app
            - .
          volumeMounts:
            - name: workspace
              mountPath: /workspace
        - name: copy-to-image
          image: alpine:latest
          command:
            - cp
          args:
            - /workspace/built-app
            - /workspace/app
          volumeMounts:
            - name: workspace
              mountPath: /workspace
        - name: create-dockerfile
          image: alpine:latest
          command:
            - sh
          args:
            - -c
            - echo 'FROM alpine:latest' > /workspace/Dockerfile && echo 'COPY /workspace/app /app' >> /workspace/Dockerfile
          volumeMounts:
            - name: workspace
              mountPath: /workspace
        - name: build-image
          image: docker:latest
          command:
            - docker
          args:
            - build
            - -t
            - my-image:latest
            - -f
            - /workspace/Dockerfile
            - /workspace
          volumeMounts:
            - name: workspace
              mountPath: /workspace
      volumes:
        - name: workspace
          emptyDir: {}
    ~~~
3. Create a new file called `test-task.yaml` with the following coontent:
    ~~~
    apiVersion: tekton.dev/v1beta1
    kind: Task
    metadata:
      name: test-task
    spec:
      steps:
        - name: test
          image: my-image:latest
          command:
            - go
          args:
            - test
          workingDir: /app
    ~~~

4. Apply the YAML files to create the resources:
    ~~~
    $ oc apply -f pipeline.yaml
    $ oc apply -f build-task.yaml
    $ oc apply -f test-task.yaml
    ~~~
5. Verify that the pipeline and stask are created successfully:
    ~~~
    $ oc get pipelines
    $ oc get tasks
    ~~~

With the above example. one can create a simple Tekton pipeline that consist of two tasks: `build-task` and `test-task`. The `build-task` compiles a Go application, creates a Docker image , and store it in a resource names `docker-image`. The `test-task` then test the built image.

#### Note: Make sure to replace the actaul values in YAML.


