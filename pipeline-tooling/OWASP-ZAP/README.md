# OWASP ZAP

OWASP ZAP (short for Zed Attack Proxy) is an open-source web application security scanner. It is intended to be used by both those new to application security as well as professional penetration testers.

# OWASP ZAP on OpenShift

This README details specifically how to add Owasp Zap's active scan to your pipeline. 

## The Task
The below code details how to add a Task to OpenShift that runs Owasp-Zap. 

```
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: owasp-zap
  namespace: dso-juice-shop
spec:
  params:
    - name: APP_URL
      type: string
      default: ''
      description: "The Applications URL to scan"
    - name: minutes
      type: string
      default: '0'
      description: "The number of minutes to spider for"
  steps:
    - command:
        - zap-full-scan.py
        - '-t'
        - "$(params.APP_URL)"
        - '-m'
        - "$(params.minutes)"
        - '-j'
      image: owasp/zap2docker-stable:2.11.0
      name: 'run-scan'
```

In the above code, two parameters are passed in - "APP_URL" & "minutes". The APP_URL is the URL to the web application that you are looking to scan, and the minutes is the amount of time you want Zap to spider the application for. The default is 0, meaning that Zap will continue spidering until it can no longer find any more URLs.

Once it has created its list of URLs, Zap will then conduct an active scan, actively interacting with the website trying to find vulnerabilities. It should be noted here that this can be a very intrusive process and may have unintended consequences. 

**You should only scan applications that you have permission to scan.**

The -t option specifies the target
The -m option specifies the minutes to scan for
The -j option specifies to use the ajax spider in addition to the traditional one. 

There are several other parameters that can be added, depending on what you are trying to achieve. Below is a list of all the parameters currently available for the zap-full-scan.py command:

```
Usage: zap-full-scan.py -t <target> [options]
    -t target         target URL including the protocol, eg https://www.example.com
Options:
    -h                print this help message
    -c config_file    config file to use to INFO, IGNORE or FAIL warnings
    -u config_url     URL of config file to use to INFO, IGNORE or FAIL warnings
    -g gen_file       generate default config file(all rules set to WARN)
    -m mins           the number of minutes to spider for (defaults to no limit)
    -r report_html    file to write the full ZAP HTML report
    -w report_md      file to write the full ZAP Wiki(Markdown) report
    -x report_xml     file to write the full ZAP XML report
    -J report_json    file to write the full ZAP JSON document
    -a                include the alpha active and passive scan rules as well
    -d                show debug messages
    -P                specify listen port
    -D                delay in seconds to wait for passive scanning 
    -i                default rules not in the config file to INFO
    -I                do not return failure on warning (post 2.9.0)
    -j                use the Ajax spider in addition to the traditional one
    -l level          minimum level to show: PASS, IGNORE, INFO, WARN or FAIL, use with -s to hide example URLs
    -n context_file   context file which will be loaded prior to scanning the target
    -p progress_file  progress file which specifies issues that are being addressed
    -s                short output format - don't show PASSes or example URLs
    -T                max time in minutes to wait for ZAP to start and the passive scan to run
    -U user           username to use for authenticated scans - must be defined in the given context file (post 2.9.0)
    -z zap_options    ZAP command line options e.g. -z "-config aaa=bbb -config ccc=ddd"
    --hook            path to python file that define your custom hooks
```

## The Pipeline

Below is the code needed to be placed into your tekton pipeline to use the Task detailed above. Note that only the *specs* section is needed to be included into an existing pipeline, as the metadata, apiVersion and kind should already be specified.

```
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: dso-pl-juice-shop
spec:
  params:
  - name: APP_URL
    type: string
    default: 'https://examples.com'
  - name: minutes
    type: string
    default: '0'
  tasks:
  - name: owasp-zap
    params:
      - name: APP_URL
        value: $(params.APP_URL)
      - name: minutes
        value: $(params.minutes)
    taskRef: 
      name: owasp-zap
```

## The Pipeline Run

The below code is what you will need to include in your Pipeline Run file, to actually run the pipeline.

```
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  generateName: dso-pl-juice-shop-
spec:
  pipelineRef:
    name: dso-pl-juice-shop
  params:
  - name: APP_URL
    value: 'https://dso-juice-shop.apps.ocp1.azure.dso.digital.mod.uk/#/'
  - name: minutes
    value: '0'
```

