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
the file [values.yaml](values.yaml) from this folder; the commands assume you are in it. The pod needs outbound HTTPS to `github.com`
(and the cluster must pull `grafana/grafana:13.1.1`); it does not need `grafana.com`. Install Grafana **before the platform**: the platform needs Grafana's address in step 6
of its guide.

## 1. Create the namespace and the administrator's login

```bash
kubectl create namespace iyzitrace-grafana
kubectl -n iyzitrace-grafana create secret generic grafana-admin --from-literal=admin-user=admin --from-literal=admin-password='CHOOSE-A-PASSWORD'
```

Replace `CHOOSE-A-PASSWORD` with your own.

## 2. Edit values.yaml, then install

Open [values.yaml](values.yaml). Most of it stays as it is. A few places are marked `EDIT`; change
only the ones that apply to your cluster. "Uncomment" means: remove the `#` at the start of the line.

| If your cluster... | Do this in values.yaml |
|---|---|
| is OpenShift | uncomment the `securityContext` lines at the top, and set `initChownData.enabled` to `false` |
| may pull images only from your own registry | uncomment the two `registry`/`repository` lines under `image:` and the three `image:` lines under `initChownData:`, and replace `REGISTRY` with your registry's address in all of them (for example `registry.example.com`; the image keeps its original address after it: `registry.example.com/docker.io/grafana/grafana`) |
| reaches GitHub only through a proxy | uncomment the three proxy lines under `env:` and replace `PROXY-HOST:PORT` |
| has a Route signed by the cluster's own CA | do it later, in the last section of this guide |

On plain Kubernetes with direct internet access, change nothing. Then install, in this folder:

```bash
helm upgrade --install grafana \
  oci://ghcr.io/grafana-community/helm-charts/grafana --version 14.0.1 \
  -n iyzitrace-grafana -f values.yaml --wait --timeout 10m
```

The chart itself comes from `ghcr.io`: with your own registry, mirror it, or download it once with
`helm pull` and install from the file. The plugins come from GitHub, not from a registry.

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
`--set env.GF_SERVER_ROOT_URL=https://<grafana-host>` added (replace `<grafana-host>`).

## 4. Check it

Open `https://<grafana-host>` and log in as `admin` with the password from step 1. Then
Administration → Plugins: **IyziTrace** is enabled, and **Infinity** and **Plotly** are listed.

## 5. Tell the platform where Grafana is

The platform asks Grafana who its administrators are. In `values.yaml` of the [platform guide](../../platform/kubernetes/README.md), set

```yaml
authService:
  grafanaUrl: http://grafana.iyzitrace-grafana.svc:3000
```

That address works from inside the cluster. If you already installed the platform, change it with
`helm upgrade` as in the platform guide, step 6.

Next: the plugin's setup wizard, in [docs/02-console-and-plugin.md](../../docs/02-console-and-plugin.md).
Use the platform's **Route address** (`https://<route-host>`) as the Platform URL, not the
in-cluster one: Grafana's server and your browser both use it.

## If the cluster reaches GitHub through a proxy

Grafana downloads the plugins from GitHub when it starts. Behind a proxy, uncomment the proxy lines in
[values.yaml](values.yaml) (step 2) and run the install command again. The proxy and the firewall must
allow HTTPS to these hosts: `github.com`, and `release-assets.githubusercontent.com` and
`objects.githubusercontent.com`, because GitHub sends release downloads there. If the platform's Route
is reached without the proxy, add its host name to `NO_PROXY` in that file.

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

Then, in [values.yaml](values.yaml), uncomment the `SSL_CERT_DIR` line under `env:` and the
`extraConfigmapMounts` lines at the end, and run the install command of step 2 again; Grafana
restarts. Run the wizard's Verify again. A Route with a certificate from a public authority needs none
of this.

## Optional: let Grafana send more queries at once (HTTP/2)

Grafana's browser side sends at most five data queries at a time unless Grafana itself serves
HTTP/2. An IyziTrace overview screen sends 30 to 48, so with a lot of data the rest wait in the
browser. A Route or Ingress that speaks HTTP/2 to the browser does not lift this limit; only
Grafana serving HTTP/2 does. On a platform holding about 11,000 histogram series and 31 days of
history, with Thanos Query allowed 8 queries at a time, it opened the 7- and 30-day overview
screens about 8% faster.

The kit does not set it, because it changes three things:

1. Grafana gets a certificate and serves it itself: `grafana.ini` `server.protocol: h2` with
   `server.cert_file` and `server.cert_key` from a mounted Secret.
2. The Route hands TLS to Grafana (`reencrypt` or `passthrough`) instead of ending it (`edge`).
3. The platform reaches Grafana over HTTPS (`authService.grafanaUrl: https://...` in step 5) and
   trusts that certificate.

## If something goes wrong

| What you see | What to do |
|---|---|
| The pod is `ImagePullBackOff` | the cluster cannot reach Docker Hub (`grafana/grafana:13.1.1`), or its rate limit was hit; or your registry does not have the image under the address the registry lines of values.yaml build: [docs/00-prerequisites.md](../../docs/00-prerequisites.md#images) |
| The pod restarted once (`RESTARTS 1`) and its first log has `failed to download plugin yesoreyeram-infinity-datasource` | expected when grafana.com is unreachable: installing the IyziTrace plugin makes Grafana look for its dependency, Infinity, on grafana.com, which fails once; Infinity is already installed from GitHub and the second start works |
| The log has `Failed to install plugin` for `grafana-lokiexplore-app`, `grafana-pyroscope-app`, `grafana-exploretraces-app` and others | harmless: Grafana tries to download its own default apps from grafana.com; nothing here uses them |
| IyziTrace is not in the plugin list | the pod could not download it: `kubectl -n iyzitrace-grafana logs deploy/grafana` and look for `antreklabs-iyzitrace-app`. It needs outbound HTTPS to github.com, and to the hosts GitHub redirects downloads to: see the proxy section above |
| The pod is not created; events say `unable to validate against any security context constraint` | OpenShift: the OpenShift edit of values.yaml (step 2) was not made |
| The wizard or a data source test says `x509: certificate signed by unknown authority` | the section above |
| Agent Manager says `grafana_admin_required` or answers 403 right after you reinstalled Grafana | the platform remembers the old Grafana's signing keys: `kubectl -n iyzitrace rollout restart sts/auth-service` |

## Remove it

```bash
helm uninstall grafana -n iyzitrace-grafana
kubectl delete namespace iyzitrace-grafana
```

Grafana's data (its settings and the plugin's saved settings) is deleted with the namespace.
