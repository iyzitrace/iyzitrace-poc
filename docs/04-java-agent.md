# 4. Java agent on each Java server

Two files are added to every Java server:

- the **OpenTelemetry Java agent** (version 2.21.0). It records traces automatically: incoming HTTP
  requests, database calls, messaging, outgoing calls. It also records JVM and HTTP metrics and the
  server's logs.
- the **iyzitrace appserver-deployment extension** (version 0.1.0). When one server runs several
  applications, it marks every trace and log line with the application it came from. IyziTrace then
  shows each application as its own service.

The agent sends its data to the collector installed in step 3, on the same machine. The
applications are not rebuilt or redeployed; the server is restarted once.

You need Java 11 or later, and the collector from step 3 running on the machine.

## 1. Download the agent and the extension

```bash
mkdir -p /opt/otel/extensions
cd /opt/otel

curl -fLo opentelemetry-javaagent.jar https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.21.0/opentelemetry-javaagent.jar
echo "5b35ccc6c275fd477a06db01923813e13d99c1a52a20b0ea8ed6576eae177c7d  opentelemetry-javaagent.jar" | sha256sum -c -

curl -fLo extensions/appserver-deployment-extension.jar https://github.com/antreklabs/iyzitrace-otel-java-extensions/releases/download/v0.1.0/appserver-deployment-extension-0.1.0.jar
echo "c7d81bf27569db099b19a859e5f8cd4f47f6eab7b6fd0a9661d5ef7033a83d9c  extensions/appserver-deployment-extension.jar" | sha256sum -c -
```

Both `sha256sum` lines must print `OK`.

Without internet on the machine, download the two files on another computer, check them the same
way, and copy them to `/opt/otel/` and `/opt/otel/extensions/`.

## 2. Add the agent's settings file

```bash
curl -fLo /opt/otel/otel-agent.properties https://raw.githubusercontent.com/iyzitrace/iyzitrace-poc/main/instrumentation/java/otel-agent.properties
chmod -R a+rX /opt/otel
```

The `chmod` lets the user the server runs as (for example `tomcat` or `jboss`) read the files.

Open `/opt/otel/otel-agent.properties` and change the two lines at the top:

```properties
otel.service.name=tomcat-orders-01
otel.resource.attributes=service.namespace=orders,deployment.environment.name=poc
```

- `otel.service.name`: a name for this server, for example `tomcat-orders-01`. JVM metrics and the
  server's own logs appear under this name.
- `service.namespace`: the name of the application landscape this server belongs to, for example
  `orders`. IyziTrace groups services by it. Use the same value on all servers of one landscape.

Leave the rest of the file as it is. It sends everything to the collector on `127.0.0.1:4318`.

If one machine runs several server instances, give each its own copy of the file (for example
`/opt/otel/otel-agent-orders.properties`) with its own `otel.service.name`.

## 3. Load the agent when the server starts

Every server needs the same three JVM options. Only where you put them differs.

```text
-javaagent:/opt/otel/opentelemetry-javaagent.jar
-Dotel.javaagent.configuration-file=/opt/otel/otel-agent.properties
-Dotel.javaagent.extensions=/opt/otel/extensions/appserver-deployment-extension.jar
```

**Tomcat 9 or 10.1:** create `$CATALINA_BASE/bin/setenv.sh` with this content. If the file already
exists, add these lines at the end.

```bash
CATALINA_OPTS="$CATALINA_OPTS -javaagent:/opt/otel/opentelemetry-javaagent.jar"
CATALINA_OPTS="$CATALINA_OPTS -Dotel.javaagent.configuration-file=/opt/otel/otel-agent.properties"
CATALINA_OPTS="$CATALINA_OPTS -Dotel.javaagent.extensions=/opt/otel/extensions/appserver-deployment-extension.jar"
export CATALINA_OPTS
```

If Tomcat runs as a systemd service that does not use `catalina.sh`, put the three options in the
unit's `Environment="CATALINA_OPTS=..."` line instead.

**WildFly or JBoss EAP, standalone:** add these lines at the end of `$JBOSS_HOME/bin/standalone.conf`.

