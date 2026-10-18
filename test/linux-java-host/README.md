# Test: a Linux machine with a Java server

This is how the Linux steps of this repository were tested. It is for us, not for the customer.

A Rocky Linux 9 container (RHEL-compatible) with Java 17 and Tomcat 10.1 runs the commands of
[docs/03-linux-collector.md](../../docs/03-linux-collector.md) and
[docs/04-java-agent.md](../../docs/04-java-agent.md) as written there
([host-run.sh](host-run.sh)), then opens Tomcat's three bundled applications (`examples`, `docs`,
`ROOT`) every second for 5 minutes.

You need Docker, a running IyziTrace that containers can reach, and a department's agent key.
From the repository's top folder:

```bash
docker build -t iyzitrace-poc-javahost -f test/linux-java-host/Dockerfile .
docker run -d --name poc-java-01 --hostname poc-java-01 \
  -e IYZITRACE_INGEST_URL=https://<route-host>/ingest \
  -e IYZITRACE_API_KEY='<agent-key>' \
  iyzitrace-poc-javahost
docker logs -f poc-java-01
```

If IyziTrace runs on the same computer behind port 80, use
`IYZITRACE_INGEST_URL=http://host.docker.internal/ingest`.

After two or three minutes, IyziTrace shows:

- in Agent Manager, `otelcol-poc-java-01` (group `java-hosts`) Online, with its metrics and logs;
- in Services, `poc-shop/examples`, `poc-shop/docs` and `poc-shop/ROOT`;
- the JVM metrics of `tomcat-poc-01`, the metrics of the machine `poc-java-01`, and Tomcat's logs.

Remove it with `docker rm -f poc-java-01`.
