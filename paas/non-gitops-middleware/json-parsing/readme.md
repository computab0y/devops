## JSON parsing 


**Creating Sample Index**

- index: app-httpd-one-write <br>
Targeting pod _app-number-one-*_ in demo-app project for Test 


Additional considerations: 

- The Elasticsearch index for structured records is formed by prepending "app-" to the structured type and appending "-write".

**Viewing logging collector pods**

`$ oc get pods --selector component=collector -o wide -n openshift-logging`