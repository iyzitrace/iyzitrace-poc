# Images from your own registry

When the cluster may pull images only from the organisation's own registry, every image the
PoC installs must start with that registry's address. Mirror each image there under its
original address, with the registry in front:

| Original | In your registry |
|---|---|
| `docker.io/grafana/loki:3.7.8` | `REGISTRY/docker.io/grafana/loki:3.7.8` |
| `ghcr.io/iyzitrace/auth-service:<tag>` | `REGISTRY/ghcr.io/iyzitrace/auth-service:<tag>` |
| `quay.io/prometheus/alertmanager:v0.34.0` | `REGISTRY/quay.io/prometheus/alertmanager:v0.34.0` |
| `nginx:1.30.4-alpine` (short name) | `REGISTRY/docker.io/library/nginx:1.30.4-alpine` |
| `otel/opentelemetry-collector-contrib:0.159.0` | `REGISTRY/docker.io/otel/opentelemetry-collector-contrib:0.159.0` |

`REGISTRY` is your registry's address, for example `registry.example.com`. The full list of
images is in [docs/00-prerequisites.md](../docs/00-prerequisites.md#images). The tags stay as
they are.

## The files

One file per Helm chart. In each, replace `REGISTRY` with your registry's address (every
occurrence), then add it as one more `-f` on that chart's install command:

| File | Chart |
|---|---|
| [values-operators.yaml](values-operators.yaml) | the operators |
| [values-storage.yaml](values-storage.yaml) | the object store |
| [values-platform.yaml](values-platform.yaml) | the platform |
| [values-grafana.yaml](values-grafana.yaml) | Grafana ([grafana/kubernetes](../grafana/kubernetes/README.md)) |

For example, the platform install of [platform/kubernetes/README.md](../platform/kubernetes/README.md),
step 6, becomes:

```bash
helm upgrade --install iyzitrace \
  oci://ghcr.io/iyzitrace/charts/iyzitrace-platform --version 1.3.1-dev.b4f7494 \
  -n iyzitrace -f values-poc.yaml -f ../../registry/values-platform.yaml --wait --timeout 20m
```

The charts themselves come from `oci://ghcr.io/iyzitrace/charts` (and Grafana's from
`oci://ghcr.io/grafana-community/helm-charts`); mirror them too, or download them once with
`helm pull` and install from the files.

## cert-manager

The cert-manager manifest has four images, all under `quay.io/jetstack`. Put your registry in
front of them as you apply it:

```bash
curl -sL https://github.com/cert-manager/cert-manager/releases/download/v1.17.2/cert-manager.yaml | sed 's#quay.io/jetstack#REGISTRY/quay.io/jetstack#g' | kubectl apply -f -
```

(Replace `REGISTRY` here as well.)

## What is not covered

- A registry that needs a login. On OpenShift the cluster-wide pull secret
  (Administration → Cluster Settings → Configuration → global pull secret) usually already has
  it. Otherwise each chart's own pull-secret setting and a secret in each namespace are needed.
- The platform's `values-platform.yaml` repeats the init containers that wait for their bucket,
  because Helm replaces a list as a whole. If a new platform chart changes them, copy them again
  from the chart's `values.yaml` (`x-wait-for-bucket`).
