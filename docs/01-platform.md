# 1. Install the platform

| Where it runs | Guide |
|---|---|
| Kubernetes 1.30+ or OpenShift 4.11+ | [platform/kubernetes/README.md](../platform/kubernetes/README.md) |

## Grafana

The plugin lives in Grafana, and the platform needs Grafana's address (`authService.grafanaUrl`). If the
customer has no Grafana to use, install the kit's Grafana **before** the platform:
[grafana/kubernetes/README.md](../grafana/kubernetes/README.md). It has the IyziTrace plugin and the
plugins it needs, and works on OpenShift.

When you are done, `https://<route-host>/healthz` answers `ok`.

Next: [02-console-and-plugin.md](02-console-and-plugin.md).
