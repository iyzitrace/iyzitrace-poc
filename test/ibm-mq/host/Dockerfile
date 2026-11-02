# The two lab applications, built with the IBM MQ JMS client inside each WAR.
FROM maven:3.9.11-eclipse-temurin-21 AS apps
COPY test/ibm-mq/apps /apps
RUN cd /apps && mvn -q -B package

# A stand-in for the customer's Linux machine: Rocky Linux 8.10 (RHEL 8.10-compatible), Java 21 and
# WildFly 41 with the two applications, so the collector and the Java agent are set up exactly as
# docs/03 and docs/04 say.
FROM rockylinux/rockylinux:8.10
RUN dnf -y install java-21-openjdk-headless procps-ng tar gzip findutils hostname && dnf clean all
ARG WILDFLY_VERSION=41.0.1.Final
RUN curl -fsSL -o /tmp/wildfly.tgz https://github.com/wildfly/wildfly/releases/download/${WILDFLY_VERSION}/wildfly-${WILDFLY_VERSION}.tar.gz \
 && echo "26e27908f5c720d53f24abb95f9575d04f580510e5d85fad513cda9ade8119c3  /tmp/wildfly.tgz" | sha256sum -c - \
 && mkdir -p /opt/wildfly && tar -xzf /tmp/wildfly.tgz -C /opt/wildfly --strip-components=1 && rm /tmp/wildfly.tgz
COPY --from=apps /apps/orders-api/target/orders-api.war /apps/orders-worker/target/orders-worker.war /opt/wildfly/standalone/deployments/
COPY . /poc
CMD ["sh", "/poc/test/ibm-mq/host-run.sh"]
