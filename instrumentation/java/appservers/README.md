# Where the JVM options go

Every app server needs the same three JVM options; only the place differs:

```
-javaagent:/opt/otel/opentelemetry-javaagent.jar
-Dotel.javaagent.configuration-file=/opt/otel/otel-agent.properties
-Dotel.javaagent.extensions=/opt/otel/extensions/appserver-deployment-extension.jar
```

| Server | Where | File here |
|---|---|---|
| Tomcat 9 / 10.1+ | `$CATALINA_BASE/bin/setenv.sh` (`CATALINA_OPTS`) | [tomcat-setenv.sh](tomcat-setenv.sh) |
| Tomcat as a systemd service | the unit's `Environment="CATALINA_OPTS=..."`, or `setenv.sh` if the unit calls `catalina.sh` | [tomcat-setenv.sh](tomcat-setenv.sh) |
| WildFly / JBoss EAP, standalone | `$JBOSS_HOME/bin/standalone.conf` (`JAVA_OPTS`) | [wildfly-standalone.conf](wildfly-standalone.conf) |
| WildFly / JBoss EAP, domain | the server group's `<jvm-options>` in `domain.xml` or `host.xml` | same options, one `<option value="..."/>` each |
| WebLogic | `$DOMAIN_HOME/bin/setUserOverrides.sh`: `JAVA_OPTIONS="$JAVA_OPTIONS ..."` (or the Server Start tab's Arguments in the console) | — |
| WebSphere Liberty | `${server.config.dir}/jvm.options`, one option per line | — |
| WebSphere traditional | Servers → Server Types → WebSphere application servers → server → Java and Process Management → Process definition → Java Virtual Machine → Generic JVM arguments | — |
| Spring Boot / plain jar | `java <options> -jar app.jar`, or `JAVA_TOOL_OPTIONS="<options>"` in the service unit | — |

**Values with `;`, `[`, `]` or `|`** (for example `otel.instrumentation.methods.include`) go in
`otel-agent.properties`, not on the command line: `catalina.sh` and `standalone.sh` evaluate
`CATALINA_OPTS` / `JAVA_OPTS` as shell code.

**The extension's coverage:** WARs on any Servlet 3.0+ container. EAR modules, EJB jars, timers
and MDBs are attributed on WildFly / JBoss EAP (verified on WildFly 27, Tomcat 10.1 and Tomcat 9).
On WebLogic and WebSphere, WARs are expected to work; EAR/EJB attribution needs a vendor resolver
that does not exist yet. See the extension's README, section 1.

**One host, several instances:** give each instance its own copy of `otel-agent.properties` with
its own `otel.service.name`, and point its `-Dotel.javaagent.configuration-file` at it.