```bash
JAVA_OPTS="$JAVA_OPTS -javaagent:/opt/otel/opentelemetry-javaagent.jar"
JAVA_OPTS="$JAVA_OPTS -Dotel.javaagent.configuration-file=/opt/otel/otel-agent.properties"
JAVA_OPTS="$JAVA_OPTS -Dotel.javaagent.extensions=/opt/otel/extensions/appserver-deployment-extension.jar"
```

In domain mode, add the three options as `<option value="..."/>` lines to the server group's
`<jvm-options>` in `domain.xml` or `host.xml`.

**Other servers:**

| Server | Where the three options go |
|---|---|
| WebLogic | `$DOMAIN_HOME/bin/setUserOverrides.sh`: `JAVA_OPTIONS="$JAVA_OPTIONS <options>"`, or the server's Server Start → Arguments in the console |
| WebSphere Liberty | `jvm.options` in the server's folder, one option per line |
| WebSphere traditional | Servers → Server Types → WebSphere application servers → your server → Java and Process Management → Process definition → Java Virtual Machine → Generic JVM arguments |
| Spring Boot or a plain jar | `java <options> -jar app.jar`, or `JAVA_TOOL_OPTIONS="<options>"` in the service unit |

Put settings that contain `;`, `[`, `]` or `|` in `otel-agent.properties`, not on the command line.
The start scripts of Tomcat and WildFly treat those characters as shell syntax.

## 4. Restart the server and check that the agent started

Restart the server the way you normally do. Then look for the agent's start line in the server log:

```bash
grep "opentelemetry-javaagent - version" $CATALINA_BASE/logs/catalina.out          # Tomcat
grep "opentelemetry-javaagent - version" $JBOSS_HOME/standalone/log/server.log      # WildFly
```

You should see `... opentelemetry-javaagent - version: 2.21.0`. The agent's own warnings and errors
start with `[otel.javaagent`.

Open a few pages of each application, then continue with [05-verify.md](05-verify.md).

## Service names

With the extension and this repository's collector configuration, each application becomes its own
service. Its name is the first of these that exists:

1. a name the application declares in `META-INF/microprofile-config.properties`, for example
   `otel.service.name=order-service`;
2. the application's context root without the slash: `/orders` becomes `orders`;
3. the deployment name, for example `orders.war`. This one is used for timers, message-driven beans,
   start-up work and the root context `/`.

If none exists, the server's `otel.service.name` is used.

The namespace is the one the application declares, or else the server's `service.namespace`.

JVM and HTTP metrics stay per server, under the server's `otel.service.name`; the agent cannot split
metrics by application. Request counts and latency per application come from the traces, so those
are per application anyway.

Example from the rehearsal: one Tomcat with `otel.service.name=tomcat-poc-01` and
`service.namespace=poc-shop` ran three applications. IyziTrace showed the services
`poc-shop/examples`, `poc-shop/docs` and `poc-shop/ROOT`, and the JVM metrics under
`tomcat-poc-01`.

To get one service per server instead, see the end of [03-linux-collector.md](03-linux-collector.md).

## What the extension covers

| Server | Web applications (WAR) | EAR modules, EJBs, timers, message-driven beans |
|---|---|---|
| WildFly 27, JBoss EAP | yes | yes (tested on WildFly 27) |
| Tomcat 10.1, Tomcat 9 | yes (tested) | not applicable |
| WebLogic, WebSphere, Liberty, Jetty, Payara | expected to work | not yet |

On Tomcat, background work right after start-up is attributed to its application only after that
application has served its first request. On WildFly and JBoss it is attributed from the start.

## Optional settings (in `otel-agent.properties`)

| You want | Add this line |
|---|---|
| Traces for chosen business methods, without code changes | `otel.instrumentation.methods.include=com.example.OrderService[place,cancel]` |
| Less data under heavy load (10% of traces) | `otel.traces.sampler=parentbased_traceidratio` and `otel.traces.sampler.arg=0.1` |
| The extension off, without removing it | `otel.instrumentation.appserver-deployment.enabled=false` |

To remove the agent, delete the three options and restart the server.
