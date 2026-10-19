# Install the platform on Kubernetes or OpenShift

The platform is installed with three Helm charts, in this order: the operators, the object store,
the platform. The steps are the same on Kubernetes and OpenShift. Where OpenShift needs something
extra, the step says so.

You need `kubectl` (or `oc` on OpenShift) and `helm` 3.14 or later, logged in to the cluster as
cluster-admin. The machine must reach `ghcr.io`: the charts are downloaded from there.

You also need one file from this repository, [values-poc.yaml](values-poc.yaml). Download it or
clone the repository; the commands below assume you are in the folder that contains it.

## 1. Install cert-manager

The operators and the platform's internal TLS need cert-manager. If the cluster already has it
(`kubectl get pods -n cert-manager` lists running pods), skip this step.

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.2/cert-manager.yaml
kubectl -n cert-manager rollout status deploy/cert-manager-webhook
```

You should see `deployment "cert-manager-webhook" successfully rolled out`.

On OpenShift you can install the "cert-manager Operator for Red Hat OpenShift" from OperatorHub
instead.

## 2. Create the two namespaces

```bash
kubectl create namespace iyzitrace-system
kubectl create namespace iyzitrace
```

**OpenShift only:** OpenShift starts pods with a random user id, but the charts set fixed non-root
user ids (for example 1000 and 10001). Allow that in both namespaces:

```bash
oc adm policy add-scc-to-group nonroot-v2 system:serviceaccounts:iyzitrace-system
oc adm policy add-scc-to-group nonroot-v2 system:serviceaccounts:iyzitrace
```

Without this, the pods are never created and the events say
`unable to validate against any security context constraint`.

## 3. Install the operators

They install the OpenTelemetry and SeaweedFS operators. Once per cluster.

```bash
helm upgrade --install iyzitrace-operators \
  oci://ghcr.io/iyzitrace/charts/iyzitrace-operators --version 0.1.0-dev.c44dd8f \
  -n iyzitrace-system --wait --timeout 10m
kubectl -n iyzitrace-system get pods
```

You should see two pods running: `otel-operator-...` and `seaweedfs-operator-...`.

## 4. Install the object store

This is SeaweedFS with three buckets: one each for traces, logs and metrics.

```bash
helm upgrade --install iyzitrace-storage \
  oci://ghcr.io/iyzitrace/charts/iyzitrace-storage --version 0.1.0-dev.c44dd8f \
  -n iyzitrace --wait --timeout 10m
kubectl -n iyzitrace wait bucket --all --for=jsonpath='{.status.phase}'=Ready --timeout=5m
```

You should see three lines ending in `condition met`: `loki-data`, `tempo-data` and
`thanos-time-series`.

## 5. Decide the address everyone will use

nginx is the platform's only entry point. Collectors, Grafana and browsers all reach it at one
HTTPS host name. In the rest of this guide it is written as `<route-host>`.

**OpenShift:** create a Route now and note its host name.

```bash
oc -n iyzitrace create route edge iyzitrace --service=nginx --port=http --insecure-policy=Redirect
oc -n iyzitrace annotate route iyzitrace haproxy.router.openshift.io/timeout=5m
oc -n iyzitrace get route iyzitrace -o jsonpath='{.spec.host}{"\n"}'
```

The last command prints the host name, for example `iyzitrace-iyzitrace.apps.cluster.example.com`.
To choose the name yourself, add `--hostname iyzitrace.apps.cluster.example.com` to the first
command. The timeout keeps long queries and agent connections open (the router's default is 30
seconds). The Route answers 503 until step 6 is done.

**Kubernetes with an Ingress controller:** choose the host name. In `values-poc.yaml`, set
`nginx.ingress.enabled: true`, `className` and `host`; the platform chart then creates the Ingress.

## 6. Install the platform

Open `values-poc.yaml` and set two values:

| Key | Set it to |
|---|---|
| `authService.grafanaUrl` | the customer's Grafana, as the cluster can reach it, e.g. `https://grafana.customer.local`; for the kit's Grafana: `http://grafana.iyzitrace-grafana.svc:3000` ([grafana/kubernetes](../../grafana/kubernetes/README.md)) |
| `lawrence.agentHttpEndpoint` | `https://<route-host>/ingest/opamp/v1/telemetry/` (keep the slash at the end) |

