# A stand-in for a customer's Linux host: Rocky Linux 9 (RHEL-compatible), Java 17 and Tomcat 10.1
# with its bundled applications (ROOT, docs, examples), so the collector install and the Java agent
# setup of this repository run exactly as they would on the host.
FROM rockylinux:9
RUN dnf -y install java-17-openjdk-headless procps-ng tar gzip findutils hostname && dnf clean all
ARG TOMCAT_VERSION=10.1.34
RUN curl -fsSL -o /tmp/tomcat.tgz https://archive.apache.org/dist/tomcat/tomcat-10/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz \
 && curl -fsSL https://archive.apache.org/dist/tomcat/tomcat-10/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz.sha512 | awk '{print $1"  /tmp/tomcat.tgz"}' | sha512sum -c - \
 && mkdir -p /opt/tomcat && tar -xzf /tmp/tomcat.tgz -C /opt/tomcat --strip-components=1 && rm /tmp/tomcat.tgz
COPY . /poc
CMD ["sh", "/poc/test/linux-java-host/host-run.sh"]
