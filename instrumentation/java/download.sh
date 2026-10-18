#!/bin/sh
# Downloads the OpenTelemetry Java agent and the iyzitrace appserver-deployment extension into
# /opt/otel (or $1), checks their SHA-256, and copies otel-agent.properties next to them.
#
#   sudo sh java/download.sh [/opt/otel]
#
# No internet on the host? Run it on a machine that has, then copy the directory to the host
# (same path) and make it readable by the app server's user.
set -eu

AGENT_VERSION=2.21.0
EXTENSION_VERSION=0.1.0
AGENT_SHA256=5b35ccc6c275fd477a06db01923813e13d99c1a52a20b0ea8ed6576eae177c7d
EXTENSION_SHA256=c7d81bf27569db099b19a859e5f8cd4f47f6eab7b6fd0a9661d5ef7033a83d9c

DIR=${1:-/opt/otel}
HERE=$(cd "$(dirname "$0")" && pwd)
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | awk '{print $1}'; }

mkdir -p "$DIR/extensions"

curl -fsSL -o "$DIR/opentelemetry-javaagent.jar" \
  "https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v${AGENT_VERSION}/opentelemetry-javaagent.jar"
[ "$(sha256 "$DIR/opentelemetry-javaagent.jar")" = "$AGENT_SHA256" ] || { echo "agent checksum mismatch" >&2; exit 1; }

curl -fsSL -o "$DIR/extensions/appserver-deployment-extension.jar" \
  "https://github.com/antreklabs/iyzitrace-otel-java-extensions/releases/download/v${EXTENSION_VERSION}/appserver-deployment-extension-${EXTENSION_VERSION}.jar"
[ "$(sha256 "$DIR/extensions/appserver-deployment-extension.jar")" = "$EXTENSION_SHA256" ] || { echo "extension checksum mismatch" >&2; exit 1; }

[ -f "$DIR/otel-agent.properties" ] || cp "$HERE/otel-agent.properties" "$DIR/otel-agent.properties"
chmod -R a+rX "$DIR"

echo "OK: $DIR"
echo "  opentelemetry-javaagent.jar                      $AGENT_VERSION"
echo "  extensions/appserver-deployment-extension.jar    $EXTENSION_VERSION"
echo "  otel-agent.properties                            edit otel.service.name and service.namespace"