The second value tells the collectors on the Linux machines where to send their own metrics and
logs. Without it they still appear in Agent Manager, but their Metrics and Logs tabs stay empty.

```bash
helm upgrade --install iyzitrace \
  oci://ghcr.io/iyzitrace/charts/iyzitrace-platform --version 1.3.1-dev.b4f7494 \
  -n iyzitrace -f values-poc.yaml --wait --timeout 20m
kubectl -n iyzitrace get pods
```

The install takes about 5 to 10 minutes. At the end, all 33 pods are `Running`.

Optional: to speed up long metric queries, add `--set thanos.queryFrontend.enabled=true` to the
command above (or `helm upgrade` later with the same flag). It adds a query-frontend that splits
range queries by day and caches their results for 10 minutes. Leave it off if you are unsure.

Check that the platform answers through the Route (replace `<route-host>`):

```bash
curl -s https://<route-host>/healthz
curl -s -o /dev/null -w '%{http_code}\n' https://<route-host>/console/
```

You should see `ok`, then `200`.

Next: [docs/02-console-and-plugin.md](../../docs/02-console-and-plugin.md).

## Optional: the automated end-to-end test

Run this only on a fresh install, before you open the console: it creates the administrator itself.
It sends test data into two test departments and checks that each department sees only its own
data, through the Route. You need Python 3 and the licence file.

```bash
python3 tests/test-k8s-e2e.py seed --base-url https://<route-host> \
  --state-file ~/iyzitrace-poc-state.json --license-file /path/to/license.lic
```

The last line must be `PASS: installed Kubernetes platform end-to-end checks`. The administrator it
created (user `helm-e2e`) and its password are in `~/iyzitrace-poc-state.json`; log in to the
console with them.

## If something goes wrong

| What you see | What to do |
|---|---|
| Pods are not created; events say `unable to validate against any security context constraint` | OpenShift: the two `oc adm policy` commands of step 2 are missing |
| Pods stay `Pending` | `kubectl -n iyzitrace describe pod <pod>`: usually no default StorageClass, or not enough CPU or memory |
| `ImagePullBackOff` | the cluster cannot reach ghcr.io or Docker Hub, or Docker Hub's rate limit was hit: [docs/00-prerequisites.md](../../docs/00-prerequisites.md#images) |
| The operators never become ready | cert-manager is missing (step 1) |
| The Route answers 503 for long | `kubectl -n iyzitrace get pods -l app.kubernetes.io/component=nginx`: nginx not ready yet |

More in [docs/06-troubleshooting.md](../../docs/06-troubleshooting.md).

## Remove it

```bash
helm uninstall iyzitrace -n iyzitrace
helm uninstall iyzitrace-storage -n iyzitrace
kubectl delete namespace iyzitrace
```

The object store's data stays on its disks until the namespace is deleted.

## What was tested before the first OpenShift PoC

On 2026-10-18, on a local Kubernetes 1.30 (minikube):

- The install from the published charts: 33 of 33 pods running.
- The end-to-end test above: 40 of 40 checks passed.
- Real OpAMP agents, over HTTP and WebSocket.
- A 5-minute restart test while components were killed and Loki was down for 60 seconds: no data
  lost.
- The plugin's setup wizard in a clean Grafana.
- A Java host (see [test/linux-java-host](../../test/linux-java-host/README.md)).

No OpenShift cluster was available, so these were checked another way:

- **Security settings:** every pod passed the Kubernetes "restricted" profile, apart from the fixed
  user ids that step 2 allows.
- **SeaweedFS:** it sets no user id, so OpenShift gives it a random one. That was rehearsed with a
  random id from the start: all its pods ran and S3 reads and writes worked.
