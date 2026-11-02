#!/bin/sh
# Runs inside the lab's Linux machine: the commands of docs/03-linux-collector.md,
# docs/04-java-agent.md (WildFly) and docs/07-ibm-mq.md as written there (files are taken from this
# checkout instead of raw.githubusercontent.com, so the version under test is the one used), then
# orders to the lab's applications.
set -eu

echo "== docs/03 step 1-2: download, check, install the collector"
cd /tmp
curl -fsSLO https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.159.0/otelcol-contrib_0.159.0_linux_amd64.rpm
echo "edf3037b5065738a118d3f21469403fb1249fad17291a803a2ba0ef7d29d74d7  otelcol-contrib_0.159.0_linux_amd64.rpm" | sha256sum -c -
rpm -Uvh /tmp/otelcol-contrib_0.159.0_linux_amd64.rpm >/dev/null

echo "== docs/03 step 3-4: configuration and values"
cp /poc/collectors/linux-host/config.yaml /etc/otelcol-contrib/config.yaml
cp /poc/collectors/linux-host/otelcol-contrib.conf.example /etc/otelcol-contrib/otelcol-contrib.conf
chown root:otelcol-contrib /etc/otelcol-contrib/otelcol-contrib.conf
chmod 640 /etc/otelcol-contrib/otelcol-contrib.conf
sed -i -e "s|^IYZITRACE_INGEST_URL=.*|IYZITRACE_INGEST_URL=$IYZITRACE_INGEST_URL|" \
       -e "s|^IYZITRACE_API_KEY=.*|IYZITRACE_API_KEY=$IYZITRACE_API_KEY|" \
       -e "s|^IYZITRACE_HOST_NAME=.*|IYZITRACE_HOST_NAME=poc-mq-01|" \
       -e "s|^IYZITRACE_AGENT_GROUP=.*|IYZITRACE_AGENT_GROUP=mq-hosts|" /etc/otelcol-contrib/otelcol-contrib.conf

echo "== docs/03 step 5-6: check and start (no systemd in a container: started directly with the same environment)"
( set -a; . /etc/otelcol-contrib/otelcol-contrib.conf; set +a
  otelcol-contrib validate --config=/etc/otelcol-contrib/config.yaml
  nohup otelcol-contrib $OTELCOL_OPTIONS > /var/log/otelcol-contrib.log 2>&1 & )
for i in $(seq 1 30); do curl -fsS http://127.0.0.1:13133/ >/dev/null 2>&1 && break; sleep 1; done

echo "== docs/04 step 1-2: agent, extension and settings"
mkdir -p /opt/otel/extensions
cd /opt/otel
curl -fsSLo opentelemetry-javaagent.jar https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.21.0/opentelemetry-javaagent.jar
echo "5b35ccc6c275fd477a06db01923813e13d99c1a52a20b0ea8ed6576eae177c7d  opentelemetry-javaagent.jar" | sha256sum -c -
curl -fsSLo extensions/appserver-deployment-extension.jar https://github.com/antreklabs/iyzitrace-otel-java-extensions/releases/download/v0.1.0/appserver-deployment-extension-0.1.0.jar
echo "c7d81bf27569db099b19a859e5f8cd4f47f6eab7b6fd0a9661d5ef7033a83d9c  extensions/appserver-deployment-extension.jar" | sha256sum -c -
cp /poc/instrumentation/java/otel-agent.properties /opt/otel/otel-agent.properties
chmod -R a+rX /opt/otel
sed -i -e 's/^otel.service.name=.*/otel.service.name=wildfly-poc-mq-01/' \
       -e 's/^otel.resource.attributes=.*/otel.resource.attributes=service.namespace=poc-orders,deployment.environment.name=poc/' /opt/otel/otel-agent.properties

echo "== docs/07 step 6: the IBM MQ extension next to the agent's other extensions"
cd /opt/otel
curl -fsSLo extensions/ibm-mq-extension.jar https://github.com/antreklabs/iyzitrace-otel-java-extensions/releases/download/v0.2.0/ibm-mq-extension-0.2.0.jar
echo "7efa3024b25055174a138d9b76fb892efa3e6f9efbdddb656172864b6fad6fd8  extensions/ibm-mq-extension.jar" | sha256sum -c -

