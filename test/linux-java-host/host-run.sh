#!/bin/sh
# Runs inside the test host: the steps of docs/03-linux-collector.md and docs/04-java-agent.md, then traffic.
set -eu
echo "== collector: install.sh"
sh /poc/collectors/linux-host/install.sh --ingest-url "$IYZITRACE_INGEST_URL" --api-key "$IYZITRACE_API_KEY" --host-name poc-java-01 --group java-hosts
( set -a; . /etc/otelcol-contrib/otelcol-contrib.conf; set +a
  nohup otelcol-contrib $OTELCOL_OPTIONS > /var/log/otelcol-contrib.log 2>&1 & )
for i in $(seq 1 30); do curl -fsS http://127.0.0.1:13133/ >/dev/null 2>&1 && break; sleep 1; done
curl -fsS http://127.0.0.1:13133/ >/dev/null && echo "collector health: OK"

echo "== java: download.sh + otel-agent.properties + setenv.sh"
sh /poc/instrumentation/java/download.sh /opt/otel
sed -i -e 's/^otel.service.name=.*/otel.service.name=tomcat-poc-01/' \
       -e 's/^otel.resource.attributes=.*/otel.resource.attributes=service.namespace=poc-shop,deployment.environment.name=poc/' /opt/otel/otel-agent.properties
cp /poc/instrumentation/java/appservers/tomcat-setenv.sh /opt/tomcat/bin/setenv.sh
/opt/tomcat/bin/catalina.sh start
for i in $(seq 1 60); do curl -fsS http://127.0.0.1:8080/ >/dev/null 2>&1 && break; sleep 1; done
grep -m1 "opentelemetry-javaagent - version" /opt/tomcat/logs/catalina.out || true

echo "== traffic (3 applications: examples, docs, ROOT)"
end=$(( $(date +%s) + ${TRAFFIC_SECONDS:-300} ))
while [ "$(date +%s)" -lt "$end" ]; do
  curl -s -o /dev/null http://127.0.0.1:8080/examples/servlets/servlet/HelloWorldExample
  curl -s -o /dev/null http://127.0.0.1:8080/examples/servlets/servlet/RequestHeaderExample
  curl -s -o /dev/null http://127.0.0.1:8080/docs/
  curl -s -o /dev/null http://127.0.0.1:8080/
  curl -s -o /dev/null http://127.0.0.1:8080/examples/no-such-page
  sleep 1
done
echo "== done; collector errors in its log:"; grep -c -i '"error"\|error' /var/log/otelcol-contrib.log || true
tail -f /dev/null
