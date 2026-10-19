# 0. Before the PoC: what to ask for and check

## OpenShift or Kubernetes cluster

- **cluster-admin access.** The operators install cluster-wide resources, and on OpenShift one
  permission must be granted. Check: `oc auth can-i '*' '*' --all-namespaces` prints `yes`.
- **OpenShift 4.11 or later** (or Kubernetes 1.30 or later). Check on OpenShift:
  `oc get scc nonroot-v2` finds it.
- **A default StorageClass with about 125 GiB free.** The platform asks for 17 disks; the object
  store is 50 GiB of that. Check: `kubectl get storageclass` shows one marked `(default)`.
- **About 4 CPU and 16 GiB memory free on the workers.**
- **cert-manager**, or permission to install it. Check: `kubectl get pods -n cert-manager`.
- **A host name for the platform.** On OpenShift the Route gets one from the cluster's apps
  domain; you can also choose one.

### Images

The cluster must be able to pull these images, directly or from a mirror:

| Registry | Images |
|---|---|
| ghcr.io | `iyzitrace/auth-service:dev-c44dd8f`, `iyzitrace/opamp:dev-c44dd8f`, `iyzitrace/inventory-service:dev-c44dd8f`, `iyzitrace/query-guard:dev-c44dd8f`, `iyzitrace/holmes:dev-c44dd8f`, `iyzitrace/thanos:v0.42.4-iyz.1`, `open-telemetry/opentelemetry-operator/opentelemetry-operator:0.144.0` |
| docker.io | `grafana/loki:3.7.8`, `grafana/tempo:2.10.7`, `nginx:1.30.4-alpine`, `otel/opentelemetry-collector-contrib:0.159.0`, `chrislusf/seaweedfs:4.44`, `chrislusf/seaweedfs-operator:1.0.39`, `curlimages/curl:8.8.0`, and `grafana/grafana:13.1.1` if you install the kit's Grafana |
| quay.io | `prometheus/alertmanager:v0.34.0`, `prometheus-operator/prometheus-config-reloader:v0.93.1`, and the cert-manager images if you install it from its manifest |

To check one image from a cluster node on OpenShift:

```bash
oc debug node/<node-name> -- chroot /host podman pull ghcr.io/iyzitrace/opamp:dev-c44dd8f
```

Docker Hub limits anonymous pulls. On a busy shared cluster, ask whether a pull secret or a mirror
exists.

## Linux machines where the Java servers run

- **root or sudo** on each machine.
- **The operating system:** RHEL, Rocky or Alma 8 or 9, or Debian or Ubuntu; x86_64 or arm64.
- **Outbound HTTPS (port 443) from each machine to the platform's host name.** Nothing listens on
  the machines for IyziTrace.
- **Downloads from github.com**, or a way to copy files to the machines: the collector package,
  the Java agent and the extension.
- **The proxy address**, if outbound traffic must go through one.
- **The CA certificate of the platform's host name**, if it is signed by an internal CA.

## Java servers

- **Java 11 or later.**
- **Which server and version:** Tomcat, WildFly / JBoss EAP, WebLogic, WebSphere, Spring Boot. And
  how it is started (systemd, a script, the admin console). This decides where the agent settings
  go.
- **A restart window for each server.** The agent loads when the JVM starts.
- **Which applications run on which server, and what the customer calls them.**

## IyziTrace

- The **licence file**.
- A **Grafana 12.3 or later** with a **Grafana administrator**, and its address as the cluster can reach it.
  Either the customer's Grafana, with the **IyziTrace plugin** build for its version, or the Grafana
  this kit installs, which already has the plugin: [grafana/kubernetes](../grafana/kubernetes/README.md).

## Network, in one table

| From | To | Port | What for |
|---|---|---|---|
| Collectors on the Linux machines | the platform's host name | 443 | sending data, Agent Manager |
| The customer's Grafana server | the platform's host name | 443 | the plugin's queries |
| The platform's pods | the customer's Grafana | 443 or 3000 | checking Grafana administrators |
| People's browsers | Grafana's host name | 443 | using IyziTrace |
| Grafana's pod (the kit's Grafana) | the platform's host name | 443 | the plugin's queries |
| Grafana's pod (the kit's Grafana) | github.com | 443 | downloading the plugins when it starts |
| The Java server | the collector on the same machine | 4318 on 127.0.0.1 | the agent's data |
