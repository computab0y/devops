# Cucumber 

Cucumber is a testing tool that supports Behavior Driven Development (BDD). It allows for executable tests to be written as easily understood specifications. 

In BDD, users (BAs, POs) first write scenarios or acceptance tests that describe the behavior of the system, which is then signed off before any actual tests / code can be created.

## Usage in Openshift 

The example in this repository and in [Book Info](https://github.com/AccenturePreda/dso-pipeline-integration/tree/main/book-info-cicd/tests) rely on cucumberJS, a node based distribution of Cucumber.

### simple maths example 

This example runs a simple cucumber test from [this feature](https://github.com/timretout/docker-cucumber-js/blob/main/examples/simple_math.feature) that adds some numbers.
The files are referenced in this folder.

In any namespace run the following commands: 

    oc apply -f cucumberTask.yaml
    Creates a task run that run the cucumberJS test via NodeJS 

    oc apply -f TaskRun.yaml
    Triggers a run of the prior created Task
    
## BookInfo Tests 

As a part of the BookInfo application we have made a (NodeJS) CucumberJS & Selenium based set of tests. See the tests (here)[https://github.com/AccenturePreda/dso-pipeline-integration/tree/main/book-info-cicd/tests/features] 

It is run via a post deployment pipeline which is triggred by ArgoCD as a BatchJob.


### Why is selenium being used? 

We need a mechanism run a headless instance of the bookinfo web application. Cucumber on its own only provides a mechism to execute tests in the .feature format. Selenium provides us with the additional functionalites to query elements on a webpage and test the page.

     
