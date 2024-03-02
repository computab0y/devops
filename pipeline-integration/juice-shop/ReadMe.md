# Juice-Shop Pipeline

In this repository is all of the code required to deploy juice-shop into Openshift.

The flow of this is as follows:

`Git-Clone Juice-Shop Repository -> Perform SAST testing using Sonarqube -> Build Juice-Shop from the Dockerfile and push to the Quay repo -> Deploy using ArgoCD -> Perform DAST scanning using Owasp-Zap`

There are some pre-requisites for this however:

+ You must have ArgoCD set up on Openshift with an exposed route
+ You must have a Quay Repository set up
+ You must create a robot account on Quay which has write access to the repository you want to push to - Replace the value in the Authentication/secrets.yaml file with this service account key
+ Similarly to the step above, you must also replace github token with a token that has access to the GitHub repo you will be cloning from. 
+ You must have a Manifests file (like in this repo) that ArgoCD is actively monitoring for any changes


After that, run a `kubectl apply -f <file>` with all of the tasks, secrets and pipeline files. It should then all be working.

Be sure to replace the values in the PipelineRun with the values you require.


Each file should be checked before deployment to ensure the relevant URLs and tokens are added. They will be marked with angle brackets where input is needed (<>)
