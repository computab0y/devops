### Grafana instalation
1. litmus-monitoring is deployed using gitops apporach
2. Add secret token to enable metrics fetch from cluster prometheus:
2.1. Get token `oc sa get-token grafana -n litmus-monitoring`
2.2. Update litmus-grafana-datasources configmap Bearer token value.