# 5. Check every layer

Work from the bottom up; each layer depends on the one before.

## 5.1 On the Linux host

```bash
systemctl is-active otelcol-contrib                       # active
curl -s http://127.0.0.1:13133/ ; echo                     # "Server available"
journalctl -u otelcol-contrib --since "10 min ago" --no-pager | grep -i -E "error|refused|401|403" | tail
grep "opentelemetry-javaagent - version" <server log>      # 2.21.0
```

Send a test span through the collector, without Java:

```bash
now=$(date +%s%N)
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:4318/v1/traces \
  -H 'Content-Type: application/json' -d '{"resourceSpans":[{"resource":{"attributes":[
   {"key":"service.name","value":{"stringValue":"poc-smoke"}},
   {"key":"service.namespace","value":{"stringValue":"poc-smoke"}}]},
  "scopeSpans":[{"spans":[{"traceId":"5b8efff798038103d269b633813fc60c","spanId":"eee19b7ec3c1b174",
   "name":"smoke","kind":2,"startTimeUnixNano":"'$((now-50000000))'","endTimeUnixNano":"'$now'"}]}]}]}'
# 200; the trace 5b8efff798038103d269b633813fc60c shows in IyziTrace within a minute
```

## 5.2 In IyziTrace (Grafana)

| Screen | What you should see | If not |
|---|---|---|
| **Agent Manager → Agents** | `otelcol-<host>` in group `java-hosts`, Online; drawer Metrics and Logs filled | collector not running, wrong key, or `lawrence.agentHttpEndpoint` (06) |
| **Services** | one service per application (`<namespace>/<context-root>`), with requests, latency, errors | no traffic yet; agent not loaded; see 06 |
| **Service detail → Operations** | the HTTP routes (`GET /orders/{id}`), JDBC calls as dependencies | |
| **Trace Pulse** | traces of the applications; open one: HTTP server span, JDBC/HTTP client spans | |
| **Log Studio** | the server's logs (service = the server name or the application) | `otel.logs.exporter=otlp` missing |
| **Atlas / Horizon** | the host (CPU, memory), its services grouped by namespace | host metrics take 1–2 minutes |
| **Service Map** | applications and their databases/downstreams | needs calls between them |

Span metrics (requests, latency per service) are computed in 5-minute windows: the first figures
appear about 1–2 minutes after the first requests.

## 5.3 Through the gateway, without Grafana (optional)

With the department's **reader** key:

```bash
R=READER-KEY
curl -s -G -H "Authorization: Bearer $R" https://$GATEWAY/query/v1/metrics/api/v1/query \
  --data-urlencode 'query=sum by (service_namespace,service_name)(rate(iyzitrace_span_metrics_calls_total[5m]))'
curl -s -H "Authorization: Bearer $R" https://$GATEWAY/api/v1/platform/auth/whoami    # tenant, licence, version
```
