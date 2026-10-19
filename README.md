# IyziTrace PoC

How to set up an IyziTrace proof of concept, step by step: the platform, collectors on the
customer's machines, and application instrumentation.

Today this covers the platform on Kubernetes or OpenShift, and Java servers on Linux machines.
Other platforms and languages will be added the same way.

## How the pieces fit

```text
 Linux machine (each one that runs a Java server)                 Kubernetes / OpenShift
┌──────────────────────────────────────────────┐               ┌──────────────────────────────┐
│ Java server (Tomcat, WildFly/JBoss, ...)     │               │ IyziTrace platform           │
│   + OpenTelemetry Java agent                 │               │   behind one host name       │
│   + iyzitrace appserver-deployment extension │               │   (Route or Ingress)         │
│        │ sends to 127.0.0.1:4318             │               │                              │
│        ▼                                     │  HTTPS 443    │                              │
│ OpenTelemetry Collector                      │──────────────►│                              │
│   adds the machine's metrics                 │  agent key    │                              │
└──────────────────────────────────────────────┘               └──────────────▲───────────────┘
                                                                              │ reader key
                                                     the customer's Grafana + IyziTrace plugin
```

## Steps

1. [Before the PoC: what to ask for and check](docs/00-prerequisites.md)
2. [Install the platform](docs/01-platform.md), and Grafana with the plugin if the customer has none
3. [Console and plugin](docs/02-console-and-plugin.md): administrator, licence, department, keys,
   and the plugin in Grafana
4. [Collector on each Linux machine](docs/03-linux-collector.md)
5. [Java agent on each Java server](docs/04-java-agent.md)
6. [Check that everything works](docs/05-verify.md)
7. [When something does not work](docs/06-troubleshooting.md)

Every step is written as commands you can copy. The few files you need are in this repository and
are downloaded in the steps:

| File | What it is |
|---|---|
| [platform/kubernetes/values.yaml](platform/kubernetes/values.yaml) | the one settings file for the operators, the object store and the platform; you change two addresses, and places marked `EDIT` cover a proxy or your own registry |
| [platform/kubernetes/values-cert-manager.yaml](platform/kubernetes/values-cert-manager.yaml) | the settings for cert-manager (its chart accepts only its own keys) |
| [grafana/kubernetes/values.yaml](grafana/kubernetes/values.yaml) | settings for the Grafana Helm chart (with the IyziTrace plugin), when the customer has none; the places that depend on the cluster (OpenShift, registry, proxy, CA) are marked `EDIT` |
| [collectors/linux-host/config.yaml](collectors/linux-host/config.yaml) | the collector's configuration, the same on every machine |
| [collectors/linux-host/otelcol-contrib.conf.example](collectors/linux-host/otelcol-contrib.conf.example) | the values that differ per machine: address, key, name |
| [instrumentation/java/otel-agent.properties](instrumentation/java/otel-agent.properties) | the Java agent's settings |

## Versions

| What | Version |
|---|---|
| Platform charts (`oci://ghcr.io/iyzitrace/charts`) | `iyzitrace-operators` and `iyzitrace-storage` `0.1.0-dev.0d769a0`, `iyzitrace-platform` `1.3.1-dev.0d769a0` |
| Platform images (`ghcr.io/iyzitrace`) | `dev-c44dd8f`; Thanos `v0.42.4-iyz.1` |
| OpenTelemetry Collector (contrib) | 0.159.0 |
| Grafana (kit): chart `grafana-community/grafana` | `14.0.1`, Grafana 13.1.1; IyziTrace plugin 1.3.1 from the `dev` branch at `de49fe9f` (release `grafana-plugin-dev.de49fe9`), Infinity 4.1.1, Plotly panel 0.5.0 |
| OpenTelemetry Java agent | 2.21.0 |
| iyzitrace appserver-deployment extension | 0.1.0 ([source](https://github.com/antreklabs/iyzitrace-otel-java-extensions)) |

## What was tested

On 2026-10-18:

- The platform on a local Kubernetes 1.30, installed from the published charts.
- The automated end-to-end test, the plugin's setup wizard, and a 5-minute restart test.
- A Rocky Linux 9 machine with Tomcat 10.1 going through steps 4 and 5 exactly as written. Its three
  applications appeared in IyziTrace as three services, and the collector appeared in Agent Manager
  with its metrics and logs.

On 2026-10-19, the published charts above with cert-manager installed through Helm and
`values.yaml`: every container of cert-manager, the operators and the platform (45 + 3 + 3) has CPU
and memory requests and limits, 33 of 33 platform pods run, the automated test passes, and no pod was
restarted or killed for memory.

Details are at the end of the [platform guide](platform/kubernetes/README.md#what-was-tested-before-the-first-openshift-poc),
and the Linux test is in [test/linux-java-host](test/linux-java-host/README.md).

## Keep keys out of this repository

Agent and reader keys and the licence file never belong here.
