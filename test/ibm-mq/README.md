# Test: IBM MQ queue managers and a WildFly machine

This is how [docs/07-ibm-mq.md](../../docs/07-ibm-mq.md) was tested. It is for us, not for the
customer.

| Container | Stands in for |
|---|---|
| `qm1`, `qm2` | two of the customer's queue managers: IBM MQ Advanced for Developers 9.4.5.1, with the read-only authorities of [collectors/ibm-mq/monitor-authorities.mqsc](../../collectors/ibm-mq/monitor-authorities.mqsc) and the monitoring channel `IYZI.MON.SVRCONN` |
| `host` (`poc-mq-01`) | the customer's Linux machine: Rocky Linux 8.10, Java 21, WildFly 41, the collector (docs/03), the Java agent (docs/04) with the IBM MQ extension (docs/07 step 3), set up by [host-run.sh](host-run.sh) with the commands of those pages |
| `ibm-mq-metrics` | the IBM MQ metrics container of docs/07 step 2, `ghcr.io/antreklabs/ibm-mq-metrics:dev-c1139e5f2ae5e7164ffef09dba8d16c8ce5b8f94`, with [ibm-mq-metrics.yml](ibm-mq-metrics.yml) (the repository's `config.yml` with the lab's values) and the Linux machine's network, as `docker run --network host` gives it there |

The two applications on WildFly carry the IBM MQ JMS client (`com.ibm.mq.jakarta.client` 9.4.1.0)
inside their WARs, as the customer's services do:

```text
 orders-api      GET /orders-api/order --> QM1 ORDER.REQUEST
 orders-worker   QM1 ORDER.REQUEST --> QM1 PAYMENT.REMOTE --channel QM1.TO.QM2--> QM2 PAYMENT.REQUEST
                                       (every 25th order: QM1 SYSTEM.DEAD.LETTER.QUEUE)
                 QM2 PAYMENT.REQUEST --> QM2 BILLING.REQUEST
                 QM2 BILLING.REQUEST is read only in even minutes: its depth and oldest message rise and fall
```

[mq/90-lab.mqsc](mq/90-lab.mqsc) defines the queues on both queue managers;
[mq/qm1-channels.mqsc](mq/qm1-channels.mqsc) and [mq/qm2-channels.mqsc](mq/qm2-channels.mqsc) the
sender and receiver channel between them.

Differences from a customer's installation, all on the queue manager side:

- The monitoring channel maps every connection to `iyzmon` without a password: the developer image
  checks passwords only for its own users `app` and `admin`. The authorities are the customer's,
  unchanged.
- The queue managers run IBM MQ 9.4; the customer's run 9.2. The MQSC commands used exist in both.
- The images exist for amd64 only; on an arm64 computer Docker runs them emulated, which is slower.

## Run it

You need Docker, a running IyziTrace that containers can reach, and a department's agent key.
From this folder:

1. Passwords for the queue managers' users `app` and `admin`, and the IyziTrace values:

   ```bash
   mkdir -p secrets
   openssl rand -hex 12 > secrets/mqAppPassword
   openssl rand -hex 12 > secrets/mqAdminPassword
   printf 'IYZITRACE_INGEST_URL=http://host.docker.internal/ingest\nIYZITRACE_API_KEY=<agent-key>\n' > .env
   ```

   Put the department's agent key in place of `<agent-key>` in `.env`. If IyziTrace does not run on
   this computer behind port 80, write its address in `IYZITRACE_INGEST_URL`.

2. Start it. By starting the queue managers (`LICENSE=accept`) you accept the IBM MQ Advanced for
   Developers licence, for development and testing only; `docker run --rm --platform linux/amd64 -e
   LICENSE=view icr.io/ibm-messaging/mq:9.4.5.1-r1` prints it.

   ```bash
   docker compose up -d --build
   docker compose logs -f host
   ```

After three to five minutes IyziTrace shows:

- in Services, the applications (namespace `poc-orders`) with their `send queue:///...` and
  `process queue:///...` operations, and on Service Map the edge from `orders-api` to the worker;
- the brokers `jms://qm1:1414` and `jms://qm2:1414`, each with its own queues;
- the dashboards of [grafana/dashboards](../../grafana/dashboards), imported as docs/07 step 4 says,
  with `QM1` and `QM2` Running, the channel `QM1.TO.QM2` Running on both ends,
  the depth and oldest message of `BILLING.REQUEST` on `QM2` rising and falling, and the
  dead-letter queue of `QM1` growing by one message every 25 orders;
- in Agent Manager, `otelcol-poc-mq-01` (group `mq-hosts`).

Remove it with `docker compose down -v`.