echo "== docs/04 step 3: WildFly standalone.conf"
cat >> /opt/wildfly/bin/standalone.conf <<'CONF'
JAVA_OPTS="$JAVA_OPTS -javaagent:/opt/otel/opentelemetry-javaagent.jar"
JAVA_OPTS="$JAVA_OPTS -Dotel.javaagent.configuration-file=/opt/otel/otel-agent.properties"
JAVA_OPTS="$JAVA_OPTS -Dotel.javaagent.extensions=/opt/otel/extensions"
CONF

echo "== docs/04 step 4: start WildFly (the applications read the queue managers' addresses from the environment)"
export MQ_QM1_CONNNAME='qm1(1414)' MQ_QM2_CONNNAME='qm2(1414)' MQ_APP_CHANNEL=DEV.APP.SVRCONN MQ_APP_USER=app
MQ_APP_PASSWORD=$(cat /run/secrets/mqAppPassword); export MQ_APP_PASSWORD
nohup /opt/wildfly/bin/standalone.sh -b 127.0.0.1 > /dev/null 2>&1 &
for i in $(seq 1 180); do curl -fsS http://127.0.0.1:8080/orders-api/order -o /dev/null 2>/dev/null && break; sleep 2; done
grep -m1 "opentelemetry-javaagent - version" /opt/wildfly/standalone/log/server.log || true

echo "== docs/07 step 2: the MQ client libraries"
mkdir -p /opt/mqm
cd /opt/mqm
curl -fsSLO https://public.dhe.ibm.com/ibmdl/export/pub/software/websphere/messaging/mqdev/redist/10.0.1.0-IBM-MQC-Redist-LinuxX64.tar.gz
echo "f8f467d5e42001cc5cbe780b07d971fd2b0850de321753c4814ceced5248915e  10.0.1.0-IBM-MQC-Redist-LinuxX64.tar.gz" | sha256sum -c -
tar -xzf 10.0.1.0-IBM-MQC-Redist-LinuxX64.tar.gz
rm 10.0.1.0-IBM-MQC-Redist-LinuxX64.tar.gz

echo "== docs/07 step 3: mq_otel, its user and its configuration"
useradd -r -m -d /var/lib/mq_otel -s /sbin/nologin mqotel
install -D -m 0755 /poc/test/ibm-mq/build/mq_otel /opt/mq_otel/mq_otel
install -D -m 0644 /poc/collectors/ibm-mq/mq_otel.yaml /etc/mq_otel/mq_otel.yaml
for qm in QM1 QM2; do
  host=$(echo "$qm" | tr 'A-Z' 'a-z')
  # Lab: the monitoring channel maps to iyzmon without a password, so no user and password lines.
  sed -e "s|^IBMMQ_CONNECTION_QUEUEMANAGER=.*|IBMMQ_CONNECTION_QUEUEMANAGER=$qm|" \
      -e "s|^IBMMQ_CONNECTION_CONNNAME=.*|IBMMQ_CONNECTION_CONNNAME='$host(1414)'|" \
      -e "s|^IBMMQ_CONNECTION_METADATAVALUES=.*|IBMMQ_CONNECTION_METADATAVALUES=$host:1414|" \
      -e '/^IBMMQ_CONNECTION_USER=/d' -e '/^IBMMQ_CONNECTION_PASSWORDFILE=/d' \
      /poc/collectors/ibm-mq/qm.env.example > /etc/mq_otel/$qm.env
  chown root:mqotel /etc/mq_otel/$qm.env
  chmod 640 /etc/mq_otel/$qm.env
done

echo "== docs/07 step 4: start one mq_otel per queue manager (no systemd: started directly with the unit's environment)"
for qm in QM1 QM2; do
  mkdir -p /var/lib/mq_otel/$qm && chown mqotel:mqotel /var/lib/mq_otel/$qm
  ( set -a; . /etc/mq_otel/$qm.env; set +a
    LD_LIBRARY_PATH=/opt/mqm/lib64 MQ_OVERRIDE_DATA_PATH=/var/lib/mq_otel/$qm \
      nohup runuser -u mqotel -- /opt/mq_otel/mq_otel -f=/etc/mq_otel/mq_otel.yaml > /var/log/mq_otel-$qm.log 2>&1 & )
done

echo "== orders, two a second, until the container stops"
while true; do
  curl -s -o /dev/null http://127.0.0.1:8080/orders-api/order
  sleep 0.5
done
