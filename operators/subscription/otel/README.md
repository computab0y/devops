# <img src="https://opentelemetry.io/img/logos/opentelemetry-logo-nav.png" alt="OpenTelemetry Icon" width="45" height=""> OpenTelemetry Operator

This operator implements *Custom Cluster Service Version*

The reasoning behind:

The CSV that comes from the community catalogue has images hosted in ghcr.io/gcr.io. Hence the subscription installation fails. So here we create a custom csv that retrieves the images via artifactory. So when the subscription uses this CSV, images are pulled down from gcr.io via artifactory.

This is a workaround implemented to get around the fact that community operator for opentelemetry uses ghcr.io/gcr.io as their image repository which is not accessible from our landing zones.

# <img src="https://opentelemetry.io/img/logos/opentelemetry-logo-nav.png" alt="OpenTelemetry Icon" width="45" height=""> OpenTelemetry Collector

The OpenTelemetry Collector offers a vendor-agnostic implementation on how to
receive, process and export telemetry data. In addition, it removes the need
to run, operate and maintain multiple agents/collectors in order to support
open-source telemetry data formats (e.g. Jaeger, Prometheus, etc.) to
multiple open-source or commercial back-ends.
