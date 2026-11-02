# 7. IBM MQ queue managers

The health of the queue managers in IyziTrace: each queue manager's status, the depth and oldest
message of every queue, the dead-letter queue, and the state of the channels. IBM's own exporter,
**mq_otel** (from [mq-metric-samples](https://github.com/ibm-messaging/mq-metric-samples), v6.0.1,
Apache-2.0), reads them with a read-only user and sends them to the collector of
[03-linux-collector.md](03-linux-collector.md). One mq_otel runs per queue manager, all on the
collector's machine.

```text
 queue manager QM1 ──MQ client, user iyzmon, channel IYZI.MON.SVRCONN──► mq_otel@QM1 ─┐
 queue manager QM2 ──────────────────────────────────────────────────────► mq_otel@QM2 ─┼─► collector ──► IyziTrace
 ...                                                                                    ┘   127.0.0.1:4317
```

The applications that use IBM MQ through JMS are traced by the Java agent of
[04-java-agent.md](04-java-agent.md): their sends and receives appear as `send queue:///<QUEUE>` and
`process queue:///<QUEUE>` operations, and a message's trace continues in the application that reads
it. Step 6 adds the queue manager to those operations.

Step 1 is for the MQ administrators, on every queue manager. Steps 2 to 5 and 7 run as root on the
collector's machine (step 2 on any machine with Docker or Podman), step 6 on the Java servers.

## 1. A read-only user on each queue manager

On the queue manager's host, an operating-system group `iyzmon` and a user in it, with a password
(if your queue managers check passwords against LDAP, create the user there instead):

```bash
groupadd iyzmon
useradd -g iyzmon -s /sbin/nologin iyzmon
passwd iyzmon
```

The authorities: the group can connect, display and inquire, send DISPLAY commands and read the
queue manager's own metrics. It cannot read, put or remove any application message.

```bash
curl -fLO https://raw.githubusercontent.com/iyzitrace/iyzitrace-poc/main/collectors/ibm-mq/monitor-authorities.mqsc
runmqsc QM1 < monitor-authorities.mqsc
```

It ends with `7 MQSC commands read.` and `No commands have a syntax error.` Repeat
`runmqsc <QMNAME> < monitor-authorities.mqsc` for every queue manager on the host.

The channel mq_otel connects through, accepted only from the collector's machine and only with
`iyzmon`'s password. In `runmqsc QM1`, with the collector machine's IP address:

```text
DEFINE CHANNEL('IYZI.MON.SVRCONN') CHLTYPE(SVRCONN) TRPTYPE(TCP) DESCR('IyziTrace read-only monitoring') REPLACE
SET CHLAUTH('IYZI.MON.SVRCONN') TYPE(ADDRESSMAP) ADDRESS('10.0.0.15') USERSRC(CHANNEL) CHCKCLNT(REQUIRED) DESCR('IyziTrace monitoring') ACTION(REPLACE)
```

If your client channels use TLS, mq_otel needs a CCDT instead of an address; ask us.

The age of the oldest message and the time since the last get need queue monitoring.
`DISPLAY QMGR MONQ` must show `MEDIUM`, `LOW` or `HIGH`; if it shows `OFF`:

```text
ALTER QMGR MONQ(MEDIUM)
```

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

The program is `out/mq_otel`. Copy it to `/tmp/mq_otel` on the collector's machine.

## 3. The MQ client libraries and mq_otel

```bash
mkdir -p /opt/mqm
cd /opt/mqm
curl -fLO https://public.dhe.ibm.com/ibmdl/export/pub/software/websphere/messaging/mqdev/redist/10.0.1.0-IBM-MQC-Redist-LinuxX64.tar.gz
echo "f8f467d5e42001cc5cbe780b07d971fd2b0850de321753c4814ceced5248915e  10.0.1.0-IBM-MQC-Redist-LinuxX64.tar.gz" | sha256sum -c -
tar -xzf 10.0.1.0-IBM-MQC-Redist-LinuxX64.tar.gz
rm 10.0.1.0-IBM-MQC-Redist-LinuxX64.tar.gz
```

This is IBM's redistributable MQ client; it connects to queue managers of any supported version.

```bash
useradd -r -m -d /var/lib/mq_otel -s /sbin/nologin mqotel
install -D -m 0755 /tmp/mq_otel /opt/mq_otel/mq_otel
mkdir -p /etc/mq_otel
curl -fLo /etc/mq_otel/mq_otel.yaml https://raw.githubusercontent.com/iyzitrace/iyzitrace-poc/main/collectors/ibm-mq/mq_otel.yaml
curl -fLo /etc/systemd/system/mq_otel@.service https://raw.githubusercontent.com/iyzitrace/iyzitrace-poc/main/collectors/ibm-mq/mq_otel@.service
```

Without internet, copy the files from this repository's `collectors/ibm-mq/` folder to the same
places.

`mq_otel.yaml` is the same for every queue manager. It monitors every queue except temporary ones
(`AMQ.*`) and the queue manager's own `SYSTEM.*` queues, but with the dead-letter queue
`SYSTEM.DEAD.LETTER.QUEUE`. If your dead-letter queue has another name that starts with `SYSTEM.`,
check that none of the `"!SYSTEM...` lines there matches it.

## 4. One settings file per queue manager

For each queue manager, a file named after it. For `QM1`:

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

Keep the quotes around the address in `CONNNAME`. `METADATAVALUES` is the queue manager's host
and port as the applications name them in their own connection (step 6); IyziTrace links the
queue manager's metrics to the messages the applications send there only when the two are equal. Then `iyzmon`'s password, alone on the first line of its file:

```bash
install -m 0600 -o mqotel -g mqotel /dev/null /etc/mq_otel/QM1.pw
vi /etc/mq_otel/QM1.pw
chown root:mqotel /etc/mq_otel/QM1.env
chmod 640 /etc/mq_otel/QM1.env
```

## 5. Start

```bash
systemctl daemon-reload
systemctl enable --now mq_otel@QM1
journalctl -u mq_otel@QM1 -n 20 --no-pager
```

The log shows `Connected to queue manager  QM1`. Repeat steps 4 and 5 for every queue manager,
writing its name for `QM1`.

The collector needs no change when it uses this repository's `config.yaml` (step 3 of
[03-linux-collector.md](03-linux-collector.md)). If your collector has its own configuration, its
`metrics` pipeline needs the two processors this repository's file has there:

- `delta_to_cumulative`: mq_otel reports its counters as the change since its last report, and
  IyziTrace keeps only running totals. Without it the put and get counts never arrive.
- `groupbyattrs/ibmmq`: it moves the queue manager's address (step 4) to where IyziTrace reads it.

## 6. The applications: which queue manager each message goes to

The Java agent's JMS spans name the queue but not the queue manager. The IBM MQ extension adds the
queue manager's host and port, so IyziTrace shows each queue manager as its own broker, with its
queues, and links it to the metrics of steps 1 to 5. On every Java server that uses IBM MQ, next to
the agent of [04-java-agent.md](04-java-agent.md):

```bash
cd /opt/otel
curl -fLo extensions/ibm-mq-extension.jar https://github.com/antreklabs/iyzitrace-otel-java-extensions/releases/download/v0.2.0/ibm-mq-extension-0.2.0.jar
echo "7efa3024b25055174a138d9b76fb892efa3e6f9efbdddb656172864b6fad6fd8  extensions/ibm-mq-extension.jar" | sha256sum -c -
```

The agent loads it from the extensions folder (step 3 of [04-java-agent.md](04-java-agent.md)).
Restart the server. The applications need no change.

Without it, IyziTrace shows all queue managers as one broker named `jms`, and a queue with the same
name on two queue managers as one queue.

## 7. The dashboard

In Grafana: Dashboards, New, Import, then upload
[grafana/dashboards/ibm-mq.json](../grafana/dashboards/ibm-mq.json) and press Import. At the top,
choose the department in **Department**.

| Part | Shows |
|---|---|
| Queue managers | status, command server, channel initiator, connections, puts and gets per second, messages on the dead-letter queue, free space, FDC files; a queue manager that stopped sending shows as **Not reporting** |
| Queues | depth, how full, oldest message, time since the last get, puts and gets per second, readers; deepest first |
| Dead-letter queues | messages on the dead-letter queue of each queue manager; set its name in **Dead-letter queue** if it is not `SYSTEM.DEAD.LETTER.QUEUE` |
| Channels | the state of the channels between queue managers, and the client connections per channel |

The first values appear one to two minutes after mq_otel starts.

## When something does not work

| What you see | What to do |
|---|---|
| `MQRC_NOT_AUTHORIZED [2035]` in the mq_otel log | the channel rule or the password: check `IYZI.MON.SVRCONN`'s `CHLAUTH` rule, the address in it and `/etc/mq_otel/<QMNAME>.pw`; the queue manager's error log names the refused user |
| `MQRC_HOST_NOT_AVAILABLE [2538]` or `[2059]` | the address or port in `IBMMQ_CONNECTION_CONNNAME`, or a firewall between the machines |
| `Directory '/home/mqotel/.mqm' could not be created` | `mqotel` was created without its home: `usermod -d /var/lib/mq_otel mqotel`, then `mkdir -p /var/lib/mq_otel && chown mqotel:mqotel /var/lib/mq_otel` |
| `AMQ8077W` or `AMQ8245W` for `iyzmon` in the queue manager's error log | an authority is missing: run `monitor-authorities.mqsc` again on that queue manager |
| Depths are shown but no puts or gets | the collector has no `delta_to_cumulative` (step 5) |
| A queue is missing | it starts with `SYSTEM.` or `AMQ.`, or it was created less than an hour ago (mq_otel looks for new queues once an hour) |
| Oldest message is always 0 | queue monitoring is off: `ALTER QMGR MONQ(MEDIUM)` (step 1) |
| All queue managers show as one broker `jms` | the IBM MQ extension is not loaded on the Java server (step 6): `ls /opt/otel/extensions`, and the agent option must name the folder |
| A queue manager shows as broker `jms://<host>:<port>` but not as monitored | `IBMMQ_CONNECTION_METADATAVALUES` (step 4) is not the host and port the applications use, or the collector lacks `groupbyattrs/ibmmq` (step 5) |
