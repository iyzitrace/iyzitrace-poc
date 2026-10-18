# 1. Install the platform

Pick the installation that fits the customer's environment:

| Environment | Guide |
|---|---|
| Kubernetes 1.30+ (any distribution) | [platform/kubernetes/README.md](../platform/kubernetes/README.md) |
| OpenShift 4.11+ | the same guide, with its [OpenShift](../platform/kubernetes/README.md#openshift) section |

At the end you have:

- the platform running, reachable at one HTTPS host name (`GATEWAY`): an Ingress host on Kubernetes,
  a Route on OpenShift;
- `https://GATEWAY/healthz` answering `ok`.

Next: [02-console-and-plugin.md](02-console-and-plugin.md).
