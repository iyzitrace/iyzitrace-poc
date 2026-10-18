# 3. Collector on each Linux host

One collector per host that runs Java app servers. It receives OTLP from the Java agents on the
same host (127.0.0.1:4317/4318), adds host metrics, and sends everything to IyziTrace through the
gateway with the department's **agent key**. It also registers with Agent Manager.

Config: [collector/config.yaml](../collector/config.yaml). Values per site and host:
[collector/otelcol-contrib.conf.example](../collector/otelcol-contrib.conf.example).

## 3.1 Copy the kit to the host

```bash
scp -r iyzitrace-poc/collectors/linux-host  user@host:/tmp/iyzitrace-collector
ssh user@host
```

## 3.2 Install

With internet on the host (downloads the RPM/DEB from GitHub and checks its SHA-256):

```bash
sudo sh /tmp/iyzitrace-collector/install.sh \
  --ingest-url https://GATEWAY/ingest \
  --api-key 'AGENT-KEY' \
  --host-name "$(hostname -s)" \
  --group java-hosts
```

Without internet: download `otelcol-contrib_0.159.0_linux_amd64.rpm` (or `.deb`, or `arm64`) from
https://github.com/open-telemetry/opentelemetry-collector-releases/releases/tag/v0.159.0 elsewhere,
copy it to the host, and add `--package /path/to/otelcol-contrib_0.159.0_linux_amd64.rpm`.

What it does:

1. Installs `otelcol-contrib` 0.159.0 (systemd service `otelcol-contrib`, user `otelcol-contrib`).
2. Puts `config.yaml` in `/etc/otelcol-contrib/`.
3. Writes `/etc/otelcol-contrib/otelcol-contrib.conf` (mode 0640) with the URL, the key, the host
   name and the group. The key is never printed.
4. Validates the config with those values, then enables and restarts the service and calls the
   health check.

Re-running it updates `config.yaml` and keeps the environment file, unless `--ingest-url` and
`--api-key` are given again.

Expected end of the output:

```
config is valid
● otelcol-contrib.service - OpenTelemetry Collector Contrib
     Active: active (running) ...
health check: OK
```

## 3.3 Check

```bash
systemctl status otelcol-contrib --no-pager
curl -s http://127.0.0.1:13133/ ; echo        # {"status":"Server available", ...}
journalctl -u otelcol-contrib -n 50 --no-pager
```

A warning `failed to get host ID` is harmless (no `/etc/machine-id`).

In IyziTrace (Grafana):

- **Agent Manager → Agents**: `otelcol-<hostname>` in group `java-hosts`, Online. Its drawer shows
  Metrics and Logs within a minute.
- **Atlas / Horizon**: the host with CPU and memory (from the host metrics) after a minute or two.

## 3.4 Options

| Need | Change |
|---|---|
| The gateway's certificate is from a private CA | copy the CA to `/etc/otelcol-contrib/iyzitrace-ca.pem`, uncomment the two `tls: ca_file:` blocks in `config.yaml`, re-run `install.sh` |
| Outbound traffic through a proxy | `HTTPS_PROXY=` / `NO_PROXY=` in `otelcol-contrib.conf`, then `systemctl restart otelcol-contrib` |
| App servers on other machines send to this collector | `endpoint: 0.0.0.0:4317` / `0.0.0.0:4318` in `config.yaml`, open the ports for those machines only, point their agents at `http://<this-host>:4318` |
| Process metrics of the Java processes (CPU, memory per JVM) | run the collector as root: `systemctl edit otelcol-contrib` → `[Service]` `User=root`; as `otelcol-contrib` it can only read its own process |
| One `service.name` per server instead of per application | remove `groupbyattrs/deployment` and `transform/deployment-as-service` from the `traces` and `logs` pipelines |
