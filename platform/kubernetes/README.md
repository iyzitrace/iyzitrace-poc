# Install the platform on Kubernetes or OpenShift

The platform is installed with three Helm charts, in this order: the operators, the object store,
the platform. The steps are the same on Kubernetes and OpenShift. Where OpenShift needs something
extra, the step says so.

You need `kubectl` (or `oc` on OpenShift) and `helm` 3.14 or later, logged in to the cluster as
cluster-admin. The machine must reach `ghcr.io`: the charts are downloaded from there.

The operators, object store and platform charts are installed with `--devel` and no version: that gives the
newest chart we have published, so this guide does not change when a chart is updated. (`--devel` is needed
because the charts are pre-release versions, which Helm skips otherwise; `helm list -A` shows which version
you got.) cert-manager and Grafana come from other projects and keep a fixed version.

You also need two files from this repository, in the folder the commands below run from:
[values.yaml](values.yaml) and [values-cert-manager.yaml](values-cert-manager.yaml). Download them or
clone the repository.

## Before you start: the values files

[values.yaml](values.yaml) is one file for steps 3, 4 and 6 (the operators, the object store and the
platform): each chart reads only the keys it knows, so the same file is given to all three commands.
[values-cert-manager.yaml](values-cert-manager.yaml) is for step 1 only: the cert-manager chart refuses
keys it does not know.

Most lines stay as they are. A few places depend on your cluster; they are marked `EDIT` in the files,
with the lines to uncomment (remove the `#` at the start of the line; in an editor, select the block and
toggle the comment). Do this **before** step 1:

| If your cluster... | Do this |
|---|---|
| may pull images only from your own registry | in both files, uncomment every block marked `EDIT: registry` and replace `REGISTRY` with your registry's address (every occurrence), for example `registry.example.com` |
| lets the pods that reach the internet (auth-service, ai-gateway) out only through an HTTP proxy | in `values.yaml`, uncomment the two blocks marked `EDIT: proxy` and replace `PROXY-HOST:PORT` |
| has neither restriction | change nothing |

**What a registry address looks like.** Mirror every image into your registry under its original
address, with your registry in front of it; the tags stay as they are. The files already contain the
resulting names:

| Original | In your registry |
|---|---|
| `docker.io/grafana/loki:3.7.8` | `REGISTRY/docker.io/grafana/loki:3.7.8` |
| `ghcr.io/iyzitrace/auth-service:<tag>` | `REGISTRY/ghcr.io/iyzitrace/auth-service:<tag>` |
| `quay.io/prometheus/alertmanager:v0.34.0` | `REGISTRY/quay.io/prometheus/alertmanager:v0.34.0` |
| `nginx:1.30.4-alpine` (a short name) | `REGISTRY/docker.io/library/nginx:1.30.4-alpine` |

The full list of images is in [docs/00-prerequisites.md](../../docs/00-prerequisites.md#images). The
charts themselves come from `ghcr.io`: mirror them too, or download them once with `helm pull` and
install from the files. A registry that needs a login is not covered here; on OpenShift the
cluster-wide pull secret (Administration → Cluster Settings → Configuration → global pull secret)
usually has it already.

**What the proxy is for.** auth-service asks GitHub for the newest plugin version (License page) and may
call Jira; ai-gateway calls the AI provider. Without a proxy and without internet the platform works;
only the update check and the AI features need the outside.

## 1. Install cert-manager

The operators and the platform's internal TLS need cert-manager. If the cluster already has it
(`kubectl get pods -n cert-manager` lists running pods), skip this step.

```bash
helm upgrade --install cert-manager \
  oci://quay.io/jetstack/charts/cert-manager --version v1.17.2 \
  -n cert-manager --create-namespace -f values-cert-manager.yaml --wait --timeout 5m
kubectl -n cert-manager get pods
```

You should see three pods running: `cert-manager-...`, `cert-manager-cainjector-...` and
`cert-manager-webhook-...`.

[values-cert-manager.yaml](values-cert-manager.yaml) installs its custom resource definitions and
gives every cert-manager pod small CPU and memory requests and limits, which a cluster with quotas
(OpenShift, for example) requires. A cert-manager you did not install with this file has whatever
resources its installer gave it.

On OpenShift you can install the "cert-manager Operator for Red Hat OpenShift" from OperatorHub
instead; set the resources of its three pods there.

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
  oci://ghcr.io/iyzitrace/charts/iyzitrace-operators --devel \
  -n iyzitrace-system -f values.yaml --wait --timeout 10m
kubectl -n iyzitrace-system get pods
```

You should see two pods running: `otel-operator-...` and `seaweedfs-operator-...`.

## 4. Install the object store

This is SeaweedFS with three buckets: one each for traces, logs and metrics.

```bash
helm upgrade --install iyzitrace-storage \
  oci://ghcr.io/iyzitrace/charts/iyzitrace-storage --devel \
  -n iyzitrace -f values.yaml --wait --timeout 10m
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

**Kubernetes with an Ingress controller:** choose the host name. In `values.yaml`, set
`nginx.ingress.enabled: true`, `className` and `host`; the platform chart then creates the Ingress.

## 6. Install the platform

Open `values.yaml` and set two values:

| Key | Set it to |
|---|---|
| `authService.grafanaUrl` | the customer's Grafana, as the cluster can reach it, e.g. `https://grafana.customer.local`; for the kit's Grafana: `http://grafana.iyzitrace-grafana.svc:3000` ([grafana/kubernetes](../../grafana/kubernetes/README.md)) |
| `lawrence.agentHttpEndpoint` | `https://<route-host>/ingest/opamp/v1/telemetry/` (keep the slash at the end) |

The second value tells the collectors on the Linux machines where to send their own metrics and
logs. Without it they still appear in Agent Manager, but their Metrics and Logs tabs stay empty.

```bash
helm upgrade --install iyzitrace \
  oci://ghcr.io/iyzitrace/charts/iyzitrace-onprem --devel \
  -n iyzitrace -f values.yaml --wait --timeout 20m
kubectl -n iyzitrace get pods
```

Installed before 2026-10-21, when this chart was called `iyzitrace-platform`? Run the same command:
the release `iyzitrace` upgrades in place to the new chart name, and its data and secrets stay.

The install takes about 5 to 10 minutes. At the end, all 33 pods are `Running`.

**CPU and memory.** `values.yaml` gives every container of the platform small requests
and limits (together about 1.3 CPU and 3.8 GiB requested, with the object store). If a pod restarts with
`OOMKilled` (`kubectl -n iyzitrace get pods`, then `kubectl -n iyzitrace describe pod <pod>`),
raise that component's memory limit in `values.yaml`; if a component is slow and
`kubectl -n iyzitrace top pods` shows its CPU at the limit, raise its CPU limit.

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
