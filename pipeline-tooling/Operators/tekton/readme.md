# Tekton

[Tekton - Cloud Native CI/CD](https://tekton.dev/)

Tekton is an open source project that provides a framework to create cloud-native CI/CD pipelines quickly. As a Kubernetes-native framework, Tekton makes it easier to deploy across multiple cloud providers or hybrid environments.​ 
By leveraging the Custom Resource Definitions (CRDs) in Kubernetes, Tekton uses the Kubernetes control plane to run pipeline tasks. By using standard industry specifications, Tekton will work well with existing CI/CD tools such as Jenkins, Jenkins X, Skaffold, Knative, and now OpenShift.​

Tekton was produced by Google

Tekton lets you build, test, and deploy across multiple environments such as VMs, serverless, Kubernetes, or Firebase. You can also deploy across multiple cloud providers or hybrid environments using Tekton pipelines.

Customizable. Tekton entities are fully customizable, allowing for a high degree of flexibility. Platform engineers can define a highly detailed catalog of building blocks for developers to use in a wide variety of scenarios.

Reusable. Tekton entities are fully portable, so once defined, anyone within the organization can use a given pipeline and reuse its building blocks. This allows developers to quickly build complex pipelines without “reinventing the wheel.”

Expandable. Tekton Catalog is a community-driven repository of Tekton building blocks. You can quickly create new and expand existing pipelines using pre-made components from the Tekton Catalog.

Standardized. Tekton installs and runs as an extension on your Kubernetes cluster and uses the well-established Kubernetes resource model. Tekton workloads execute inside Kubernetes containers.

Scalable. To increase your workload capacity, you can simply add nodes to your cluster. Tekton scales with your cluster without the need to redefine your resource allocations or any other modifications to your pipelines.

## Installation

Use the OpenShift console, runt he following command:

```bash
oc apply -f 01.sub-pipeline.yaml
```

## Usage

```python
........
```

## Contributing
Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

Please make sure to update tests as appropriate.

## License
[MIT](https://choosealicense.com/licenses/mit/)