# 0. Before the PoC: what to ask for and check

## OpenShift or Kubernetes cluster

- **cluster-admin access.** The operators install cluster-wide resources, and on OpenShift one
  permission must be granted. Check: `oc auth can-i '*' '*' --all-namespaces` prints `yes`.
- **OpenShift 4.11 or later** (or Kubernetes 1.30 or later). Check on OpenShift:
  `oc get scc nonroot-v2` finds it.
- **A default StorageClass with about 125 GiB free.** The platform asks for 17 disks; the object
  store is 50 GiB of that. Check: `kubectl get storageclass` shows one marked `(default)`.
- **About 4 CPU and 16 GiB memory free on the workers.** The pods request about 1.4 CPU and
  4 GiB together (platform, object store, operators, cert-manager); their limits add up to about
  15 CPU and 19 GiB, so the nodes need room for the pods to use more than they request. In a test with
  10 services sending data the pods used about 3 GiB together.
- **cert-manager**, or permission to install it. Check: `kubectl get pods -n cert-manager`.
- **A host name for the platform.** On OpenShift the Route gets one from the cluster's apps
  domain; you can also choose one.

### Images

The cluster must be able to pull these images, directly or from a mirror:

| Registry | Images |
|---|---|
| ghcr.io | `iyzitrace/auth-service:dev-72f53ed`, `iyzitrace/opamp:dev-72f53ed`, `iyzitrace/inventory-service:dev-72f53ed`, `iyzitrace/query-guard:dev-72f53ed`, `iyzitrace/holmes:dev-72f53ed`, `iyzitrace/thanos:v0.42.4-iyz.1`, `open-telemetry/opentelemetry-operator/opentelemetry-operator:0.144.0` |
| docker.io | `grafana/loki:3.7.8`, `grafana/tempo:2.10.7`, `nginx:1.30.4-alpine`, `otel/opentelemetry-collector-contrib:0.159.0`, `chrislusf/seaweedfs:4.44`, `chrislusf/seaweedfs-operator:1.0.39`, `curlimages/curl:8.8.0`, `busybox` (only `helm test` of the operators and, on plain Kubernetes, the kit's Grafana), and `grafana/grafana:13.1.1` if you install the kit's Grafana |
| quay.io | `prometheus/alertmanager:v0.34.0`, `prometheus-operator/prometheus-config-reloader:v0.93.1`, `brancz/kube-rbac-proxy:v0.20.0`, and the cert-manager images (`jetstack/cert-manager-controller`, `-cainjector`, `-webhook`, `-startupapicheck`, v1.17.2) if you install cert-manager as in step 1 |

If the cluster may pull only from your own registry, mirror these images under their original
addresses and see [../README.md](../README.md).

To check one image from a cluster node on OpenShift:

```bash
oc debug node/<node-name> -- chroot /host podman pull ghcr.io/iyzitrace/opamp:dev-72f53ed
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
| The platform's auth-service pod | api.github.com | 443 | the newest plugin version on the License page (optional; through a proxy if you have one) |
| The platform's ai-gateway pod | the AI provider's address | 443 | the AI features (optional; through a proxy if you have one) |
| Grafana's pod (the kit's Grafana) | the platform's host name | 443 | the plugin's queries |
| Grafana's pod (the kit's Grafana) | github.com, release-assets.githubusercontent.com, objects.githubusercontent.com | 443 | downloading the plugins when it starts (through a proxy if you have one) |
| The Java server | the collector on the same machine | 4318 on 127.0.0.1 | the agent's data |
