#!/bin/sh
# Installs or updates the OpenTelemetry Collector (contrib 0.159.0) on a RHEL/Rocky/Alma or
# Debian/Ubuntu host, puts this repository's config in place, and starts the service.
#
#   sudo sh collector/install.sh --ingest-url https://GATEWAY/ingest --api-key AGENT-KEY \
#        [--host-name NAME] [--group java-hosts] [--package /path/to/otelcol-contrib.rpm|.deb]
#
# --package installs a file you copied to the host (no internet needed). Without it the package is
# downloaded from GitHub and its SHA-256 is checked. Re-running updates the config and keeps the
# existing environment file unless --ingest-url/--api-key are given again.
set -eu

VERSION=0.159.0
HERE=$(cd "$(dirname "$0")" && pwd)
INGEST_URL="" API_KEY="" HOST_NAME=$(hostname -s 2>/dev/null || hostname) GROUP=java-hosts PACKAGE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --ingest-url) INGEST_URL=${2%/}; shift 2 ;;
    --api-key) API_KEY=$2; shift 2 ;;
    --host-name) HOST_NAME=$2; shift 2 ;;
    --group) GROUP=$2; shift 2 ;;
    --package) PACKAGE=$2; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

[ "$(id -u)" = 0 ] || { echo "run as root (sudo)" >&2; exit 1; }

case "$(uname -m)" in
  x86_64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
if command -v rpm >/dev/null 2>&1 && ! command -v dpkg >/dev/null 2>&1; then KIND=rpm; else KIND=deb; fi

# SHA-256 of the release packages (from the release's .sha256 files).
sha_of() {
  case "$1" in
    amd64.rpm) echo edf3037b5065738a118d3f21469403fb1249fad17291a803a2ba0ef7d29d74d7 ;;
    amd64.deb) echo 4ede8d750d6bf845e353be46cc550f590e6ccdaeeb60aae941cde6ad561877db ;;
    arm64.rpm) echo 996f2010da2210dae7f50f9661e66595409d6e27c6499b6ea42f0b99c60cce9d ;;
    arm64.deb) echo 430469fbfb48f123d08dfc896973bdc205ba393901cc506e92c9c928698a6d5e ;;
  esac
}

installed=$(otelcol-contrib --version 2>/dev/null | awk '{print $NF}' || true)
if [ "$installed" = "$VERSION" ] && [ -z "$PACKAGE" ]; then
  echo "otelcol-contrib $VERSION is already installed"
else
  if [ -z "$PACKAGE" ]; then
    PACKAGE=/tmp/otelcol-contrib_${VERSION}_linux_${ARCH}.${KIND}
    echo "downloading $(basename "$PACKAGE")"
    curl -fsSL -o "$PACKAGE" "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${VERSION}/otelcol-contrib_${VERSION}_linux_${ARCH}.${KIND}"
    echo "$(sha_of "$ARCH.$KIND")  $PACKAGE" | sha256sum -c -
  fi
  case "$PACKAGE" in
    *.rpm) rpm -Uvh --replacepkgs "$PACKAGE" ;;
    *.deb) dpkg -i "$PACKAGE" ;;
    *) echo "--package must be a .rpm or .deb" >&2; exit 1 ;;
  esac
fi

install -d -m 0755 /etc/otelcol-contrib
install -m 0644 "$HERE/config.yaml" /etc/otelcol-contrib/config.yaml

CONF=/etc/otelcol-contrib/otelcol-contrib.conf
if [ -n "$INGEST_URL" ] || [ -n "$API_KEY" ] || ! grep -q '^IYZITRACE_INGEST_URL=' "$CONF" 2>/dev/null; then
  [ -n "$INGEST_URL" ] && [ -n "$API_KEY" ] || { echo "--ingest-url and --api-key are required on the first install" >&2; exit 2; }
  umask 027
  sed -e "s|^IYZITRACE_INGEST_URL=.*|IYZITRACE_INGEST_URL=$INGEST_URL|" \
      -e "s|^IYZITRACE_API_KEY=.*|IYZITRACE_API_KEY=$API_KEY|" \
      -e "s|^IYZITRACE_HOST_NAME=.*|IYZITRACE_HOST_NAME=$HOST_NAME|" \
      -e "s|^IYZITRACE_AGENT_GROUP=.*|IYZITRACE_AGENT_GROUP=$GROUP|" \
      "$HERE/otelcol-contrib.conf.example" > "$CONF"
  chown root:otelcol-contrib "$CONF" 2>/dev/null || true
  chmod 0640 "$CONF"
  echo "wrote $CONF (the agent key is not printed)"
fi

# Check the config with the values from the environment file before (re)starting.
( set -a; . "$CONF"; set +a; otelcol-contrib validate --config=/etc/otelcol-contrib/config.yaml )
echo "config is valid"

if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  systemctl daemon-reload
  systemctl enable otelcol-contrib >/dev/null 2>&1 || true
  systemctl restart otelcol-contrib
  sleep 3
  systemctl --no-pager --lines=0 status otelcol-contrib || true
  curl -fsS http://127.0.0.1:13133/ >/dev/null && echo "health check: OK" || echo "health check: not answering yet (see: journalctl -u otelcol-contrib -n 50)"
else
  echo "systemd not found: start it with  otelcol-contrib --config=/etc/otelcol-contrib/config.yaml  (after sourcing $CONF)"
fi
