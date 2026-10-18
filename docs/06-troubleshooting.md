# 6. Troubleshooting

## Platform install

| Symptom | Cause and fix |
|---|---|
| Pods not created; events: `unable to validate against any security context constraint` | **OpenShift:** the SCC grant is missing or was done for the wrong namespace (`platform/kubernetes/openshift/scc.sh`) |
| Pods `Pending` | no default StorageClass, quota, or node capacity: `kubectl describe pod <pod> -n iyzitrace` |
| `ImagePullBackOff` | no egress or Docker Hub rate limit: `platform/kubernetes/check-images.sh`, an image pull secret, or a mirror |
| Operators never Ready | cert-manager missing or not Ready |
| `helm --wait` times out | `kubectl -n iyzitrace get pods`; the first non-Running pod's `describe` and `logs` |
| Gateway answers 503 (OpenShift Route) | nginx not Ready yet, or the Route's `targetPort` is not `http` |
| Gateway answers 502 on `/ingest` | nginx cannot reach a collector: `kubectl -n iyzitrace logs deploy/nginx` |

## Console and plugin

| Symptom | Cause and fix |
|---|---|
| Wizard: reader key not accepted | an agent key instead of a reader key, or a key of another department |
| Wizard: licence not usable | install the licence in the console first |
| Agent Manager: `grafana_admin_required` | `authService.grafanaUrl` is wrong or not reachable from the pods; the user is not a Grafana Admin |
| Screens empty, wizard passed | no data yet, or the time range is too short; check 05 |

## Collector (Linux host)

| Symptom | Cause and fix |
|---|---|
| `install.sh`: `checksum` failure | incomplete download or a proxy rewriting it; download again, or use `--package` |
| Service does not start | `journalctl -u otelcol-contrib -n 50`; usually a typo in `otelcol-contrib.conf` |
| Log: `401` / `Unauthorized` | wrong key, or a reader key used instead of the agent key |
| Log: `x509: certificate signed by unknown authority` | the gateway uses a private CA: `tls.ca_file` (03, Options) |
| Log: `connection refused` / timeouts to the gateway | firewall or proxy: `curl -v https://GATEWAY/healthz` from the host; `HTTPS_PROXY` |
| Agent Manager lists the collector, drawer empty | `lawrence.agentHttpEndpoint` not set to `https://GATEWAY/ingest/opamp/v1/telemetry/` (platform install, step 6) |
| Collector not in Agent Manager | OpAMP blocked, or the key belongs to another department |
| Warning `failed to get host ID` | harmless |

## Java agent

| Symptom | Cause and fix |
|---|---|
| No `opentelemetry-javaagent - version` line | the `-javaagent` option is not applied: check where the server reads its options (java/appservers/README.md) |
| Server fails at start with the agent (WildFly/JBoss LogManager errors) | add the commented options in `wildfly-standalone.conf` |
| Agent log: `Failed to export spans` / connection refused to 127.0.0.1:4318 | the collector is not running on the host |
| Traces arrive, no `appserver.deployment.*` attributes, one service per server | the extension is not loaded: path and read permission of `/opt/otel/extensions/...` |
| HTTP server spans lack the attributes, child spans have them | a Servlet 2.x application, or a newer agent than tested (keep 2.21.0) |
| Startup work not attributed (Tomcat) | expected until the application's first request |
| No logs | `otel.logs.exporter=otlp` missing in `otel-agent.properties` |
| Too much data | sampling: `otel.traces.sampler=parentbased_traceidratio`, `otel.traces.sampler.arg=0.1` |

## Collecting information for support

```bash
# Platform
kubectl -n iyzitrace get pods -o wide
kubectl -n iyzitrace get events --sort-by=.lastTimestamp | tail -30
# Host
journalctl -u otelcol-contrib --since "30 min ago" --no-pager > otelcol.log
otelcol-contrib --version
java -version
```

Never paste agent or reader keys into tickets or chats; the logs above do not contain them.
