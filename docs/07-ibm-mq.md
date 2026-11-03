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

The container connects to every queue manager as one MQ user. On each queue manager that user needs
these authorities, and no more:

| Object | Authorities | Why |
|---|---|---|
| the queue manager | connect, inquire, display | connect and read its status |
| every queue (`**`) | inquire, display | depth, oldest message, time on queue |
| every channel (`**`) | display | channel status |
| every client-connection channel (`**`) | display | channel status |
| `SYSTEM.ADMIN.COMMAND.QUEUE` | put, inquire, display | send DISPLAY commands |
| `SYSTEM.DEFAULT.MODEL.QUEUE` | get, inquire, display | receive their answers on a temporary queue |

With them the user cannot read, put or remove application messages, or change any object.

Do you already have a monitoring user for MQ? Follow **A**. If not, follow **B**.

### A. You have a monitoring user

On each queue manager, as an MQ administrator:

1. Give the user's group the authorities. In `runmqsc QM1`, with your group's name in place of
   `<group>`:

   ```text
   SET AUTHREC OBJTYPE(QMGR) GROUP('<group>') AUTHADD(CONNECT, INQ, DSP)
   SET AUTHREC PROFILE('SYSTEM.ADMIN.COMMAND.QUEUE') OBJTYPE(QUEUE) GROUP('<group>') AUTHADD(PUT, INQ, DSP)
   SET AUTHREC PROFILE('SYSTEM.DEFAULT.MODEL.QUEUE') OBJTYPE(QUEUE) GROUP('<group>') AUTHADD(GET, INQ, DSP)
   SET AUTHREC PROFILE('**') OBJTYPE(QUEUE) GROUP('<group>') AUTHADD(INQ, DSP)
   SET AUTHREC PROFILE('**') OBJTYPE(CHANNEL) GROUP('<group>') AUTHADD(DSP)
   SET AUTHREC PROFILE('**') OBJTYPE(CLNTCONN) GROUP('<group>') AUTHADD(DSP)
   ```

   These only add authorities; what the user already has stays. If your queue managers grant
   authorities to users, not groups (`SecurityPolicy=user` in `qm.ini`), write
   `PRINCIPAL('<user>')` instead of `GROUP('<group>')`.

2. The channel. If the user already connects through a server-connection channel of its own, keep
   it. Otherwise create one, open only to the collector machine's IP address (in `runmqsc QM1`):

   ```text
   DEFINE CHANNEL('IYZI.MON.SVRCONN') CHLTYPE(SVRCONN) TRPTYPE(TCP) DESCR('IyziTrace monitoring') REPLACE
   SET CHLAUTH('IYZI.MON.SVRCONN') TYPE(ADDRESSMAP) ADDRESS('10.0.0.15') USERSRC(CHANNEL) CHCKCLNT(REQUIRED) DESCR('IyziTrace monitoring') ACTION(REPLACE)
   ```

3. Note the user's name, its password and the channel's name: step 2 needs them.

### B. You have no monitoring user

1. On each queue manager's host, as root, create the group and the user `iyzmon` (with LDAP,
   create them there instead):

   ```bash
   groupadd iyzmon
   useradd -g iyzmon -s /sbin/nologin iyzmon
   passwd iyzmon
   ```

2. On each queue manager, as an MQ administrator, give `iyzmon` the authorities.
   [monitor-authorities.mqsc](../collectors/ibm-mq/monitor-authorities.mqsc) holds the six
   commands of A.1 for the group `iyzmon`:

   ```bash
   curl -fLO https://raw.githubusercontent.com/iyzitrace/iyzitrace-poc/main/collectors/ibm-mq/monitor-authorities.mqsc
   runmqsc QM1 < monitor-authorities.mqsc
   ```

   It ends with `6 MQSC commands read.`

3. Create the channel, open only to the collector machine's IP address (in `runmqsc QM1`):

   ```text
   DEFINE CHANNEL('IYZI.MON.SVRCONN') CHLTYPE(SVRCONN) TRPTYPE(TCP) DESCR('IyziTrace monitoring') REPLACE
   SET CHLAUTH('IYZI.MON.SVRCONN') TYPE(ADDRESSMAP) ADDRESS('10.0.0.15') USERSRC(CHANNEL) CHCKCLNT(REQUIRED) DESCR('IyziTrace monitoring') ACTION(REPLACE)
   ```

### Then, in both cases

- If `echo "DISPLAY QMGR MONQ" | runmqsc QM1` shows `MONQ(OFF)`, run `ALTER QMGR MONQ(MEDIUM)`:
  the oldest message needs it.
- **Check:** `echo "DISPLAY AUTHREC GROUP('<group>')" | runmqsc QM1` (`iyzmon` in B) lists the
  profiles of the table: `SYSTEM.ADMIN.COMMAND.QUEUE`, `SYSTEM.DEFAULT.MODEL.QUEUE` and `**`.
- Repeat on every queue manager. With TLS channels, ask us.

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

In A, also change `username` (the user's name) and `channelName` (if it keeps its own channel) in
each block.

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
| Remove everything | see [Removing everything](#removing-everything) |

## Removing everything

On the collector's machine:

```bash
docker rm -f ibm-mq-metrics
rm -r /etc/ibm-mq-metrics
```

On the Java servers: `rm /opt/otel/extensions/ibm-mq-extension.jar`, then restart them.

On each queue manager, as an MQ administrator:

- **A (your own user).** The user stays yours. To take back what A.1 added, in `runmqsc QM1`
  (authorities the user had before step 1 go too):

  ```text
  SET AUTHREC OBJTYPE(QMGR) GROUP('<group>') AUTHRMV(CONNECT, INQ, DSP)
  SET AUTHREC PROFILE('SYSTEM.ADMIN.COMMAND.QUEUE') OBJTYPE(QUEUE) GROUP('<group>') AUTHRMV(PUT, INQ, DSP)
  SET AUTHREC PROFILE('SYSTEM.DEFAULT.MODEL.QUEUE') OBJTYPE(QUEUE) GROUP('<group>') AUTHRMV(GET, INQ, DSP)
  SET AUTHREC PROFILE('**') OBJTYPE(QUEUE) GROUP('<group>') AUTHRMV(INQ, DSP)
  SET AUTHREC PROFILE('**') OBJTYPE(CHANNEL) GROUP('<group>') AUTHRMV(DSP)
  SET AUTHREC PROFILE('**') OBJTYPE(CLNTCONN) GROUP('<group>') AUTHRMV(DSP)
  ```

  If you created `IYZI.MON.SVRCONN` in A.2, also:

  ```text
  SET CHLAUTH('IYZI.MON.SVRCONN') TYPE(ADDRESSMAP) ACTION(REMOVEALL)
  STOP CHANNEL('IYZI.MON.SVRCONN') MODE(FORCE) STATUS(INACTIVE)
  DELETE CHANNEL('IYZI.MON.SVRCONN')
  ```

- **B (`iyzmon`).** The authorities and the channel, then the user on the host as root:

  ```bash
  curl -fLO https://raw.githubusercontent.com/iyzitrace/iyzitrace-poc/main/collectors/ibm-mq/remove-monitor-authorities.mqsc
  runmqsc QM1 < remove-monitor-authorities.mqsc
  userdel iyzmon
  groupdel iyzmon
  ```

In Grafana, delete the three IBM MQ dashboards.

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
