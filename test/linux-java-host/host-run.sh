#!/bin/sh
# Runs inside the test machine: the commands of docs/03-linux-collector.md and docs/04-java-agent.md,
# as written there (files are taken from this checkout instead of raw.githubusercontent.com, so the
# version under test is the one used), then traffic to Tomcat's three applications.
set -eu
ARCH=$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')
case "$ARCH" in amd64) SHA=edf3037b5065738a118d3f21469403fb1249fad17291a803a2ba0ef7d29d74d7 ;;
                arm64) SHA=996f2010da2210dae7f50f9661e66595409d6e27c6499b6ea42f0b99c60cce9d ;; esac

echo "== docs/03 step 1-2: download, check, install the collector"
cd /tmp
curl -fsSLO https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.159.0/otelcol-contrib_0.159.0_linux_${ARCH}.rpm
echo "$SHA  otelcol-contrib_0.159.0_linux_${ARCH}.rpm" | sha256sum -c -
rpm -Uvh /tmp/otelcol-contrib_0.159.0_linux_${ARCH}.rpm >/dev/null
otelcol-contrib --version

echo "== docs/03 step 3-4: configuration and values"
cp /poc/collectors/linux-host/config.yaml /etc/otelcol-contrib/config.yaml
cp /poc/collectors/linux-host/otelcol-contrib.conf.example /etc/otelcol-contrib/otelcol-contrib.conf
chown root:otelcol-contrib /etc/otelcol-contrib/otelcol-contrib.conf
chmod 640 /etc/otelcol-contrib/otelcol-contrib.conf
sed -i -e "s|^IYZITRACE_INGEST_URL=.*|IYZITRACE_INGEST_URL=$IYZITRACE_INGEST_URL|" \
       -e "s|^IYZITRACE_API_KEY=.*|IYZITRACE_API_KEY=$IYZITRACE_API_KEY|" \
       -e "s|^IYZITRACE_HOST_NAME=.*|IYZITRACE_HOST_NAME=poc-java-01|" \
       -e "s|^IYZITRACE_AGENT_GROUP=.*|IYZITRACE_AGENT_GROUP=java-hosts|" /etc/otelcol-contrib/otelcol-contrib.conf

echo "== docs/03 step 5: check the configuration"
( set -a; . /etc/otelcol-contrib/otelcol-contrib.conf; set +a
  otelcol-contrib validate --config=/etc/otelcol-contrib/config.yaml ) && echo "config is valid"

echo "== docs/03 step 6: start (no systemd in a container: started directly with the same environment)"
( set -a; . /etc/otelcol-contrib/otelcol-contrib.conf; set +a
  nohup otelcol-contrib $OTELCOL_OPTIONS > /var/log/otelcol-contrib.log 2>&1 & )
for i in $(seq 1 30); do curl -fsS http://127.0.0.1:13133/ >/dev/null 2>&1 && break; sleep 1; done
curl -s http://127.0.0.1:13133/; echo

echo "== docs/04 step 1: agent and extension"
mkdir -p /opt/otel/extensions
cd /opt/otel
curl -fsSLo opentelemetry-javaagent.jar https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.21.0/opentelemetry-javaagent.jar
echo "5b35ccc6c275fd477a06db01923813e13d99c1a52a20b0ea8ed6576eae177c7d  opentelemetry-javaagent.jar" | sha256sum -c -
curl -fsSLo extensions/appserver-deployment-extension.jar https://github.com/antreklabs/iyzitrace-otel-java-extensions/releases/download/v0.1.0/appserver-deployment-extension-0.1.0.jar
echo "c7d81bf27569db099b19a859e5f8cd4f47f6eab7b6fd0a9661d5ef7033a83d9c  extensions/appserver-deployment-extension.jar" | sha256sum -c -

echo "== docs/04 step 2: settings file"
cp /poc/instrumentation/java/otel-agent.properties /opt/otel/otel-agent.properties
chmod -R a+rX /opt/otel
sed -i -e 's/^otel.service.name=.*/otel.service.name=tomcat-poc-01/' \
       -e 's/^otel.resource.attributes=.*/otel.resource.attributes=service.namespace=poc-shop,deployment.environment.name=poc/' /opt/otel/otel-agent.properties

echo "== docs/04 step 3: Tomcat setenv.sh"
cat > /opt/tomcat/bin/setenv.sh <<'SETENV'
CATALINA_OPTS="$CATALINA_OPTS -javaagent:/opt/otel/opentelemetry-javaagent.jar"
CATALINA_OPTS="$CATALINA_OPTS -Dotel.javaagent.configuration-file=/opt/otel/otel-agent.properties"
CATALINA_OPTS="$CATALINA_OPTS -Dotel.javaagent.extensions=/opt/otel/extensions/appserver-deployment-extension.jar"
export CATALINA_OPTS
SETENV

echo "== docs/04 step 4: start Tomcat, check the agent"
/opt/tomcat/bin/catalina.sh start
for i in $(seq 1 60); do curl -fsS http://127.0.0.1:8080/ >/dev/null 2>&1 && break; sleep 1; done
grep -m1 "opentelemetry-javaagent - version" /opt/tomcat/logs/catalina.out || true

echo "== traffic (3 applications: examples, docs, ROOT) for ${TRAFFIC_SECONDS:-300}s"
end=$(( $(date +%s) + ${TRAFFIC_SECONDS:-300} ))
while [ "$(date +%s)" -lt "$end" ]; do
  curl -s -o /dev/null http://127.0.0.1:8080/examples/servlets/servlet/HelloWorldExample
  curl -s -o /dev/null http://127.0.0.1:8080/examples/servlets/servlet/RequestHeaderExample
  curl -s -o /dev/null http://127.0.0.1:8080/docs/
  curl -s -o /dev/null http://127.0.0.1:8080/
  sleep 1
done
echo "== done"
tail -f /dev/null
