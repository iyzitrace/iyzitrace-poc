# IyziTrace PoC on OpenShift: step by step

This branch (`mkk-poc`) installs the IyziTrace platform and a Grafana with the IyziTrace plugin on
OpenShift, from your own image registry, through your proxy. Everything is already set up for that:
you type your registry's address and your proxy's address once (step 2), and then copy the commands in
order. About 30 minutes, most of it waiting for pods.

## What you need

- OpenShift 4.11 or later and `oc` logged in as cluster-admin. Check: `oc auth can-i '*' '*' --all-namespaces` prints `yes`.
- `helm` 3.14 or later, and `git`.
- A default StorageClass with about 125 GiB free, and about 4 CPU and 16 GiB memory free on the workers.
- **Your registry's address**, with the images below copied into it.
  Each image goes in under its original address, with your registry in front:
  `docker.io/grafana/loki:3.7.8` becomes `PUT HERE/docker.io/grafana/loki:3.7.8` (PUT HERE = your registry). Tags stay as they are.
- **Your proxy's address** (host and port). It must let through HTTPS to
  `github.com`, `release-assets.githubusercontent.com` and `objects.githubusercontent.com` (Grafana
  downloads its plugins from GitHub) and to the AI provider, if you use the AI features.
- **The licence file** (`.lic`).
- The machine you run the commands on reaches `ghcr.io` and `quay.io`: the Helm charts are downloaded
  from there. Through a proxy, run `export HTTPS_PROXY=http://PUT HERE` (your proxy, as host:port) once in your
  terminal first (`helm` uses it).

The images to copy (22 are needed; the last two are optional: `busybox` is only for `helm test` of the
operators, `cert-manager-acmesolver` only if you later use ACME certificates):

```text
docker.io/chrislusf/seaweedfs-operator:1.0.39
docker.io/chrislusf/seaweedfs:4.44
docker.io/curlimages/curl:8.8.0
docker.io/grafana/grafana:13.1.1
docker.io/grafana/loki:3.7.8
docker.io/grafana/tempo:2.10.7
docker.io/library/nginx:1.30.4-alpine
docker.io/otel/opentelemetry-collector-contrib:0.159.0
ghcr.io/iyzitrace/auth-service:dev-c44dd8f
ghcr.io/iyzitrace/holmes:dev-c44dd8f
ghcr.io/iyzitrace/inventory-service:dev-c44dd8f
ghcr.io/iyzitrace/opamp:dev-c44dd8f
ghcr.io/iyzitrace/query-guard:dev-c44dd8f
ghcr.io/iyzitrace/thanos:v0.42.4-iyz.1
ghcr.io/open-telemetry/opentelemetry-operator/opentelemetry-operator:0.144.0
quay.io/brancz/kube-rbac-proxy:v0.20.0
quay.io/jetstack/cert-manager-cainjector:v1.17.2
quay.io/jetstack/cert-manager-controller:v1.17.2
quay.io/jetstack/cert-manager-startupapicheck:v1.17.2
quay.io/jetstack/cert-manager-webhook:v1.17.2
quay.io/prometheus-operator/prometheus-config-reloader:v0.93.1
quay.io/prometheus/alertmanager:v0.34.0
docker.io/library/busybox:latest
quay.io/jetstack/cert-manager-acmesolver:v1.17.2
```

## 1. Get the kit

```bash
git clone https://github.com/iyzitrace/iyzitrace-poc.git
cd iyzitrace-poc
git checkout mkk-poc
```

## 2. Enter your registry and your proxy

Two commands. In each, replace `PUT HERE` with your own address (the proxy as `host:port`), and keep the rest
as it is. They write your values into the three settings files.

```bash
sed -i 's#REGISTRY#PUT HERE#g' platform/kubernetes/values.yaml platform/kubernetes/values-cert-manager.yaml grafana/kubernetes/values.yaml
sed -i 's#PROXY-HOST:PORT#PUT HERE#g' platform/kubernetes/values.yaml grafana/kubernetes/values.yaml
```

On a Mac, write `sed -i ''` instead of `sed -i`. Check that nothing is left (neither a word to replace nor
`PUT HERE` that you forgot to replace):

