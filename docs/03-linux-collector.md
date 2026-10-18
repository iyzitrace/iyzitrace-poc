# 3. Collector on each Linux machine

Install one OpenTelemetry Collector on every machine that runs a Java server. The Java agent sends
its data to this collector on the same machine. The collector adds the machine's own metrics (CPU,
memory, disk, network) and sends everything to IyziTrace with the department's **agent** key. It
also shows up in IyziTrace's Agent Manager.

Run the commands as root, or put `sudo` in front of each. The examples are for x86_64; on arm64
machines write `arm64` instead of `amd64` in the file names.

## 1. Download the collector package

RHEL, Rocky or Alma:

```bash
cd /tmp
curl -fLO https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.159.0/otelcol-contrib_0.159.0_linux_amd64.rpm
echo "edf3037b5065738a118d3f21469403fb1249fad17291a803a2ba0ef7d29d74d7  otelcol-contrib_0.159.0_linux_amd64.rpm" | sha256sum -c -
```

Debian or Ubuntu:

```bash
cd /tmp
curl -fLO https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.159.0/otelcol-contrib_0.159.0_linux_amd64.deb
echo "4ede8d750d6bf845e353be46cc550f590e6ccdaeeb60aae941cde6ad561877db  otelcol-contrib_0.159.0_linux_amd64.deb" | sha256sum -c -
```

The second command must print `OK`: the file is complete and unchanged.

For arm64 the checksums are `996f2010da2210dae7f50f9661e66595409d6e27c6499b6ea42f0b99c60cce9d`
(rpm) and `430469fbfb48f123d08dfc896973bdc205ba393901cc506e92c9c928698a6d5e` (deb).

If the machine has no internet access, download the file on another computer, check it the same
way, and copy it to `/tmp` on the machine.

## 2. Install it

```bash
rpm -Uvh /tmp/otelcol-contrib_0.159.0_linux_amd64.rpm      # RHEL, Rocky, Alma
dpkg -i /tmp/otelcol-contrib_0.159.0_linux_amd64.deb        # Debian, Ubuntu
otelcol-contrib --version
```

The last command prints `otelcol-contrib version 0.159.0`.

The package installs a systemd service called `otelcol-contrib`. Its configuration lives in
`/etc/otelcol-contrib/`. The package may already have started it with a sample configuration; the
next steps replace that.

## 3. Put IyziTrace's configuration in place

```bash
curl -fLo /etc/otelcol-contrib/config.yaml https://raw.githubusercontent.com/iyzitrace/iyzitrace-poc/main/collectors/linux-host/config.yaml
curl -fLo /etc/otelcol-contrib/otelcol-contrib.conf https://raw.githubusercontent.com/iyzitrace/iyzitrace-poc/main/collectors/linux-host/otelcol-contrib.conf.example
chown root:otelcol-contrib /etc/otelcol-contrib/otelcol-contrib.conf
chmod 640 /etc/otelcol-contrib/otelcol-contrib.conf
```

Without internet, copy the two files from this repository's `collectors/linux-host/` folder to the
same places.

`config.yaml` is the same on every machine. `otelcol-contrib.conf` holds the values that differ
per machine, including the key, so only root and the collector can read it.

## 4. Fill in the values for this machine

```bash
vi /etc/otelcol-contrib/otelcol-contrib.conf
```

Change these four lines:

```text
IYZITRACE_INGEST_URL=https://<route-host>/ingest
IYZITRACE_API_KEY=<agent-key>
IYZITRACE_HOST_NAME=<this machine's name>
IYZITRACE_AGENT_GROUP=java-hosts
```

- `IYZITRACE_INGEST_URL`: the platform's host name followed by `/ingest`, with no slash at the end.
- `IYZITRACE_API_KEY`: the department's **agent** key, not the reader key.
- `IYZITRACE_HOST_NAME`: how the machine appears in Agent Manager; `hostname -s` prints a good
  choice.
- `IYZITRACE_AGENT_GROUP`: the group in Agent Manager; any name works.

Leave the `OTELCOL_OPTIONS=` line as it is.

## 5. Check the configuration

This loads the values you just wrote and checks the configuration without starting anything:

```bash
( set -a; . /etc/otelcol-contrib/otelcol-contrib.conf; set +a
  otelcol-contrib validate --config=/etc/otelcol-contrib/config.yaml ) && echo "config is valid"
```

You should see `config is valid`. Otherwise the error names the wrong line.

## 6. Start the collector

```bash
systemctl enable otelcol-contrib
systemctl restart otelcol-contrib
systemctl status otelcol-contrib --no-pager
curl -s http://127.0.0.1:13133/
```

`systemctl status` shows `active (running)`. The `curl` answers with `"status":"Server available"`.

If it is not running, the last 50 log lines tell why:

```bash
journalctl -u otelcol-contrib -n 50 --no-pager
```

A warning `failed to get host ID` is harmless.

## 7. Check it in IyziTrace

In Grafana, IyziTrace:

- **Agent Manager → Agents:** `otelcol-<machine name>` in group `java-hosts`, Online. Open it: the
  Metrics and Logs tabs fill within a minute.
- **Atlas** or **Horizon:** the machine, with its CPU and memory, after one or two minutes.

Next: [04-java-agent.md](04-java-agent.md).

## When the situation is different

**The platform's certificate is signed by an internal CA.** Copy the CA certificate to
`/etc/otelcol-contrib/iyzitrace-ca.pem`. In `config.yaml`, remove the `#` in front of the two
`tls:` / `ca_file:` blocks. Then run `systemctl restart otelcol-contrib`.

**Outbound traffic must go through a proxy.** Add these lines to `otelcol-contrib.conf`, then
restart:

```text
HTTPS_PROXY=http://<proxy-host>:<port>
NO_PROXY=localhost,127.0.0.1
```

**Java servers on other machines send to this collector.** In `config.yaml`, change
`127.0.0.1:4317` and `127.0.0.1:4318` to `0.0.0.0:4317` and `0.0.0.0:4318`. Open these ports in the
firewall only for those machines, and point their agents at `http://<this machine>:4318`.

**You also want CPU and memory per Java process.** The collector can only read other users'
processes as root. Run `systemctl edit otelcol-contrib`, add the two lines below, then restart:

```text
[Service]
User=root
```

**You want one service per server, not one per application.** In `config.yaml`, remove
`groupbyattrs/deployment` and `transform/deployment-as-service` from the `traces` and `logs`
pipelines. See [04-java-agent.md](04-java-agent.md#service-names) for what that changes.
