# 0. Prerequisites: what to get from the customer, and what to check

## OpenShift

| Item | Why | How to check |
|---|---|---|
| `oc` login with **cluster-admin** | the operators install CRDs; the SCC grant (step 1.2) | `oc auth can-i '*' '*' --all-namespaces` → `yes` |
| OpenShift 4.11 or later | the `nonroot-v2` SCC exists from 4.11 | `oc get scc nonroot-v2` |
| A **default StorageClass**, ~125Gi free | 17 PVCs (50Gi object store) | `oc get storageclass` (one marked `(default)`) |
| Image pulls: ghcr.io, docker.io, quay.io | the platform's images | `platform/kubernetes/check-images.sh` from a machine with the cluster's egress; or ask for a mirror |
| The admin machine reaches `ghcr.io` | `helm` pulls the charts from `oci://ghcr.io/iyzitrace/charts` | `helm show chart oci://ghcr.io/iyzitrace/charts/iyzitrace-platform --version 1.3.1-dev.c44dd8f` |
| A Route host name (default apps domain is fine) | the only entry point | `oc get ingresses.config cluster -o jsonpath='{.spec.domain}'` |
| cert-manager installed, or allowed to install | operators' webhooks, internal TLS | `oc get pods -n cert-manager`, or OperatorHub "cert-manager Operator for Red Hat OpenShift" |

Sizing: the base profile (one of each component) asks for about 2 CPU and 3.5Gi memory in requests,
up to ~14Gi in limits. Fine for a PoC on any worker node with 4 CPU / 16Gi free.

## Linux hosts (where the Java app servers run)

| Item | Why |
|---|---|
| root/sudo on each host | installing the collector package and the systemd service |
| OS: RHEL/Rocky/Alma 8–9 or Debian/Ubuntu; x86_64 or aarch64 | `collector/install.sh` handles RPM and DEB |
| **Outbound HTTPS (443) from each host to the Route host** | the collector sends there; nothing listens on the hosts for IyziTrace |
| Download access to github.com, or copy the files in | collector RPM/DEB, Java agent, extension. Without internet: run the downloads elsewhere and copy |
| A proxy, if outbound traffic must use one | `HTTPS_PROXY` in the collector's environment file |
| The Route's CA certificate, if it is not publicly trusted | `tls.ca_file` in the collector config |

## Java app servers

| Item | Why |
|---|---|
| Java 11 or later on each app server | the extension's minimum (agent 2.x needs Java 8+) |
| Which server and version (Tomcat, WildFly/JBoss EAP, WebLogic, WebSphere, Spring Boot) | where the JVM options go: [java/appservers/README.md](../java/appservers/README.md) |
| How the server is started (systemd unit, script, admin console) | same |
| A **restart window** for each server | the agent is loaded at JVM start |
| Which applications run where; names the customer uses for them | `service.namespace` per server, optional declared names per app |

## IyziTrace side

| Item | Why |
|---|---|
| The licence file | console setup |
| The customer Grafana URL (as the cluster's pods reach it) and a Grafana Admin | the plugin and Agent Manager |
| The IyziTrace plugin build for that Grafana | installed in step 2 |

## Network summary

| From | To | Port | What |
|---|---|---|---|
| Linux hosts (collector) | Route host | 443 | OTLP ingest, OpAMP, collector self-telemetry |
| Customer Grafana (server side) | Route host | 443 | plugin datasources (queries, platform API) |
| Platform pods | customer Grafana | 443/3000 | Grafana Admin verification (Agent Manager, AI settings) |
| Java app server | collector on the same host | 4317/4318 on 127.0.0.1 | OTLP from the agent |