```bash
grep -n "REGISTRY\|PROXY-HOST\|PUT HERE" platform/kubernetes/values.yaml platform/kubernetes/values-cert-manager.yaml grafana/kubernetes/values.yaml
```

It must print nothing.

## 3. Install cert-manager

```bash
cd platform/kubernetes
helm upgrade --install cert-manager \
  oci://quay.io/jetstack/charts/cert-manager --version v1.17.2 \
  -n cert-manager --create-namespace -f values-cert-manager.yaml --wait --timeout 5m
kubectl -n cert-manager get pods
```

You should see three pods running: `cert-manager-...`, `cert-manager-cainjector-...`, `cert-manager-webhook-...`.
(If the cluster already has cert-manager, skip this step.) The commands of steps 3 to 9 are run in this
folder, `platform/kubernetes`.

## 4. Create the two namespaces and allow the pods' user ids

```bash
oc create namespace iyzitrace-system
oc create namespace iyzitrace
oc adm policy add-scc-to-group nonroot-v2 system:serviceaccounts:iyzitrace-system
oc adm policy add-scc-to-group nonroot-v2 system:serviceaccounts:iyzitrace
```

## 5. Install the operators

`--devel` (here and in steps 6 and 8) means: use the newest chart we have published. The charts are pre-release
versions, which Helm skips without it. `helm list -A` shows the version you got.

```bash
helm upgrade --install iyzitrace-operators \
  oci://ghcr.io/iyzitrace/charts/iyzitrace-operators --devel \
  -n iyzitrace-system -f values.yaml --wait --timeout 10m
kubectl -n iyzitrace-system get pods
```

Two pods running: `otel-operator-...` and `seaweedfs-operator-...`.

## 6. Install the object store

```bash
helm upgrade --install iyzitrace-storage \
  oci://ghcr.io/iyzitrace/charts/iyzitrace-storage --devel \
  -n iyzitrace -f values.yaml --wait --timeout 10m
kubectl -n iyzitrace wait bucket --all --for=jsonpath='{.status.phase}'=Ready --timeout=5m
```

Three lines ending in `condition met`.

## 7. Create the platform's address

nginx is the platform's only entry point. Create its Route and read its host name:

```bash
oc -n iyzitrace create route edge iyzitrace --service=nginx --port=http --insecure-policy=Redirect
oc -n iyzitrace annotate route iyzitrace haproxy.router.openshift.io/timeout=5m
oc -n iyzitrace get route iyzitrace -o jsonpath='{.spec.host}{"\n"}'
```

The last command prints the host name. Put it into the settings file, replacing `PUT HERE` with that host name:

```bash
sed -i 's#ROUTE-HOST#PUT HERE#g' values.yaml
```

(Mac: `sed -i ''`.) Check: `grep -n "ROUTE-HOST\|PUT HERE" values.yaml` must print nothing.
The Route answers 503 until step 8 is done.

## 8. Install the platform

```bash
helm upgrade --install iyzitrace \
  oci://ghcr.io/iyzitrace/charts/iyzitrace-platform --devel \
  -n iyzitrace -f values.yaml --wait --timeout 20m
kubectl -n iyzitrace get pods
```

It takes 5 to 10 minutes. At the end, all 33 pods are `Running`.

## 9. Check the platform

Replace `PUT-HERE` with the platform's host name (the one step 7 printed):

```bash
curl -s https://PUT-HERE/healthz
curl -s -o /dev/null -w '%{http_code}\n' https://PUT-HERE/console/
```

You should see `ok`, then `200`. (Add `-k` if the Route's certificate is signed by the cluster's own CA.)

## 10. Install Grafana with the IyziTrace plugin

Choose Grafana's administrator password (replace `CHOOSE-A-PASSWORD`), create its Route and read its host name:

```bash
cd ../../grafana/kubernetes
oc create namespace iyzitrace-grafana
kubectl -n iyzitrace-grafana create secret generic grafana-admin --from-literal=admin-user=admin --from-literal=admin-password='CHOOSE-A-PASSWORD'
oc -n iyzitrace-grafana create route edge grafana --service=grafana --port=service --insecure-policy=Redirect
oc -n iyzitrace-grafana get route grafana -o jsonpath='{.spec.host}{"\n"}'
```

