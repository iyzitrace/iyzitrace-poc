# 2. Console and plugin

## Console: administrator, licence, department, keys

Open `https://<route-host>/console/` in a browser.

1. **Create the administrator.** A fresh install asks for one. If you ran the optional end-to-end
   test, log in with the `helm-e2e` user and the password from `~/iyzitrace-poc-state.json`
   instead.
2. **Install the licence**: License page, upload the `.lic` file.
3. **Create the customer's department** on the Tenants page, for example `poc`. A department's data
   can only be read with that department's keys.
4. **Create two keys for the department** on the API Keys page:
   - an **agent** key, for the collectors on the Linux machines;
   - a **reader** key, for the Grafana plugin.

   Each key is shown only once. Copy it somewhere safe right away.
5. **Turn on enforcement** on the API Keys page, under Access Control, for both "Agents (Ingest)"
   and "External Consumers (Query)". From now on, data without a key is refused.

## Plugin in Grafana

If you installed the kit's Grafana ([grafana/kubernetes](../grafana/kubernetes/README.md)), the plugin
is already there and enabled: log in as `admin` and go to step 2. In the customer's own Grafana:

1. Install the IyziTrace plugin and enable it: Administration → Plugins → IyziTrace.
2. Open IyziTrace. The setup wizard starts.
3. **Step 1, Platform & department.**
   - Platform URL: `https://<route-host>`
   - Reader key: the department's reader key
   - Press **Verify**. It shows the department's name and that the licence is valid. Press
     **Continue**.
4. **Step 2, Data sources.** Press **Configure data sources**. Four data sources are created
   (metrics, logs, traces, platform API). Press **Continue**.
5. **Step 3, Verification.** Press **Run checks**.
   - "Platform services are running" and "The reader key is accepted" must be green.
   - Until a collector sends data, it says "No data has arrived yet". That is expected: press
     **Skip**. The screens fill in once data arrives.

To add another department later: IyziTrace → Departments → Add department, with that department's
reader key.

Agent Manager and the AI settings work only for a **Grafana administrator**. The platform checks
that against the Grafana address in `values-poc.yaml`. If Agent Manager says
`grafana_admin_required`, that address is wrong or the cluster cannot reach it.

Next: [03-linux-collector.md](03-linux-collector.md).
