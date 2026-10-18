# IyziTrace PoC kit

Everything needed to run an IyziTrace proof of concept: platform installation, collectors on the
customer's machines, application instrumentation, and step-by-step checks. Each part is a separate
directory, so a PoC uses only the parts it needs and new ones can be added.

| Part | Available now | Directory |
|---|---|---|
| **Platform** | Kubernetes 1.30+, including OpenShift 4.11+ | [platform/kubernetes/](platform/kubernetes/README.md) |
| **Collectors** | Linux host (RHEL/Rocky/Alma, Debian/Ubuntu), systemd | [collectors/linux-host/](collectors/linux-host/) |
| **Instrumentation** | Java: OpenTelemetry Java agent + iyzitrace appserver-deployment extension | [instrumentation/java/](instrumentation/java/) |
| **Rehearsal** | a Linux host with Tomcat, run locally in Docker | [test/linux-java-host/](test/linux-java-host/README.md) |

## Typical layout: Java app servers on Linux, platform on Kubernetes/OpenShift

```text
 Linux host (each app server machine)                            Kubernetes / OpenShift
┌──────────────────────────────────────────────┐               ┌──────────────────────────────┐
│ Java app server (Tomcat, WildFly/JBoss, ...) │               │ IyziTrace platform           │
│   + OpenTelemetry Java agent 2.21.0          │               │   Ingress / Route ──► nginx  │
│   + appserver-deployment extension 0.1.0     │               │     ├─ ingest (OTLP)         │
│        │ OTLP http://127.0.0.1:4318          │               │     ├─ OpAMP (Agent Manager) │
│        ▼                                     │  HTTPS 443    │     └─ query (plugin)        │
│ OpenTelemetry Collector contrib 0.159.0      │──────────────►│                              │
│   traces, logs, JVM + host metrics, OpAMP    │  agent key    │                              │
└──────────────────────────────────────────────┘               └──────────────▲───────────────┘
                                                                              │ reader key
                                                     customer Grafana + IyziTrace plugin
```

## Step by step

| Step | What | Doc |
|---|---|---|
| 0 | Collect what the customer must provide; check access | [docs/00-prerequisites.md](docs/00-prerequisites.md) |
| 1 | Install the platform | [docs/01-platform.md](docs/01-platform.md) |
| 2 | Console (administrator, licence, department, keys) and the plugin in Grafana | [docs/02-console-and-plugin.md](docs/02-console-and-plugin.md) |
| 3 | Collector on each Linux host | [docs/03-linux-collector.md](docs/03-linux-collector.md) |
| 4 | Java agent and extension on each app server | [docs/04-java-agent.md](docs/04-java-agent.md) |
| 5 | Check every layer | [docs/05-verify.md](docs/05-verify.md) |
| — | When something does not work | [docs/06-troubleshooting.md](docs/06-troubleshooting.md) |

## Versions

| Component | Version | Source |
|---|---|---|
| IyziTrace platform images | `dev-c44dd8f` (amd64 + arm64) | `ghcr.io/iyzitrace/*`, public |
| Patched Thanos | `v0.42.4-iyz.1` | `ghcr.io/iyzitrace/thanos` |
| Platform charts | `iyzitrace-operators`/`iyzitrace-storage` `0.1.0-dev.c44dd8f`, `iyzitrace-platform` `1.3.1-dev.c44dd8f` | `oci://ghcr.io/iyzitrace/charts`, public |
| OpenTelemetry Collector contrib | 0.159.0 | GitHub releases, SHA-256 checked by `install.sh` |
| OpenTelemetry Java agent | 2.21.0 | GitHub releases, SHA-256 checked by `download.sh` |
| appserver-deployment extension | 0.1.0 | [antreklabs/iyzitrace-otel-java-extensions](https://github.com/antreklabs/iyzitrace-otel-java-extensions) releases, SHA-256 checked |

## Rehearsed

On 2026-10-18: the platform on minikube (Kubernetes 1.30); the Linux host with `test/linux-java-host`
(Rocky Linux 9, Java 17, Tomcat 10.1). Results:
[platform/kubernetes/README.md](platform/kubernetes/README.md#rehearsal-results-minikube-kubernetes-130-2026-10-18-platform-dev-at-c44dd8f).

| Java host check | Result |
|---|---|
| `install.sh`: download, SHA-256, RPM, environment file, validate | passed |
| Collector in Agent Manager (group `java-hosts`), own metrics and logs | passed |
| Agent 2.21.0 + extension in Tomcat 10.1, three applications | three services: `poc-shop/examples`, `poc-shop/docs`, `poc-shop/ROOT` |
| JVM metrics, host metrics, logs | arrive |

## Adding a part

- A new platform installation (Compose, a single VM, ...): `platform/<name>/README.md`, linked from
  `docs/01-platform.md`.
- A new collector type (Windows, Kubernetes DaemonSet, ...): `collectors/<name>/`.
- A new language (.NET, Node.js, Python, ...): `instrumentation/<language>/`.

No keys, licences or customer data belong in this repository.