Put the host name it prints into the settings file (replace `PUT HERE`), and install:

```bash
sed -i 's#GRAFANA-HOST#PUT HERE#g' values.yaml
grep -n "GRAFANA-HOST\|PUT HERE" values.yaml
helm upgrade --install grafana \
  oci://ghcr.io/grafana-community/helm-charts/grafana --version 14.0.1 \
  -n iyzitrace-grafana -f values.yaml --wait --timeout 10m
kubectl -n iyzitrace-grafana get pods
```

The `grep` line must print nothing. Then one pod, `1/1 Running`. It may restart once on its first start while it downloads the plugins; that is normal.
Open `https://<Grafana host>` and log in as `admin` with the password you chose. Under Administration → Plugins,
**IyziTrace** is enabled.

## 11. Set up IyziTrace

This is done in the browser, once:

1. **Platform console**, `https://<platform host>/console/`: create the administrator, install the licence
   (License page), create a department on the Tenants page, and create two keys for it on the API Keys page
   (an **agent** key for the collectors and a **reader** key for Grafana). Details:
   [docs/02-console-and-plugin.md](docs/02-console-and-plugin.md).
2. **Grafana**, IyziTrace: the setup wizard asks for the platform address, `https://<platform host>`, and the
   department's reader key. Press Verify, then configure the data sources.

Then the collectors on the Linux machines and the Java agents: [docs/03-linux-collector.md](docs/03-linux-collector.md),
[docs/04-java-agent.md](docs/04-java-agent.md), and the final checks in [docs/05-verify.md](docs/05-verify.md).

## If something goes wrong

| What you see | What to do |
|---|---|
| A pod is `ImagePullBackOff` | `oc -n <namespace> describe pod <pod>` shows the image address it tried. It must exist in your registry under exactly that address (see the list above) |
| Pods are not created; events say `unable to validate against any security context constraint` | step 4 was skipped for that namespace |
| A pod stays `Pending` | `oc -n <namespace> describe pod <pod>`: usually no default StorageClass or not enough CPU or memory |
| A pod restarts with `OOMKilled` | raise that component's memory limit in `platform/kubernetes/values.yaml` (every component has a `resources` entry) and run its install command again |
| The wizard or a data source test says `x509: certificate signed by unknown authority` | Grafana does not trust the platform Route's certificate: see below |
| Agent Manager says `grafana_admin_required` or answers 403 | `values.yaml` in `platform/kubernetes` has `authService.grafanaUrl: http://grafana.iyzitrace-grafana.svc:3000`; if you reinstalled Grafana, restart the platform's login service: `oc -n iyzitrace rollout restart sts/auth-service` |

More in [docs/06-troubleshooting.md](docs/06-troubleshooting.md).

**The Route's certificate is signed by the cluster's own CA.** In `grafana/kubernetes`:

```bash
oc -n openshift-config-managed get configmap default-ingress-cert -o jsonpath='{.data.ca-bundle\.crt}' > router-ca.crt
kubectl -n iyzitrace-grafana create configmap platform-ca --from-file=router-ca.crt
```

Then in `grafana/kubernetes/values.yaml` uncomment the line `SSL_CERT_DIR: /etc/platform-ca` (under `env:`) and the
`extraConfigmapMounts` lines at the end of the file, and run the `helm upgrade --install grafana ...` command of
step 10 again. Grafana restarts; run the wizard's Verify again.

## Remove it

```bash
helm uninstall iyzitrace -n iyzitrace
helm uninstall iyzitrace-storage -n iyzitrace
helm uninstall iyzitrace-operators -n iyzitrace-system
helm uninstall grafana -n iyzitrace-grafana
helm uninstall cert-manager -n cert-manager
oc delete namespace iyzitrace iyzitrace-system iyzitrace-grafana cert-manager
```

---

The general version of this kit (any Kubernetes, your choice of registry and proxy) is on the `main` branch.
