# Rehearsal: a Linux host with a Java app server

Runs [docs/03-linux-collector.md](../../docs/03-linux-collector.md) and
[docs/04-java-agent.md](../../docs/04-java-agent.md) on a Rocky Linux 9 container (RHEL-compatible)
with Java 17 and Tomcat 10.1: `collectors/linux-host/install.sh` and `instrumentation/java/download.sh`
run exactly as written. Then it sends traffic to Tomcat's three bundled applications (`examples`,
`docs`, `ROOT`) for `TRAFFIC_SECONDS` (default 300).

Needs Docker, a running IyziTrace reachable from containers, and a department's **agent** key.

```bash
# from the repository root
docker build -t iyzitrace-poc-javahost -f test/linux-java-host/Dockerfile .
docker run -d --name poc-java-01 --hostname poc-java-01 \
  -e IYZITRACE_INGEST_URL=https://GATEWAY/ingest \
  -e IYZITRACE_API_KEY='AGENT-KEY' \
  iyzitrace-poc-javahost
docker logs -f poc-java-01
```

For a platform on the same machine (Compose, or a port-forward to nginx on port 80), use
`IYZITRACE_INGEST_URL=http://host.docker.internal/ingest`.

Expected in IyziTrace after 2–3 minutes:
- Agent Manager: `otelcol-poc-java-01` (group `java-hosts`) Online, with its metrics and logs;
- Services: `poc-shop/examples`, `poc-shop/docs`, `poc-shop/ROOT`;
- JVM metrics of `tomcat-poc-01`, host metrics of `poc-java-01`, Tomcat's logs.

Clean up: `docker rm -f poc-java-01`.
