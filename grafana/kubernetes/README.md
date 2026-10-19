# Grafana with the IyziTrace plugin, on Kubernetes or OpenShift

The IyziTrace screens live in a Grafana plugin. If the customer has no Grafana you can use for the
PoC, this installs one next to the platform with the official Grafana Helm chart. The plugin and the
two plugins it needs are installed by Grafana itself when the pod starts, all three from GitHub:

| Plugin | Where it comes from |
|---|---|
| IyziTrace 1.3.1 | [the release `grafana-plugin-dev.de49fe9`](https://github.com/iyzitrace/iyzitrace-poc/releases/tag/grafana-plugin-dev.de49fe9) of this repository: a build of the plugin repository's `dev` branch, commit `de49fe9f`. It is not signed, so Grafana is told to let exactly this plugin load unsigned |
| Infinity data source 4.1.1 | [the release `v4.1.1`](https://github.com/grafana/grafana-infinity-datasource/releases/tag/v4.1.1) of its repository. The IyziTrace plugin depends on it. The zip in `values.yaml` is for amd64; on an arm64 cluster replace `linux_amd64` with `linux_arm64` in its address |
| Plotly panel 0.5.0 | [the release `v0.5.0`](https://github.com/ae3e/ae3e-plotly-panel/releases/tag/v0.5.0) of its repository. The platform's dashboards use it |

The Grafana is 13.1.1, the version the plugin is developed against (it needs 12.3 or later). If the
customer already has a Grafana, skip this and install the plugin there instead:
[docs/02-console-and-plugin.md](../../docs/02-console-and-plugin.md).

You need `kubectl` (or `oc` on OpenShift) and `helm` 3.14 or later, logged in to the cluster, and
the files [values.yaml](values.yaml) (and, for OpenShift, [values-openshift.yaml](values-openshift.yaml))
from this folder; the commands assume you are in it. The pod needs outbound HTTPS to `github.com`
(and the cluster must pull `grafana/grafana:13.1.1`); it does not need `grafana.com`. Install Grafana **before the platform**: the platform needs Grafana's address in step 6
of its guide.

## 1. Create the namespace and the administrator's login

```bash
kubectl create namespace iyzitrace-grafana
kubectl -n iyzitrace-grafana create secret generic grafana-admin --from-literal=admin-user=admin --from-literal=admin-password='CHOOSE-A-PASSWORD'
```

Replace `CHOOSE-A-PASSWORD` with your own.

## 2. Install Grafana

```bash
helm upgrade --install grafana \
  oci://ghcr.io/grafana-community/helm-charts/grafana --version 14.0.1 \
  -n iyzitrace-grafana -f values.yaml --wait --timeout 10m
```

**OpenShift:** add `-f values-openshift.yaml` after `-f values.yaml`. OpenShift starts pods with a
random user id, but the chart sets a fixed one (472); that file removes it.

```bash
kubectl -n iyzitrace-grafana get pods
```

You should see one pod, `grafana-...`, `1/1 Running`. The plugins are downloaded in the first
seconds after it starts. Without access to grafana.com the pod restarts once on its first start
(see the table at the end); that is expected.

## 3. Open it to browsers

**OpenShift:**

```bash
oc -n iyzitrace-grafana create route edge grafana --service=grafana --port=service --insecure-policy=Redirect
oc -n iyzitrace-grafana get route grafana -o jsonpath='{.spec.host}{"\n"}'
```

The last command prints the host name, for example `grafana-iyzitrace-grafana.apps.cluster.example.com`.

**Kubernetes with an Ingress controller:** choose a host name and create the Ingress (add TLS as
your cluster does it):

```bash
kubectl -n iyzitrace-grafana create ingress grafana --class=nginx --rule='grafana.example.com/*=grafana:3000'
```

Then tell Grafana its address: run the command of step 2 again with
`--set env.GF_SERVER_ROOT_URL=https://<grafana-host>` added (replace `<grafana-host>`). On OpenShift,
keep `-f values-openshift.yaml` in it.

## 4. Check it

Open `https://<grafana-host>` and log in as `admin` with the password from step 1. Then
Administration → Plugins: **IyziTrace** is enabled, and **Infinity** and **Plotly** are listed.

## 5. Tell the platform where Grafana is

The platform asks Grafana who its administrators are. In `values-poc.yaml` of the platform guide, set

```yaml
authService:
  grafanaUrl: http://grafana.iyzitrace-grafana.svc:3000
```

That address works from inside the cluster. If you already installed the platform, change it with
`helm upgrade` as in the platform guide, step 6.

Next: the plugin's setup wizard, in [docs/02-console-and-plugin.md](../../docs/02-console-and-plugin.md).
Use the platform's **Route address** (`https://<route-host>`) as the Platform URL, not the
in-cluster one: Grafana's server and your browser both use it.

## If the platform's Route uses a certificate Grafana does not trust

The plugin's queries go from Grafana's pod to the platform's Route. If the Route's certificate was
signed by the cluster's own certificate authority (the default on OpenShift Local and on many
on-premises clusters), the wizard or a data source test fails with
`x509: certificate signed by unknown authority`. Give Grafana the authority's certificate.

**OpenShift:** the default ingress authority is in the cluster. Run both commands in this folder:

```bash
oc -n openshift-config-managed get configmap default-ingress-cert -o jsonpath='{.data.ca-bundle\.crt}' > router-ca.crt
kubectl -n iyzitrace-grafana create configmap platform-ca --from-file=router-ca.crt
```

**Elsewhere:** put the authority's certificate (PEM) in a file called `router-ca.crt` and run the
second command only.

Then run the command of step 2 again with `-f values-ca.yaml` added after the other `-f` files; Grafana
restarts. Run the wizard's Verify again. A Route with a certificate from a public authority needs none
of this.

## If something goes wrong

| What you see | What to do |
|---|---|
| The pod is `ImagePullBackOff` | the cluster cannot reach Docker Hub (`grafana/grafana:13.1.1`), or its rate limit was hit: [docs/00-prerequisites.md](../../docs/00-prerequisites.md#images) |
| The pod restarted once (`RESTARTS 1`) and its first log has `failed to download plugin yesoreyeram-infinity-datasource` | expected when grafana.com is unreachable: installing the IyziTrace plugin makes Grafana look for its dependency, Infinity, on grafana.com, which fails once; Infinity is already installed from GitHub and the second start works |
| The log has `Failed to install plugin` for `grafana-lokiexplore-app`, `grafana-pyroscope-app`, `grafana-exploretraces-app` and others | harmless: Grafana tries to download its own default apps from grafana.com; nothing here uses them |
| IyziTrace is not in the plugin list | the pod could not download it: `kubectl -n iyzitrace-grafana logs deploy/grafana` and look for `antreklabs-iyzitrace-app`. It needs outbound HTTPS to github.com |
| The pod is not created; events say `unable to validate against any security context constraint` | OpenShift: `-f values-openshift.yaml` is missing in step 2 |
| The wizard or a data source test says `x509: certificate signed by unknown authority` | the section above |
| Agent Manager says `grafana_admin_required` or answers 403 right after you reinstalled Grafana | the platform remembers the old Grafana's signing keys: `kubectl -n iyzitrace rollout restart sts/auth-service` |

## Remove it

```bash
helm uninstall grafana -n iyzitrace-grafana
kubectl delete namespace iyzitrace-grafana
```

Grafana's data (its settings and the plugin's saved settings) is deleted with the namespace.
