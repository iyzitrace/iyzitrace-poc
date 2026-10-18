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

Two ways, same result. **A** runs the steps of **B** for you; use B to do it by hand or to see
exactly what changes on the host.

### A) With the script

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

### B) By hand, step by step

Run as root (or prefix each command with `sudo`). The examples are for x86_64; on aarch64 replace
`amd64` with `arm64`.

**1. Download the package and check it.**

RHEL / Rocky / Alma:

```bash
cd /tmp
curl -fLO https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.159.0/otelcol-contrib_0.159.0_linux_amd64.rpm
echo "edf3037b5065738a118d3f21469403fb1249fad17291a803a2ba0ef7d29d74d7  otelcol-contrib_0.159.0_linux_amd64.rpm" | sha256sum -c -
# otelcol-contrib_0.159.0_linux_amd64.rpm: OK
```

Debian / Ubuntu:

```bash
cd /tmp
curl -fLO https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.159.0/otelcol-contrib_0.159.0_linux_amd64.deb
echo "4ede8d750d6bf845e353be46cc550f590e6ccdaeeb60aae941cde6ad561877db  otelcol-contrib_0.159.0_linux_amd64.deb" | sha256sum -c -
```

SHA-256 of the other packages (also published next to each file on the release page as `<file>.sha256`):

| File | SHA-256 |
|---|---|
| `otelcol-contrib_0.159.0_linux_arm64.rpm` | `996f2010da2210dae7f50f9661e66595409d6e27c6499b6ea42f0b99c60cce9d` |
| `otelcol-contrib_0.159.0_linux_arm64.deb` | `430469fbfb48f123d08dfc896973bdc205ba393901cc506e92c9c928698a6d5e` |

No internet on the host: download on another machine, check it the same way, copy it to `/tmp`.

**2. Install it.**

```bash
rpm -Uvh /tmp/otelcol-contrib_0.159.0_linux_amd64.rpm      # RHEL family
dpkg -i  /tmp/otelcol-contrib_0.159.0_linux_amd64.deb      # Debian family
otelcol-contrib --version                                  # otelcol-contrib version 0.159.0
```

The package creates the user `otelcol-contrib`, the binary `/usr/bin/otelcol-contrib`, the directory
`/etc/otelcol-contrib/` and the systemd unit `otelcol-contrib.service`. The unit reads its
environment from `/etc/otelcol-contrib/otelcol-contrib.conf` and starts
`otelcol-contrib $OTELCOL_OPTIONS`. The package may start it at once with its own sample config;
the next steps replace that.

**3. Put the config in place.**

```bash
install -m 0644 /tmp/iyzitrace-collector/config.yaml /etc/otelcol-contrib/config.yaml
```

**4. Write the environment file** (the URL, the key and the names the config reads):

```bash
install -m 0640 -o root -g otelcol-contrib /tmp/iyzitrace-collector/otelcol-contrib.conf.example /etc/otelcol-contrib/otelcol-contrib.conf
vi /etc/otelcol-contrib/otelcol-contrib.conf
```

Set the four values:

| Line | Value |
|---|---|
| `IYZITRACE_INGEST_URL=` | `https://GATEWAY/ingest` (no trailing slash) |
| `IYZITRACE_API_KEY=` | the department's **agent** key |
| `IYZITRACE_HOST_NAME=` | the host's name as it should appear in Agent Manager, e.g. the output of `hostname -s` |
| `IYZITRACE_AGENT_GROUP=` | `java-hosts` (or any group name) |

Keep `OTELCOL_OPTIONS="--config=/etc/otelcol-contrib/config.yaml"`. The file holds a key: mode
0640, owner `root`, group `otelcol-contrib`.

**5. Validate the config with those values.**

```bash
( set -a; . /etc/otelcol-contrib/otelcol-contrib.conf; set +a
  otelcol-contrib validate --config=/etc/otelcol-contrib/config.yaml ) && echo "config is valid"
```

No output and `config is valid` means it is valid. An error names the line.

**6. Start it, and start it at boot.**

```bash
systemctl daemon-reload
systemctl enable otelcol-contrib
systemctl restart otelcol-contrib
systemctl status otelcol-contrib --no-pager
curl -s http://127.0.0.1:13133/ ; echo          # {"status":"Server available", ...}
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
