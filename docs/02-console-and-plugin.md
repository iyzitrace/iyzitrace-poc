# 2. Console and plugin

## 2.1 Console: administrator, licence, department, keys

Open `https://$GATEWAY/console/`.

1. **Administrator.** On a fresh install the console asks for one. (If you ran the licensed end-to-end test (platform install, step 7),
   log in with the `helm-e2e` user from the state file instead.)
2. **Licence.** Install the licence file.
3. **Department.** Create the customer's department, e.g. `poc`. A department is a tenant: its data
   is visible only with its own keys.
4. **Keys** for the department, two kinds:

   | Key | Role | Used by |
   |---|---|---|
   | agent key | `agent` (ingest) | the collectors on the Linux hosts (step 3) |
   | reader key | `reader` (query) | the Grafana plugin (step 2.2) |

   Copy both when they are shown; they are not shown again. Do not commit them anywhere.
5. **API-key enforcement**: turn on ingest and query enforcement, so anonymous traffic is refused.

## 2.2 Plugin in the customer Grafana

1. Install the IyziTrace app plugin in Grafana and enable it (Administration → Plugins → IyziTrace).
2. Open IyziTrace; the setup wizard starts.
3. **Step 1, Platform & department:**
   - Platform URL: `https://$GATEWAY`
   - Reader key: the department's reader key
   - **Verify**. It must show the department's name and a usable licence. **Continue**.
4. **Step 2, Data sources:** **Configure data sources**. Four datasources are created (metrics, logs,
   traces, platform API), all pointing at the gateway. **Continue**.
5. **Step 3, Verification:** **Run checks**.
   - "Platform services are running" and "The reader key is accepted" must pass.
   - Before any collector sends, "No data has arrived yet" is expected: use **Skip**. The screens
     fill in once data arrives.

More departments later: IyziTrace → Departments → Add department, with that department's reader key.

Agent Manager and the AI settings need a **Grafana Admin**. The platform verifies it against
`authService.grafanaUrl` (platform install, step 6); if that URL is wrong, Agent Manager answers
`grafana_admin_required`.
