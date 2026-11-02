# 7. IBM MQ

What the customer gets, for every queue manager:

- on three dashboards in Grafana: its status, the depth of its queues, the oldest message on each
  queue, the dead-letter queue and the channels between queue managers;
- in IyziTrace, its own broker, with the applications that send to it and read from it.

How the data flows:

```text
 queue manager QM1 ─┐
 queue manager QM2 ─┼── MQ client, read-only user iyzmon ──► IBM MQ metrics container ──► collector ──► IyziTrace
 ...                ┘    channel IYZI.MON.SVRCONN            (one, for every queue        127.0.0.1:4317
                                                              manager)                         ▲
 WildFly + Java agent + IBM MQ extension (JMS spans with the queue manager's host and port) ───┘
```

The container runs OpenTelemetry's
[ibm-mq-metrics](https://github.com/open-telemetry/opentelemetry-java-contrib/tree/main/ibm-mq-metrics)
1.61.0 (Apache-2.0) with IBM's MQ Java client. It runs on the collector's machine of
[03-linux-collector.md](03-linux-collector.md) and reads one file that lists every queue manager.
Nothing is installed on the queue managers' hosts.

| Step | Who | Where | Takes |
|---|---|---|---|
| [1. Read-only user](#1-a-read-only-user-on-each-queue-manager) | MQ administrator | each queue manager | 10 min per queue manager |
| [2. The container](#2-the-container-on-the-collectors-machine) | Linux administrator | the collector's machine | 15 min, then 1 min per queue manager |
| [3. Java servers](#3-the-ibm-mq-extension-on-the-java-servers) | application server administrator | each Java server that uses IBM MQ | 5 min and a restart |
| [4. Dashboards](#4-the-dashboards) | Grafana administrator | Grafana | 5 min |
| [5. Acceptance](#5-acceptance) | IyziTrace and the customer | Grafana, IyziTrace | 15 min |

## Before you start

| Check | How | Expected |
|---|---|---|
| The collector runs | `systemctl is-active otelcol-contrib` | `active` ([03-linux-collector.md](03-linux-collector.md)) |
| Docker runs on the same machine | `docker version` | a version |
| That machine reaches every queue manager's listener | `timeout 3 bash -c '</dev/tcp/mq-host-01.example/1414' && echo open`, once per queue manager | `open` |
| Queue monitoring is on (oldest message, time on queue) | `echo "DISPLAY QMGR MONQ" \| runmqsc QM1` | `MONQ(MEDIUM)`, `LOW` or `HIGH` |

## 1. A read-only user on each queue manager

On the queue manager's host, as root: an operating-system group `iyzmon` and a user in it, with a
password. If the queue managers check passwords against LDAP, create the user there instead.

```bash
groupadd iyzmon
useradd -g iyzmon -s /sbin/nologin iyzmon
passwd iyzmon
```

As an MQ administrator, the authorities. The group can connect, display and inquire, and send
DISPLAY commands. It cannot read, put or remove any application message.

```bash
curl -fLO https://raw.githubusercontent.com/iyzitrace/iyzitrace-poc/main/collectors/ibm-mq/monitor-authorities.mqsc
runmqsc QM1 < monitor-authorities.mqsc
```

It ends with `6 MQSC commands read.` and `No commands have a syntax error.`

The user must stay read-only. Besides DISPLAY commands, the container also asks to reset queue
statistics and reads the queue manager's event queues (`SYSTEM.ADMIN.*.EVENT`), which removes the
events it reads. With these authorities the queue manager refuses both: no statistics are reset,
no events are removed. An existing monitoring user can be used instead only if it has neither `chg`
on queues nor `get` on the event queues:

```bash
dspmqaut -m QM1 -n SYSTEM.ADMIN.QMGR.EVENT -t queue -p <user>
dspmqaut -m QM1 -n <an application queue> -t queue -p <user>
```

Neither may list `get` or `chg`.

The channel the container connects through. It accepts only the collector's machine, and only with
`iyzmon`'s password. In `runmqsc QM1`, with the collector machine's IP address:

```text
DEFINE CHANNEL('IYZI.MON.SVRCONN') CHLTYPE(SVRCONN) TRPTYPE(TCP) DESCR('IyziTrace read-only monitoring') REPLACE
SET CHLAUTH('IYZI.MON.SVRCONN') TYPE(ADDRESSMAP) ADDRESS('10.0.0.15') USERSRC(CHANNEL) CHCKCLNT(REQUIRED) DESCR('IyziTrace monitoring') ACTION(REPLACE)
```

If your client channels use TLS, ask us.

If `DISPLAY QMGR MONQ` showed `OFF`:

```text
ALTER QMGR MONQ(MEDIUM)
```

**Check:** `echo "DISPLAY AUTHREC GROUP('iyzmon')" | runmqsc QM1` lists the profiles
`SYSTEM.ADMIN.COMMAND.QUEUE`, `SYSTEM.DEFAULT.MODEL.QUEUE` and `**` (queue, channel and clntconn).

Repeat for every queue manager.

## 2. The container on the collector's machine

As root.

**The image:**

```bash
docker pull ghcr.io/antreklabs/ibm-mq-metrics:dev-c1139e5f2ae5e7164ffef09dba8d16c8ce5b8f94
```

Without internet on this machine, pull it on one that has it, then
`docker save ghcr.io/antreklabs/ibm-mq-metrics:dev-c1139e5f2ae5e7164ffef09dba8d16c8ce5b8f94 -o ibm-mq-metrics.tar`, copy the file over and
`docker load -i ibm-mq-metrics.tar`.

**The file**, one for every queue manager:

```bash
mkdir -p /etc/ibm-mq-metrics
curl -fLo /etc/ibm-mq-metrics/config.yml https://raw.githubusercontent.com/iyzitrace/iyzitrace-poc/main/collectors/ibm-mq/config.yml
vi /etc/ibm-mq-metrics/config.yml
chown 65532 /etc/ibm-mq-metrics/config.yml
chmod 600 /etc/ibm-mq-metrics/config.yml
```

It has one block per queue manager under `queueManagers`. Copy a block for each one and change its
first four lines:

```yaml
  - name: "QM1"
    host: "mq-host-01.example"
    port: 1414
    password: "<iyzmon's password>"
```

The file holds passwords, so only the container's user (65532) can read it.

If the dead-letter queue has another name that starts with `SYSTEM.`, check that none of the
`SYSTEM.` prefixes in `queueFilters` matches it.

**Start it:**

```bash
docker run -d --name ibm-mq-metrics --restart unless-stopped --network host \
  -v /etc/ibm-mq-metrics/config.yml:/etc/ibm-mq-metrics/config.yml:ro \
  ghcr.io/antreklabs/ibm-mq-metrics:dev-c1139e5f2ae5e7164ffef09dba8d16c8ce5b8f94
docker logs ibm-mq-metrics 2>&1 | grep "Active Channels"
```

**Check:** within a minute, one line `Active Channels in queueManager QM1 are [...]` per queue
manager. Lines with reason `2035` for `MQCMD_RESET_Q_STATS` and for `SYSTEM.ADMIN.*.EVENT` are
expected: that is the queue manager refusing what the read-only user may not do.

**The collector.** Nothing to change when it uses this repository's `config.yaml` (step 3 of
[03-linux-collector.md](03-linux-collector.md)). If it has its own configuration, it needs an OTLP
gRPC receiver on `127.0.0.1:4317` in a `metrics` pipeline that exports to IyziTrace. For a
collector on another address, add `-e OTEL_EXPORTER_OTLP_ENDPOINT=http://<host>:4317` to
`docker run`.

## 3. The IBM MQ extension on the Java servers

The Java agent's JMS spans name the queue but not the queue manager, so IyziTrace shows every queue
manager as one broker `jms`. The extension adds the queue manager's host and port. On every Java
server that uses IBM MQ, next to the agent of [04-java-agent.md](04-java-agent.md):

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

## 4. The dashboards

In Grafana, for each of the three files: Dashboards, New, Import, upload the file, Import.

| File | Shows |
|---|---|
| [ibm-mq-overview.json](../grafana/dashboards/ibm-mq-overview.json) | every queue manager: what needs attention now (not running, not reporting, channels not running, dead letters, queues over 80% full, messages older than 5 minutes), one row per queue manager, status history, deepest queues, oldest messages, channels |
| [ibm-mq-queue-manager.json](../grafana/dashboards/ibm-mq-queue-manager.json) | one queue manager: its queues and channels |
| [ibm-mq-queue.json](../grafana/dashboards/ibm-mq-queue.json) | one queue: depth, oldest message, time on queue, readers and writers |

Start at **IBM MQ - Overview** and choose the department at the top. A click on a queue manager or a
queue opens its own dashboard. If the dead-letter queue is not `SYSTEM.DEAD.LETTER.QUEUE`, write its
name in **Dead-letter queue**.

## 5. Acceptance

| Check | Where | Expected |
|---|---|---|
| Every queue manager reports | IBM MQ - Overview | one row per queue manager in the table, all **Running**; **Not reporting** 0 |
| Depths are right | a queue manager's dashboard, and `echo "DISPLAY QLOCAL(<QUEUE>) CURDEPTH" \| runmqsc QM1` | the same depth, give or take a minute |
| Dead letters are right | IBM MQ - Overview, **Dead letters** column; `echo "DISPLAY QLOCAL(SYSTEM.DEAD.LETTER.QUEUE) CURDEPTH" \| runmqsc QM1` | the same number |
| Oldest messages are right | a queue manager's dashboard; `echo "DISPLAY QSTATUS(<QUEUE>) MSGAGE" \| runmqsc QM1` | the same age in seconds, give or take a minute |
| An outage shows | `docker stop ibm-mq-metrics` | within 3 minutes **Not reporting** shows every queue manager; `docker start ibm-mq-metrics` turns it back |
| The applications' messages reach their queue manager | IyziTrace | one broker `jms://<host>:<port>` per queue manager, with its queues |

## Day-2 operations

| Task | What to do |
|---|---|
| Add a queue manager | step 1 on it, a block for it in `/etc/ibm-mq-metrics/config.yml`, then `docker restart ibm-mq-metrics` |
| Remove a queue manager | remove its block, then `docker restart ibm-mq-metrics` |
| Change `iyzmon`'s password | change it in the file, then `docker restart ibm-mq-metrics` |
| New queues | nothing: every queue is read again each minute |
| Upgrade | `docker pull` the new image, then `docker rm -f ibm-mq-metrics` and `docker run` with it as in step 2 |
| See what it does | `docker logs -f ibm-mq-metrics` |

## Removing everything

On the Java servers: `rm /opt/otel/extensions/ibm-mq-extension.jar`, then restart them.

On the collector's machine:

```bash
docker rm -f ibm-mq-metrics
docker rmi ghcr.io/antreklabs/ibm-mq-metrics:dev-c1139e5f2ae5e7164ffef09dba8d16c8ce5b8f94
rm -r /etc/ibm-mq-metrics
```

On each queue manager, as an MQ administrator, then on its host as root:

```bash
curl -fLO https://raw.githubusercontent.com/iyzitrace/iyzitrace-poc/main/collectors/ibm-mq/remove-monitor-authorities.mqsc
runmqsc QM1 < remove-monitor-authorities.mqsc
userdel iyzmon
groupdel iyzmon
```

In Grafana, delete the three IBM MQ dashboards.

## Known limits

These come from ibm-mq-metrics 1.61.0; the dashboards take them into account.

- A channel that is stopped or inactive is not reported. It drops out of the channel lists instead
  of showing as stopped. A channel that is retrying or binding shows.
- `ibm_mq_oldest_msg_age_microseconds` holds seconds, despite its name.
- For a queue manager it cannot reach, the container keeps sending the last status it read.
  `ibm_mq_heartbeat` is 0 then, and the dashboards show such a queue manager as **Not reporting**.
- There are no put and get counts: the tool reads them by resetting the queue statistics, which the
  read-only user refuses.

## When something does not work

| What you see | What to do |
|---|---|
| `Error connecting to QueueManager QM1` with reason `2035` in the container's log | the channel rule or the password: check `IYZI.MON.SVRCONN`'s `CHLAUTH` rule, the address in it and the password in the file; the queue manager's error log names the refused user |
| reason `2538` or `2059` | the host or port in the file, or a firewall between the machines |
| `AMQ8077W` or `AMQ8245W` for `iyzmon` in the queue manager's error log | an authority is missing: run `monitor-authorities.mqsc` again on that queue manager |
| `Permission denied` for `config.yml` | the file's owner must be 65532 (step 2); with SELinux enforcing, write `:ro,Z` instead of `:ro` in `docker run` |
| The log is fine but nothing arrives in IyziTrace | the collector does not listen on `127.0.0.1:4317`, or the container was started without `--network host` |
| Oldest message is always 0 | queue monitoring is off: `ALTER QMGR MONQ(MEDIUM)` (step 1) |
| A queue is missing | it starts with `AMQ.` or with one of the `SYSTEM.` prefixes in `queueFilters` |
| All queue managers show as one broker `jms` | the IBM MQ extension is not loaded on the Java server (step 3): `ls /opt/otel/extensions`, and the agent option must name the folder |
