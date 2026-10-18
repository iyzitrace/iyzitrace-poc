# 4. Java agent and the appserver-deployment extension

Each Java app server gets:

- the **OpenTelemetry Java agent** 2.21.0: automatic traces (HTTP, JDBC, JMS, outgoing calls...),
  JVM and HTTP metrics, and logs;
- the **iyzitrace appserver-deployment extension** 0.1.0
  ([antreklabs/iyzitrace-otel-java-extensions](https://github.com/antreklabs/iyzitrace-otel-java-extensions)).
  When several applications run in one server, it tags every span and log record with the
  application it came from. With this kit's collector config, each application becomes its own
  service in IyziTrace.

The agent sends to the collector on the same host (`http://127.0.0.1:4318`); the collector
forwards to IyziTrace. No application is rebuilt or redeployed; the server is restarted once.

Requirements: Java 11 or later; the collector of step 3 running on the host.

## 4.1 Download the agent and the extension

On the host (or on a machine with internet, then copy `/opt/otel` to the host):

```bash
sudo sh iyzitrace-poc/instrumentation/java/download.sh /opt/otel
```

Result, with both SHA-256 checksums verified:

```
/opt/otel/opentelemetry-javaagent.jar                       2.21.0
/opt/otel/extensions/appserver-deployment-extension.jar     0.1.0
/opt/otel/otel-agent.properties                             the settings, edit next
```

The app server's user must be able to read `/opt/otel` (the script makes it world-readable).

## 4.2 Settings: `/opt/otel/otel-agent.properties`

Edit the two identity lines; leave the rest as is.

```properties
otel.service.name=CHANGE-ME-server-name
otel.resource.attributes=service.namespace=CHANGE-ME-namespace,deployment.environment.name=poc
```

| Key | Example | Meaning in IyziTrace |
|---|---|---|
| `otel.service.name` | `tomcat-orders-01` | the server's name: used for JVM metrics, server-wide logs, and as the fallback for work outside any application |
| `service.namespace` | `orders` | the application landscape the server belongs to; groups services in Atlas and Horizon. Use the same value for all servers of one landscape |
| `deployment.environment.name` | `poc` | separates environments |

One host with several server instances: one copy of the file per instance, each with its own
`otel.service.name`, each instance pointing at its own copy.

## 4.3 JVM options

Every server gets the same three options:

```
-javaagent:/opt/otel/opentelemetry-javaagent.jar
-Dotel.javaagent.configuration-file=/opt/otel/otel-agent.properties
-Dotel.javaagent.extensions=/opt/otel/extensions/appserver-deployment-extension.jar
```

Where they go depends on the server: [instrumentation/java/appservers/README.md](../instrumentation/java/appservers/README.md).
The two most common:

**Tomcat 9 / 10.1+:**

```bash
sudo cp iyzitrace-poc/instrumentation/java/appservers/tomcat-setenv.sh $CATALINA_BASE/bin/setenv.sh
# (if setenv.sh already exists, append the file's lines to it instead)
```

**WildFly / JBoss EAP (standalone):** append
[wildfly-standalone.conf](../instrumentation/java/appservers/wildfly-standalone.conf) to
`$JBOSS_HOME/bin/standalone.conf`.

## 4.4 Restart the server and check the agent started

```bash
# Tomcat
grep "opentelemetry-javaagent - version" $CATALINA_BASE/logs/catalina.out
# WildFly
grep "opentelemetry-javaagent - version" $JBOSS_HOME/standalone/log/server.log   # or the console output
```

Expected: `... VersionLogger - opentelemetry-javaagent - version: 2.21.0`. Errors from the agent are
logged with `[otel.javaagent ...]` and `WARN`/`ERROR`.

Send a few requests to each application, then go to [05-verify.md](05-verify.md).

## Service names: what you will see

The collector turns the extension's attributes into one service per application. For traces and
logs, `service.name` is the first that exists of:

1. the name the application declares, in `META-INF/microprofile-config.properties`:
   `otel.service.name=order-service`;
2. the context root without the slash: `/orders` → `orders`;
3. the deployment name: `orders.war`, `shop.ear`. This applies to timers, MDBs, startup work and
   the root context `/`.

Otherwise `otel.service.name` from the properties file stays.

`service.namespace`, first that exists:

1. the declared namespace (`otel.resource.attributes=service.namespace=commerce` in the same file);
2. the server's `service.namespace` from the properties file;
3. the server's `otel.service.name`.

JVM and HTTP **metrics** stay per server (`otel.service.name`): the agent cannot tag metrics per
application. IyziTrace's latency and call figures per application come from the traces, so they are
per application anyway.

Example from the rehearsal: one Tomcat with `otel.service.name=tomcat-poc-01` and
`service.namespace=poc-shop`, running the bundled `examples`, `docs` and `ROOT` web applications.
In IyziTrace it shows as the services `poc-shop/examples`, `poc-shop/docs` and `poc-shop/ROOT`, plus
the JVM metrics of `tomcat-poc-01`.

To keep one service per server instead, see "Options" in [03-linux-collector.md](03-linux-collector.md#34-options).

## Coverage of the extension

| Server | WARs | EAR modules, EJB jars, timers, MDBs |
|---|---|---|
| WildFly 27 / JBoss EAP | ✅ | ✅ (verified on WildFly 27) |
| Tomcat 10.1, Tomcat 9 | ✅ (verified) | n/a |
| WebLogic, WebSphere / Liberty, Jetty, Payara | ✅ expected (generic core) | ❌ not yet (needs a vendor resolver) |

Background work right after start-up is attributed only after the application's first request
(generic core). On WildFly / JBoss it is attributed from the start.

## Optional

| Need | Setting in `otel-agent.properties` |
|---|---|
| Spans for chosen business methods, no code change | `otel.instrumentation.methods.include=com.example.OrderService[place,cancel]` |
| Less data under heavy load | `otel.traces.sampler=parentbased_traceidratio` and `otel.traces.sampler.arg=0.1` |
| Turn the extension off without removing it | `otel.instrumentation.appserver-deployment.enabled=false` |
| Turn the agent off for one restart | remove the `-javaagent` option |
