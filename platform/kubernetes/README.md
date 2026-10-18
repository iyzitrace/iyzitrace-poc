# Platform on Kubernetes (and OpenShift)

Installs the IyziTrace platform with its three Helm charts: operators → object store → platform.
The steps are the same on any Kubernetes 1.30+; the places where **OpenShift** differs are marked
and collected in [OpenShift](#openshift).

All commands run from a machine with `kubectl` (or `oc`) and `helm` 3.14+, with cluster-admin.

```bash
git clone https://github.com/antreklabs/iyzitrace-observability-platform.git   # the charts (private: needs access)
git clone https://github.com/iyzitrace/iyzitrace-poc.git                        # this kit
cd iyzitrace-observability-platform && git checkout dev && cd ..
export KIT=$PWD/iyzitrace-poc/platform/kubernetes
cd iyzitrace-observability-platform
```

Files used here:

| File | What |
|---|---|
| [values-iyzitrace-images.yaml](values-iyzitrace-images.yaml) | the six IyziTrace images from `ghcr.io/iyzitrace` (the chart's defaults are not published yet) |
| [values-poc.yaml](values-poc.yaml) | the PoC's settings: Grafana URL, the public agent URL, the Ingress (not on OpenShift) |
| [images.txt](images.txt), [check-images.sh](check-images.sh) | every image the install pulls, and a check that each can be pulled |
| [openshift/scc.sh](openshift/scc.sh), [openshift/route.yaml](openshift/route.yaml) | OpenShift only |

## 1. cert-manager

The operators' webhooks and the platform's internal TLS need it. Skip if it is installed
(`kubectl get pods -n cert-manager`).

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.2/cert-manager.yaml
kubectl -n cert-manager rollout status deploy/cert-manager-webhook
```

**OpenShift:** the "cert-manager Operator for Red Hat OpenShift" from OperatorHub works too.

## 2. Namespaces (and on OpenShift, the SCC)

```bash
kubectl create namespace iyzitrace-system
kubectl create namespace iyzitrace
```

**OpenShift:** run `sh $KIT/openshift/scc.sh` instead (it creates both namespaces and grants the
SCC; see [OpenShift](#openshift)).

## 3. Operators (once per cluster)

```bash
helm dependency update helm/operators
helm upgrade --install iyzitrace-operators helm/operators -n iyzitrace-system --wait --timeout 10m
kubectl -n iyzitrace-system get pods          # otel-operator, seaweedfs-operator: Running
```

## 4. Object store

```bash
helm upgrade --install iyzitrace-storage helm/storage -n iyzitrace --wait --timeout 10m
kubectl -n iyzitrace wait bucket --all --for=jsonpath='{.status.phase}'=Ready --timeout=5m
```

Do not add the repository's `values-minikube.yaml` on a real cluster: it deletes the store on uninstall.

## 5. Decide the public address (GATEWAY)

nginx is the platform's only entry point. Everything outside the cluster (collectors, Grafana,
browsers) reaches it at one HTTPS host name, called `GATEWAY` below.

| Cluster | How nginx is published | GATEWAY |
|---|---|---|
| Kubernetes with an Ingress controller | `nginx.ingress` in `values-poc.yaml` | the Ingress host |
| Kubernetes with Gateway API | `nginx.httpRoute` (see the platform's production install doc) | the HTTPRoute host |
| **OpenShift** | a Route: `kubectl apply -f $KIT/openshift/route.yaml` | `oc -n iyzitrace get route iyzitrace -o jsonpath='{.spec.host}'` |

```bash
export GATEWAY=iyzitrace.apps.example.com     # your value
```

## 6. Platform

Fill in [values-poc.yaml](values-poc.yaml):

| Key | Value |
|---|---|
| `authService.grafanaUrl` | the customer Grafana, as the cluster's pods reach it |
| `lawrence.agentHttpEndpoint` | `https://GATEWAY/ingest/opamp/v1/telemetry/` (with the trailing slash) |
| `nginx.ingress.*` | Kubernetes with an Ingress controller only; leave disabled on OpenShift |

`lawrence.agentHttpEndpoint` is the address Agent Manager gives managed collectors for their own
metrics and logs. The default is the in-cluster nginx Service, which collectors on other machines
cannot resolve. Without this setting they register, but their metrics and logs never arrive.

```bash
helm dependency update helm/platform
helm upgrade --install iyzitrace helm/platform -n iyzitrace \
  -f $KIT/values-iyzitrace-images.yaml -f $KIT/values-poc.yaml --wait --timeout 20m
kubectl -n iyzitrace get pods                                  # 33 pods, all Running
curl -s https://$GATEWAY/healthz; echo                         # ok
curl -s -o /dev/null -w '%{http_code}\n' https://$GATEWAY/console/     # 200
```

Base profile (one of each component): about 2 CPU and 3.5Gi memory requested, 17 PVCs (~125Gi,
50Gi of it the object store) on the default StorageClass. For production sizing and three replicas,
see the platform's `values-prod.yaml` and `docs/deployment/kubernetes-production-installation.md`.

## 7. Optional: the licensed end-to-end test

Only on a **fresh** install, **before** the console setup (it creates the administrator itself). It
checks ingest, queries, tenant isolation, inventory and the service graph through the gateway, and
leaves two test departments behind.

```bash
python3 scripts/test-k8s-e2e.py seed --base-url https://$GATEWAY \
  --state-file ~/iyzitrace-poc-state.json --license-file /path/to/license.lic
```

The last line must be `PASS: installed Kubernetes platform end-to-end checks`. The administrator it
created (`helm-e2e`) and its password are in the state file (mode 0600); use them for the console.

Next: [docs/02-console-and-plugin.md](../../docs/02-console-and-plugin.md).

---

## OpenShift

Three differences from plain Kubernetes:

1. **SCC (step 2).** OpenShift runs pods under the `restricted-v2` SCC with a random UID. The charts
   set fixed non-root UIDs: 1000 for the IyziTrace services, 101 for nginx, 10001 for the collectors,
   Loki and Tempo, 65534 for Alertmanager and 65532 for the operators.
   [openshift/scc.sh](openshift/scc.sh) grants the built-in `nonroot-v2` SCC (any non-root UID,
   nothing more) to the service accounts of `iyzitrace-system` and `iyzitrace`. Without it, pods are
   rejected with `unable to validate against any security context constraint`. Needs OpenShift
   4.11+ and cluster-admin.
2. **Route (step 5).** [openshift/route.yaml](openshift/route.yaml): TLS ends at the router (edge),
   HTTP is redirected, and the router timeout is raised to 5 minutes for OpAMP WebSocket sessions and
   long queries (the default is 30s). Leave `nginx.ingress` disabled.
3. **cert-manager (step 1)** can come from OperatorHub.

**What was checked before the first OpenShift PoC** (on Kubernetes, since no OpenShift cluster was
available):

- **Pod security.** All pods were audited against the Kubernetes `restricted` Pod Security profile.
  - Unset `seccompProfile`, and Alertmanager's unset privilege escalation and capabilities, are
    filled in by OpenShift's SCC admission (`RuntimeDefault`, `false`, `drop: [ALL]`).
  - The fixed UIDs are the remaining difference, and step 2 covers them.
- **SeaweedFS** sets no UID and stays on `restricted-v2`. It was run from the start as UID
  1000680000 with group 0, fsGroup, all capabilities dropped and seccomp `RuntimeDefault`. All four
  pods ran, the buckets became Ready, and an S3 upload and download succeeded. (It fails only if root
  wrote the same volumes first, which does not happen on OpenShift.)
- **NetworkPolicy.** OpenShift enforces policies. The chart ships one (the internal Thanos query);
  it does not touch the Route → nginx path.

---

## Rehearsal results (minikube, Kubernetes 1.30, 2026-10-18, platform `dev` at `c44dd8f`)

| Test | Result |
|---|---|
| Install: operators, object store, platform | 33/33 pods Running |
| Licensed gateway/tenant test (`test-k8s-e2e.py seed`) | 40/40 |
| OpAMP agents, HTTP and WebSocket (`scripts/test-k8s-opamp.go`) | passed |
| Restart and kill test, 5 minutes, Loki down for 60s (`scripts/test-k8s-restarts.sh`) | 300/300 per signal; SQLite databases kept |
| Plugin setup wizard in a clean Grafana | passed |
| OTel demo against the platform | data in every signal; 5 agents online, drawer metrics and logs |
| Test bed (every layer and plugin screen) | 194/197. The 3 others are environment differences: a check that calls a Compose container by name, a region a fresh install attributes to the run, and modules without configuration yet (AI provider, teams) |

## Clean up

```bash
helm uninstall iyzitrace -n iyzitrace
helm uninstall iyzitrace-storage -n iyzitrace   # the store is kept (keep: true); delete its PVCs to remove it
kubectl delete namespace iyzitrace
```

The operators can stay for the next install. Uninstalling them deletes the OpenTelemetry CRDs and
every collector in the cluster.
