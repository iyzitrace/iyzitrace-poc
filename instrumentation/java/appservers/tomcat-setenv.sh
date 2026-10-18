# Tomcat: $CATALINA_BASE/bin/setenv.sh (create it if missing; catalina.sh sources it on start).
# If setenv.sh already exists, append these lines to it.
# Tomcat 9 (javax) and 10.1+ (jakarta) both work; Java 11 or later is required.

OTEL_HOME=/opt/otel
CATALINA_OPTS="$CATALINA_OPTS -javaagent:$OTEL_HOME/opentelemetry-javaagent.jar"
CATALINA_OPTS="$CATALINA_OPTS -Dotel.javaagent.configuration-file=$OTEL_HOME/otel-agent.properties"
CATALINA_OPTS="$CATALINA_OPTS -Dotel.javaagent.extensions=$OTEL_HOME/extensions/appserver-deployment-extension.jar"
export CATALINA_OPTS
