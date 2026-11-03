# 7. IBM MQ

For every queue manager, three Grafana dashboards show its status, its queues (depth, oldest
message) and dead-letter queue, and its channels. IyziTrace shows each queue manager as a broker
with the applications that use it.

```text
 QM1, QM2, ... ◄── user iyzmon, channel IYZI.MON.SVRCONN ── ibm-mq-metrics container ──► collector ──► IyziTrace
                                                            (one, on the collector's machine)   ▲
 WildFly + Java agent + IBM MQ extension ───────────────────────────────────────────────────────┘
```

Nothing is installed on the queue managers' hosts.

| Step | Who | Takes |
|---|---|---|
| [1. The monitoring user](#1-the-monitoring-user) | MQ administrator, on each queue manager | 10 min each |
| [2. The container](#2-the-container) | Linux administrator, on the collector's machine | 15 min |
| [3. The Java servers](#3-the-java-servers) | application server administrator | 5 min and a restart |
| [4. The dashboards](#4-the-dashboards) | Grafana administrator | 5 min |

You need a machine with Docker, usually the one with the collector of
[03-linux-collector.md](03-linux-collector.md), and it must reach every queue manager's port:
`timeout 3 bash -c '</dev/tcp/mq-host-01.example/1414' && echo open`.

## 1. The monitoring user

The container connects to every queue manager as one read-only MQ user. On each queue manager the
user needs:

| Object | Authorities | Why |
|---|---|---|
| the queue manager | connect, inquire, display | connect and read its status |
| every queue (`**`) | inquire, display | depth, oldest message, time on queue |
| every channel and client-connection channel (`**`) | display | channel status |
| `SYSTEM.ADMIN.COMMAND.QUEUE` | put, inquire, display | send DISPLAY commands |
| `SYSTEM.DEFAULT.MODEL.QUEUE` | get, inquire, display | receive their answers on a temporary queue |

The user cannot read, put or remove application messages, or change any object. The container
does not reset queue statistics or read the event queues, so other tools that use them are not
affected.

**The user.** If you already have a monitoring user for MQ, you can use it. Otherwise create
`iyzmon` on each queue manager's host, as root (with LDAP, create it there instead):

```bash
groupadd iyzmon
useradd -g iyzmon -s /sbin/nologin iyzmon
passwd iyzmon
```

**The authorities**, on each queue manager, as an MQ administrator. The file grants the table's
authorities to the group `iyzmon`:

```bash
curl -fLO https://raw.githubusercontent.com/iyzitrace/iyzitrace-poc/main/collectors/ibm-mq/monitor-authorities.mqsc
runmqsc QM1 < monitor-authorities.mqsc
```

For your own user, grant them to its group instead (IBM MQ on Linux grants authorities to groups;
if the queue manager grants them to users, `SecurityPolicy=user`, write `PRINCIPAL` for `GROUP`):

```bash
sed "s/GROUP('iyzmon')/GROUP('<your group>')/" monitor-authorities.mqsc | runmqsc QM1
```

Either way it ends with `6 MQSC commands read.` and only adds authorities: what the user already
has stays.

**The channel**, in `runmqsc QM1`, open only to the collector machine's IP address:

```text
DEFINE CHANNEL('IYZI.MON.SVRCONN') CHLTYPE(SVRCONN) TRPTYPE(TCP) DESCR('IyziTrace monitoring') REPLACE
SET CHLAUTH('IYZI.MON.SVRCONN') TYPE(ADDRESSMAP) ADDRESS('10.0.0.15') USERSRC(CHANNEL) CHCKCLNT(REQUIRED) DESCR('IyziTrace monitoring') ACTION(REPLACE)
```

If your own user already connects through a server-connection channel of its own, you can use that
channel instead: write its name in `channelName` in step 2.

If `DISPLAY QMGR MONQ` shows `MONQ(OFF)`, also `ALTER QMGR MONQ(MEDIUM)`: the oldest message needs it.

Repeat on every queue manager. With TLS channels, ask us.

## 2. The container

On the collector's machine, as root:

```bash
docker pull ghcr.io/antreklabs/ibm-mq-metrics:dev-c97d56dab294d8e2757d579fecd48ceedf68803a
mkdir -p /etc/ibm-mq-metrics
curl -fLo /etc/ibm-mq-metrics/config.yml https://raw.githubusercontent.com/iyzitrace/iyzitrace-poc/main/collectors/ibm-mq/config.yml
vi /etc/ibm-mq-metrics/config.yml
```

The file has one block per queue manager. Copy a block for each one and change its first four
lines:

```yaml
  - name: "QM1"
    host: "mq-host-01.example"
    port: 1414
    password: "<the user's password>"
```

With your own user, also change `username: "iyzmon"` in each block, and `channelName` if it uses
its own channel.

**Which collector.** The container sends to the collector on the same machine, with OTLP gRPC on
`127.0.0.1:4317`, which the collector of docs/03 already listens on. If your collector is elsewhere,
or takes OTLP only over HTTP, add its address to the `docker run` below, after `--network host`:

| Your collector | Add to `docker run` |
|---|---|
| this machine, `127.0.0.1:4317` (docs/03) | nothing |
| another machine or port, OTLP gRPC | `-e OTEL_EXPORTER_OTLP_ENDPOINT=http://<collector>:4317` |
| OTLP over HTTP | `-e OTEL_EXPORTER_OTLP_ENDPOINT=http://<collector>:4318 -e OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf` |

Then:

```bash
chown 65532 /etc/ibm-mq-metrics/config.yml
chmod 600 /etc/ibm-mq-metrics/config.yml
docker run -d --name ibm-mq-metrics --restart unless-stopped --network host \
  -v /etc/ibm-mq-metrics/config.yml:/etc/ibm-mq-metrics/config.yml:ro \
  ghcr.io/antreklabs/ibm-mq-metrics:dev-c97d56dab294d8e2757d579fecd48ceedf68803a
docker logs ibm-mq-metrics 2>&1 | grep "Active Channels"
```

**Check:** within a minute, one line `Active Channels in queueManager QM1 are [...]` per queue
manager.

Without internet on this machine: `docker pull` on one that has it, `docker save <image> -o
ibm-mq-metrics.tar`, copy the file over, `docker load -i ibm-mq-metrics.tar`.

## 3. The Java servers

On every Java server that uses IBM MQ, next to the agent of [04-java-agent.md](04-java-agent.md):

```bash
cd /opt/otel
curl -fLo extensions/ibm-mq-extension.jar https://github.com/antreklabs/iyzitrace-otel-java-extensions/releases/download/v0.2.0/ibm-mq-extension-0.2.0.jar
echo "7efa3024b25055174a138d9b76fb892efa3e6f9efbdddb656172864b6fad6fd8  extensions/ibm-mq-extension.jar" | sha256sum -c -
```

Restart the server the way you normally do. Without the extension, IyziTrace shows every queue
manager as one broker `jms`.

**Check:** IyziTrace shows one broker per queue manager, `jms://<host>:<port>`.

## 4. The dashboards

In Grafana, Dashboards, New, Import, once for each file:
[ibm-mq-overview.json](../grafana/dashboards/ibm-mq-overview.json),
[ibm-mq-queue-manager.json](../grafana/dashboards/ibm-mq-queue-manager.json),
[ibm-mq-queue.json](../grafana/dashboards/ibm-mq-queue.json).

Open **IBM MQ - Overview** and choose the department. A click on a queue manager or a queue opens
its own dashboard.

**Check:**

- every queue manager has a row, **Running**, and **Not reporting** is 0;
- a queue's depth and oldest message match `echo "DISPLAY QSTATUS(<QUEUE>) CURDEPTH MSGAGE" | runmqsc QM1`, give or take a minute;
- after `docker stop ibm-mq-metrics`, **Not reporting** counts every queue manager within 3 minutes;
  `docker start ibm-mq-metrics` brings them back.

## Later

| Task | What to do |
|---|---|
| Add or remove a queue manager | step 1 on it, its block in `config.yml`, `docker restart ibm-mq-metrics` |
| Change the password | in `config.yml`, `docker restart ibm-mq-metrics` |
| Upgrade | `docker pull` the new image, `docker rm -f ibm-mq-metrics`, `docker run` it as in step 2 |
| Remove everything | `docker rm -f ibm-mq-metrics` and `rm -r /etc/ibm-mq-metrics`; on each queue manager `runmqsc QM1 <` [remove-monitor-authorities.mqsc](../collectors/ibm-mq/remove-monitor-authorities.mqsc) (for your own user, with the `sed` of step 1), `userdel iyzmon`, `groupdel iyzmon`; on the Java servers `rm /opt/otel/extensions/ibm-mq-extension.jar` and a restart |

## Good to know

- A stopped or inactive channel is not reported: it drops out of the channel lists. A retrying
  channel shows.
- For a queue manager it cannot reach, the container keeps sending its last status;
  `ibm_mq_heartbeat` is 0 then, and the dashboards show it as **Not reporting**.
- `ibm_mq_oldest_msg_age_microseconds` holds seconds, despite its name.

## When something does not work

| What you see | What to do |
|---|---|
| reason `2035` when connecting, in `docker logs ibm-mq-metrics` | the channel rule, its IP address or the password |
| reason `2538` or `2059` | the host or port in `config.yml`, or a firewall |
| `AMQ8077W` or `AMQ8245W` for `iyzmon` in the queue manager's error log | an authority is missing: run `monitor-authorities.mqsc` again |
| `Permission denied` for `config.yml` | owner 65532 (step 2); with SELinux, `:ro,Z` instead of `:ro` |
| the log is fine but no data | the collector does not listen where the container sends (step 2, "Which collector"), or `--network host` is missing |
| oldest message always 0 | `ALTER QMGR MONQ(MEDIUM)` (step 1) |
| a queue is missing | it starts with `AMQ.` or a `SYSTEM.` prefix in `queueFilters` |
| one broker `jms` for all | the extension is not in `/opt/otel/extensions` (step 3) |
