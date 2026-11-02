# 7. IBM MQ runbook

What the customer gets, for every queue manager:

- its health in Grafana: status, queue depths, the oldest message on each queue, the dead-letter
  queue and the channels between queue managers, on three dashboards;
- in IyziTrace, each queue manager as its own broker, linked to the applications that send to it
  and read from it.

How the data flows:

```text
 queue manager QM1 ──MQ client, user iyzmon, channel IYZI.MON.SVRCONN──► mq_otel@QM1 ─┐
 queue manager QM2 ──────────────────────────────────────────────────────► mq_otel@QM2 ─┼─► collector ──► IyziTrace
 ...                                                                                    ┘   127.0.0.1:4317
 WildFly + Java agent + IBM MQ extension (JMS spans with the queue manager's host:port) ────► collector
```

**mq_otel** is IBM's exporter, from
[mq-metric-samples](https://github.com/ibm-messaging/mq-metric-samples) v6.0.1 (Apache-2.0). One
mq_otel runs per queue manager, all of them on the collector's machine of
[03-linux-collector.md](03-linux-collector.md). It connects as a client with a read-only user, so
nothing is installed on the queue managers' hosts.

| Phase | Who | Where | Takes |
|---|---|---|---|
| [0. Before you start](#0-before-you-start) | IyziTrace + customer | — | one meeting |
| [1. Read-only user](#1-a-read-only-user-on-each-queue-manager) | MQ administrator | each queue manager | 10 min per queue manager |
| [2. Build mq_otel](#2-build-mq_otel-once) | IyziTrace | any machine with Docker or Podman | 15 min, once |
| [3. mq_otel](#3-mq_otel-on-the-collectors-machine) | Linux administrator | the collector's machine | 30 min, then 2 min per queue manager |
| [4. Java servers](#4-the-ibm-mq-extension-on-the-java-servers) | application server administrator | each Java server that uses IBM MQ | 5 min and a restart |
| [5. Dashboards](#5-the-dashboards) | Grafana administrator | Grafana | 5 min |
| [6. Acceptance](#6-acceptance) | IyziTrace + customer | Grafana, IyziTrace | 15 min |

## 0. Before you start

| Check | How | Expected |
|---|---|---|
| The collector runs on the machine that will host mq_otel | `systemctl is-active otelcol-contrib` | `active` ([03-linux-collector.md](03-linux-collector.md)) |
| That machine reaches every queue manager's listener | `timeout 3 bash -c '</dev/tcp/mq-host-01.example/1414' && echo open`, once per queue manager | `open` |
| The Java servers run the agent | `grep "opentelemetry-javaagent - version" $JBOSS_HOME/standalone/log/server.log` | a version line ([04-java-agent.md](04-java-agent.md)) |
| The MQ team agrees to a read-only user and a channel per queue manager | phase 1 shows exactly what they add | yes |
| Queue monitoring is on (oldest message, last get) | `echo "DISPLAY QMGR MONQ" \| runmqsc QM1` | `MONQ(MEDIUM)`, `LOW` or `HIGH` |
| A machine with Docker or Podman and internet, for phase 2 | `docker version` | a version |

Then fill in one row per queue manager. Every later phase reads its values from here.

| Queue manager | Host | Port | Host and port as the applications name them | Phase 1 | Phase 3 | Running |
|---|---|---|---|---|---|---|
| QM1 | mq-host-01.example | 1414 | mq-host-01.example:1414 | | | |

The fourth column is what the applications put in their own connection to the queue manager. It
can differ from the host mq_otel uses (an alias, a load balancer). IyziTrace links a queue
manager's metrics to the applications' messages only when the two are equal.

## 1. A read-only user on each queue manager

On the queue manager's host, as root: an operating-system group `iyzmon` and a user in it, with a
password. If the queue managers check passwords against LDAP, create the user there instead.

```bash
groupadd iyzmon
useradd -g iyzmon -s /sbin/nologin iyzmon
passwd iyzmon
```

As an MQ administrator, the authorities. The group can connect, display and inquire, send DISPLAY
commands and read the queue manager's own metrics. It cannot read, put or remove any application
message.

```bash
curl -fLO https://raw.githubusercontent.com/iyzitrace/iyzitrace-poc/main/collectors/ibm-mq/monitor-authorities.mqsc
runmqsc QM1 < monitor-authorities.mqsc
```

It ends with `7 MQSC commands read.` and `No commands have a syntax error.`

The channel mq_otel connects through. It accepts only the collector's machine, and only with
`iyzmon`'s password. In `runmqsc QM1`, with the collector machine's IP address:

```text
DEFINE CHANNEL('IYZI.MON.SVRCONN') CHLTYPE(SVRCONN) TRPTYPE(TCP) DESCR('IyziTrace read-only monitoring') REPLACE
SET CHLAUTH('IYZI.MON.SVRCONN') TYPE(ADDRESSMAP) ADDRESS('10.0.0.15') USERSRC(CHANNEL) CHCKCLNT(REQUIRED) DESCR('IyziTrace monitoring') ACTION(REPLACE)
```

If your client channels use TLS, mq_otel needs a CCDT instead of an address; ask us.

If `DISPLAY QMGR MONQ` showed `OFF` in phase 0:

```text
ALTER QMGR MONQ(MEDIUM)
```

**Check:** `echo "DISPLAY AUTHREC GROUP('iyzmon')" | runmqsc QM1` lists the profiles
`SYSTEM.ADMIN.COMMAND.QUEUE`, `SYSTEM.DEFAULT.MODEL.QUEUE`, `**` (queue, channel and clntconn) and
`SYSTEM.ADMIN.TOPIC`.

Repeat for every queue manager, and tick **Phase 1** in the table.

## 2. Build mq_otel (once)

IBM publishes mq_otel as source only. Build it once, on any Linux or macOS machine with Docker and
internet access (with Podman, write `podman` for `docker`):

```bash
git clone --depth 1 --branch v6.0.1 https://github.com/ibm-messaging/mq-metric-samples.git
cd mq-metric-samples
docker build --platform linux/amd64 -f Dockerfile.build -t mq-metric-samples-gobuild:6.0.1 .
mkdir -p out
docker run --rm --platform linux/amd64 -e MONITORS=mq_otel -v "$PWD/out:/go/out" mq-metric-samples-gobuild:6.0.1
```

**Check:** `file out/mq_otel` says `ELF 64-bit LSB executable, x86-64`. Copy it to `/tmp/mq_otel` on
the collector's machine.

## 3. mq_otel on the collector's machine

As root.

**The MQ client libraries**, in mq_otel's own folder, so that an IBM MQ already installed on the
machine (in `/opt/mqm`) is not touched. This is IBM's redistributable MQ client; it connects to queue
managers of any supported version.

```bash
mkdir -p /opt/mq_otel/mqclient
cd /opt/mq_otel/mqclient
curl -fLO https://public.dhe.ibm.com/ibmdl/export/pub/software/websphere/messaging/mqdev/redist/10.0.1.0-IBM-MQC-Redist-LinuxX64.tar.gz
echo "f8f467d5e42001cc5cbe780b07d971fd2b0850de321753c4814ceced5248915e  10.0.1.0-IBM-MQC-Redist-LinuxX64.tar.gz" | sha256sum -c -
tar -xzf 10.0.1.0-IBM-MQC-Redist-LinuxX64.tar.gz
rm 10.0.1.0-IBM-MQC-Redist-LinuxX64.tar.gz
```

**mq_otel, its user, its settings and its service:**

```bash
useradd -r -m -d /var/lib/mq_otel -s /sbin/nologin mqotel
install -D -m 0755 /tmp/mq_otel /opt/mq_otel/mq_otel
mkdir -p /etc/mq_otel
curl -fLo /etc/mq_otel/mq_otel.yaml https://raw.githubusercontent.com/iyzitrace/iyzitrace-poc/main/collectors/ibm-mq/mq_otel.yaml
curl -fLo /etc/systemd/system/mq_otel@.service https://raw.githubusercontent.com/iyzitrace/iyzitrace-poc/main/collectors/ibm-mq/mq_otel@.service
systemctl daemon-reload
```

Without internet, copy the files from this repository's `collectors/ibm-mq/` folder to the same
places.

`mq_otel.yaml` is the same for every queue manager. It monitors every queue except temporary ones
(`AMQ.*`) and the queue manager's own `SYSTEM.*` queues, but with the dead-letter queue
`SYSTEM.DEAD.LETTER.QUEUE`. If your dead-letter queue has another name that starts with `SYSTEM.`,
check that none of the `"!SYSTEM...` lines there matches it.

**The collector.** Nothing to change when it uses this repository's `config.yaml` (step 3 of
[03-linux-collector.md](03-linux-collector.md)). If it has its own configuration, its `metrics`
pipeline needs the two processors this repository's file has there:

- `delta_to_cumulative`: mq_otel reports its counters as the change since its last report, and
  IyziTrace keeps only running totals. Without it the put and get counts never arrive.
- `groupbyattrs/ibmmq`: it moves the queue manager's address (the table's fourth column) to where
  IyziTrace reads it.

**For each queue manager**, with the values of its row in the table. For `QM1`:

```bash
curl -fLo /etc/mq_otel/QM1.env https://raw.githubusercontent.com/iyzitrace/iyzitrace-poc/main/collectors/ibm-mq/qm.env.example
vi /etc/mq_otel/QM1.env
```

Change these lines:

```text
IBMMQ_CONNECTION_QUEUEMANAGER=QM1
IBMMQ_CONNECTION_CONNNAME='mq-host-01.example(1414)'
IBMMQ_CONNECTION_PASSWORDFILE=/etc/mq_otel/QM1.pw
IBMMQ_CONNECTION_METADATAVALUES=mq-host-01.example:1414
```

Keep the quotes around the address in `CONNNAME`. `METADATAVALUES` is the table's fourth column.
Then `iyzmon`'s password, alone on the first line of its file, and the service:

```bash
install -m 0600 -o mqotel -g mqotel /dev/null /etc/mq_otel/QM1.pw
vi /etc/mq_otel/QM1.pw
chown root:mqotel /etc/mq_otel/QM1.env
chmod 640 /etc/mq_otel/QM1.env
systemctl enable --now mq_otel@QM1
journalctl -u mq_otel@QM1 -n 20 --no-pager
```

**Check:** the log shows `Connected to queue manager  QM1`, and the queue manager's error log has
no `AMQ8077W` or `AMQ8245W` for `iyzmon`. Tick **Phase 3**.

## 4. The IBM MQ extension on the Java servers

The Java agent's JMS spans name the queue but not the queue manager. The extension adds the queue
manager's host and port. On every Java server that uses IBM MQ, next to the agent of
[04-java-agent.md](04-java-agent.md):

```bash
cd /opt/otel
curl -fLo extensions/ibm-mq-extension.jar https://github.com/antreklabs/iyzitrace-otel-java-extensions/releases/download/v0.2.0/ibm-mq-extension-0.2.0.jar
echo "7efa3024b25055174a138d9b76fb892efa3e6f9efbdddb656172864b6fad6fd8  extensions/ibm-mq-extension.jar" | sha256sum -c -
```

The agent loads it from the extensions folder (step 3 of [04-java-agent.md](04-java-agent.md)).
Restart the server the way you normally do. The applications need no change.

**Check:** after a few messages, IyziTrace shows the applications' `send queue:///<QUEUE>` and
`process queue:///<QUEUE>` operations, and one broker per queue manager, named
`jms://<host>:<port>`, instead of a single broker `jms`.

## 5. The dashboards

In Grafana, for each of the three files: Dashboards, New, Import, upload the file, Import.

| File | Shows |
|---|---|
| [ibm-mq-overview.json](../grafana/dashboards/ibm-mq-overview.json) | every queue manager: what needs attention now (not running, not reporting, channels down, dead letters, queues over 80% full, messages older than 5 minutes), one row per queue manager, status history, deepest queues, oldest messages, channels |
| [ibm-mq-queue-manager.json](../grafana/dashboards/ibm-mq-queue-manager.json) | one queue manager: workload, failed calls, CPU, memory, disk, recovery log, its queues and channels |
| [ibm-mq-queue.json](../grafana/dashboards/ibm-mq-queue.json) | one queue: depth, oldest message, time on queue, puts and gets, bytes, expired and rolled back |

Start at **IBM MQ - Overview** and choose the department at the top. A click on a queue manager or a
queue opens its own dashboard. If the dead-letter queue is not `SYSTEM.DEAD.LETTER.QUEUE`, write its
name in **Dead-letter queue**.

## 6. Acceptance

| Check | Where | Expected |
|---|---|---|
| Every queue manager reports | IBM MQ - Overview | one row per queue manager in the table, all **Running**; **Not reporting** 0 |
| Depths are right | a queue manager's dashboard, and `echo "DISPLAY QLOCAL(<QUEUE>) CURDEPTH" \| runmqsc QM1` | the same depth, give or take a minute |
| Dead letters are right | IBM MQ - Overview, **Dead letters** column; `echo "DISPLAY QLOCAL(SYSTEM.DEAD.LETTER.QUEUE) CURDEPTH" \| runmqsc QM1` | the same number |
| Puts and gets arrive | a queue manager's dashboard, **Messages put and got** | lines above 0 while the applications work |
| An outage shows | stop one queue manager's mq_otel: `systemctl stop mq_otel@QM1` | within 2 minutes **Not reporting** 1 and QM1 red in **Status history**; `systemctl start mq_otel@QM1` turns it back |
| The applications' messages reach their queue manager | IyziTrace | one broker `jms://<host>:<port>` per queue manager, with its queues |

## Day-2 operations

| Task | Commands |
|---|---|
| Add a queue manager | phase 1 on it, then phase 3 "For each queue manager" with its name |
| Remove a queue manager | `systemctl disable --now mq_otel@QM1`, then `rm /etc/mq_otel/QM1.env /etc/mq_otel/QM1.pw` |
| Change `iyzmon`'s password | write it into `/etc/mq_otel/QM1.pw`, then `systemctl restart mq_otel@QM1` |
| New queues | nothing: mq_otel finds queues created since its start within an hour |
| Upgrade mq_otel | phase 2 with the new version, `install -m 0755 /tmp/mq_otel /opt/mq_otel/mq_otel`, then `systemctl restart 'mq_otel@*'` |
| See what mq_otel does | `journalctl -u mq_otel@QM1 -f` |

## Removing everything

On the Java servers: `rm /opt/otel/extensions/ibm-mq-extension.jar`, then restart them.

On the collector's machine:

```bash
systemctl disable --now 'mq_otel@*'
rm -r /etc/mq_otel /opt/mq_otel /etc/systemd/system/mq_otel@.service
systemctl daemon-reload
userdel -r mqotel
```

On each queue manager, as an MQ administrator, then on its host as root:

```bash
curl -fLO https://raw.githubusercontent.com/iyzitrace/iyzitrace-poc/main/collectors/ibm-mq/remove-monitor-authorities.mqsc
runmqsc QM1 < remove-monitor-authorities.mqsc
userdel iyzmon
groupdel iyzmon
```

In Grafana, delete the three IBM MQ dashboards.

## When something does not work

| What you see | What to do |
|---|---|
| `MQRC_NOT_AUTHORIZED [2035]` in the mq_otel log | the channel rule or the password: check `IYZI.MON.SVRCONN`'s `CHLAUTH` rule, the address in it and `/etc/mq_otel/<QMNAME>.pw`; the queue manager's error log names the refused user |
| `MQRC_HOST_NOT_AVAILABLE [2538]` or `[2059]` | the address or port in `IBMMQ_CONNECTION_CONNNAME`, or a firewall between the machines |
| `Directory '/home/mqotel/.mqm' could not be created` | `mqotel` was created without its home: `usermod -d /var/lib/mq_otel mqotel`, then `mkdir -p /var/lib/mq_otel && chown mqotel:mqotel /var/lib/mq_otel` |
| `AMQ8077W` or `AMQ8245W` for `iyzmon` in the queue manager's error log | an authority is missing: run `monitor-authorities.mqsc` again on that queue manager |
| Depths are shown but no puts or gets | the collector has no `delta_to_cumulative` (phase 3) |
| A queue is missing | it starts with `SYSTEM.` or `AMQ.`, or it was created less than an hour ago |
| Oldest message is always 0 | queue monitoring is off: `ALTER QMGR MONQ(MEDIUM)` (phase 1) |
| All queue managers show as one broker `jms` | the IBM MQ extension is not loaded on the Java server (phase 4): `ls /opt/otel/extensions`, and the agent option must name the folder |
| A queue manager shows as broker `jms://<host>:<port>` but not linked to its metrics | `IBMMQ_CONNECTION_METADATAVALUES` is not the host and port the applications use, or the collector lacks `groupbyattrs/ibmmq` (phase 3) |
