#!/bin/sh
# OpenShift runs pods under restricted-v2 with a random UID. The charts set fixed non-root UIDs
# (1000 IyziTrace services, 101 nginx, 10001 collectors/Loki/Tempo, 65534 Alertmanager, 65532 the
# operators), so their service accounts get the built-in nonroot-v2 SCC: any non-root UID, nothing more.
# SeaweedFS sets no UID and stays on restricted-v2 (random UID), which works.
set -eu
for ns in iyzitrace-system iyzitrace; do
  oc get namespace "$ns" >/dev/null 2>&1 || oc create namespace "$ns"
  oc adm policy add-scc-to-group nonroot-v2 "system:serviceaccounts:$ns"
done
echo "nonroot-v2 granted to the service accounts of iyzitrace-system and iyzitrace"
