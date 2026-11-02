# syntax=docker/dockerfile:1
# IBM MQ metrics for IyziTrace: OpenTelemetry's ibm-mq-metrics (opentelemetry-java-contrib, Apache-2.0)
# with IBM's MQ Java client. One container for every queue manager. It reads one file,
# /etc/ibm-mq-metrics/config.yml, and sends OTLP to the collector on 127.0.0.1:4317
# (docs/07-ibm-mq.md).
FROM eclipse-temurin:21-jre@sha256:0b99b3376fbb50dbf9c0af8535fdd5b8eb0d3fdfc8b1e4967f383b6919f6901a

WORKDIR /opt/ibm-mq-metrics
ADD --chmod=644 --checksum=sha256:8a2aa79021d85a08771d779e064590b422dbea65ace6e099ca9eabeb4857020a \
    https://repo1.maven.org/maven2/io/opentelemetry/contrib/opentelemetry-ibm-mq-metrics/1.61.0-alpha/opentelemetry-ibm-mq-metrics-1.61.0-alpha-all.jar \
    ibm-mq-metrics.jar
ADD --chmod=644 --checksum=sha256:da3ad7f3f6e781d7df3e6d892f4c3476f0c5b7d4e4b6f2e043480bcc41ae01b6 \
    https://repo1.maven.org/maven2/com/ibm/mq/com.ibm.mq.allclient/10.0.0.5/com.ibm.mq.allclient-10.0.0.5.jar \
    com.ibm.mq.allclient.jar

# Metrics only. Another collector address: docker run -e OTEL_EXPORTER_OTLP_ENDPOINT=http://<host>:4317
ENV OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4317 \
    OTEL_EXPORTER_OTLP_PROTOCOL=grpc \
    OTEL_TRACES_EXPORTER=none \
    OTEL_LOGS_EXPORTER=none

USER 65532
ENTRYPOINT ["java", "-cp", "/opt/ibm-mq-metrics/*", "io.opentelemetry.ibm.mq.opentelemetry.Main", "/etc/ibm-mq-metrics/config.yml"]
