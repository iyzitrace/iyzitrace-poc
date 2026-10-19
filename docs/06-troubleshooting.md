# 6. When something does not work

## Installing the platform

| What you see | What to do |
|---|---|
| Pods are not created; the events say `unable to validate against any security context constraint` | OpenShift: run the two `oc adm policy add-scc-to-group nonroot-v2 ...` commands from step 2 of the platform guide |
| Pods stay `Pending` | `kubectl -n iyzitrace describe pod <pod>` shows why: usually no default StorageClass, or not enough CPU or memory |
| `ImagePullBackOff` | the cluster cannot reach the registry, or Docker Hub's pull limit was hit. Check one image from a node (see [00-prerequisites.md](00-prerequisites.md#images)); ask for a pull secret or a mirror |
| The operators never become ready | cert-manager is missing or not ready: `kubectl get pods -n cert-manager` |
| `helm ... --wait` times out | `kubectl -n iyzitrace get pods`, then `kubectl -n iyzitrace describe pod <first pod that is not Running>` and `kubectl -n iyzitrace logs <that pod>` |
| The Route answers 503 | nginx is not ready yet: `kubectl -n iyzitrace get pods -l app.kubernetes.io/component=nginx` |
| `/ingest` answers 502 | nginx cannot reach a collector: `kubectl -n iyzitrace logs deploy/nginx` |

## Console and plugin

| What you see | What to do |
|---|---|
| The wizard does not accept the key | you used the agent key, or a key of another department. Use the department's **reader** key |
| The wizard says the licence is not usable | install the licence in the console first |
| Agent Manager says `grafana_admin_required` | the Grafana address in `values.yaml` is wrong or the cluster cannot reach it, or you are not a Grafana administrator |
| A data source test or the wizard says `x509: certificate signed by unknown authority` | Grafana does not trust the platform's certificate (a Route signed by the cluster's own CA): [grafana/kubernetes/README.md](../grafana/kubernetes/README.md#if-the-platforms-route-uses-a-certificate-grafana-does-not-trust) |
| The wizard passed but the screens are empty | no data has arrived yet, or the time range is too short. Go through [05-verify.md](05-verify.md) |

## Collector on a Linux machine

| What you see | What to do |
|---|---|
| `sha256sum` does not say `OK` | the download is incomplete or a proxy changed it. Download again |
| The service does not start | `journalctl -u otelcol-contrib -n 50 --no-pager`; usually a typo in `/etc/otelcol-contrib/otelcol-contrib.conf` |
| The log shows `401` or `Unauthorized` | wrong key: use the department's **agent** key |
| The log shows `x509: certificate signed by unknown authority` | the platform's certificate is from an internal CA: see the end of [03-linux-collector.md](03-linux-collector.md) |
| The log shows `connection refused` or timeouts | a firewall or proxy is in the way. Test from the machine: `curl -v https://<route-host>/healthz`. Set `HTTPS_PROXY` if needed |
| The collector is in Agent Manager, but its Metrics and Logs tabs are empty | `lawrence.agentHttpEndpoint` in `values.yaml` is not `https://<route-host>/ingest/opamp/v1/telemetry/`. Fix it and run the platform's `helm upgrade` again |
| The collector is not in Agent Manager | the key belongs to another department, or traffic to the platform is blocked |
| Warning `failed to get host ID` | harmless |

## Java agent

| What you see | What to do |
|---|---|
| No `opentelemetry-javaagent - version` line in the server log | the three JVM options are not applied: check where your server reads its options ([04-java-agent.md](04-java-agent.md), step 3) |
| WildFly or JBoss does not start with the agent, with LogManager errors | add `-Djava.util.logging.manager=org.jboss.logmanager.LogManager` and `-Djboss.modules.system.pkgs=org.jboss.byteman,org.jboss.logmanager,io.opentelemetry` to `JAVA_OPTS` |
| The agent log says `Failed to export` or `connection refused` to 127.0.0.1:4318 | the collector is not running on the machine |
| Traces arrive, but there is one service per server instead of one per application | the extension is not loaded: check the path in `-Dotel.javaagent.extensions` and that the server's user can read the file |
| Background work right after start-up has no application (Tomcat) | expected until the application has served its first request |
| No logs | `otel.logs.exporter=otlp` is missing from `otel-agent.properties` |
| Too much data | in `otel-agent.properties`: `otel.traces.sampler=parentbased_traceidratio` and `otel.traces.sampler.arg=0.1` |

## Information to collect for support

On the cluster:

```bash
kubectl -n iyzitrace get pods -o wide
kubectl -n iyzitrace get events --sort-by=.lastTimestamp | tail -30
```

On the Linux machine:

```bash
journalctl -u otelcol-contrib --since "30 min ago" --no-pager > otelcol.log
otelcol-contrib --version
java -version
```

These outputs contain no keys. Never paste an agent or reader key into a ticket or a chat.
