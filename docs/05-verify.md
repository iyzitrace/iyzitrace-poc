# 5. Check that everything works

Check from the bottom up: the Java server, then the collector, then IyziTrace.

## On the Linux machine

Is the collector running?

```bash
systemctl status otelcol-contrib --no-pager
```

You should see `active (running)`.

Did the agent start inside the Java server? (Tomcat shown; on WildFly use
`$JBOSS_HOME/standalone/log/server.log`.)

```bash
grep "opentelemetry-javaagent - version" $CATALINA_BASE/logs/catalina.out
```

You should see `opentelemetry-javaagent - version: 2.21.0`.

Does the collector reach IyziTrace? This shows only problems from the last 10 minutes:

```bash
journalctl -u otelcol-contrib --since "10 min ago" --no-pager | grep -i -E "error|refused|401|403"
```

No output is good. `401` or `403` means a wrong key (see [06-troubleshooting.md](06-troubleshooting.md)).

## In IyziTrace (Grafana)

Open each of these screens:

| Screen | You should see |
|---|---|
| **Agent Manager → Agents** | `otelcol-<machine name>` in group `java-hosts`, Online. Open it: Metrics and Logs are filled |
| **Services** | one service per application, for example `orders/orders`, with requests, latency and errors |
| **Services → open a service → Operations** | the HTTP routes, such as `GET /orders/{id}`, and database calls |
| **Trace Pulse** | traces; open one to see the HTTP request and the database or HTTP calls under it |
| **Log Studio** | the server's logs |
| **Atlas** or **Horizon** | the machine with its CPU and memory, and its services grouped by namespace |
| **Service Map** | the applications and the databases and services they call |

Request counts and latency appear one to two minutes after the first requests.

## A test without Java

To check the collector and IyziTrace without the Java server, send one test trace by hand. Run this
on the Linux machine:

```bash
now=$(date +%s%N)
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:4318/v1/traces \
  -H 'Content-Type: application/json' \
  -d '{"resourceSpans":[{"resource":{"attributes":[
        {"key":"service.name","value":{"stringValue":"poc-smoke"}},
        {"key":"service.namespace","value":{"stringValue":"poc-smoke"}}]},
      "scopeSpans":[{"spans":[{"traceId":"5b8efff798038103d269b633813fc60c","spanId":"eee19b7ec3c1b174",
        "name":"smoke","kind":2,"startTimeUnixNano":"'$((now-50000000))'","endTimeUnixNano":"'$now'"}]}]}]}'
```

It prints `200`. Within a minute the service `poc-smoke/poc-smoke` appears in Services, and Trace
Pulse finds the trace `5b8efff798038103d269b633813fc60c`.
