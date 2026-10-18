#!/usr/bin/env python3
# Copied from antreklabs/iyzitrace-observability-platform scripts/test-k8s-e2e.py at c44dd8f (AGPL-3.0-only).
"""Exercise an installed helm/platform release through nginx; keep credentials local.

Use a disposable cluster. Seed bootstraps its console, creates two departments and
enables API-key enforcement. Refresh sends new probes; verify reads stored ones.
The state file contains credentials and must never be committed.
"""

import argparse
import json
import os
from pathlib import Path
import secrets
import time
import urllib.error
import urllib.parse
import urllib.request


def request(base, path, method="GET", body=None, token=None, headers=None):
    supplied = {"Content-Type": "application/json", **(headers or {})}
    if token:
        supplied["Authorization"] = "Bearer " + token
    req = urllib.request.Request(
        base + path, method=method, headers=supplied,
        data=None if body is None else json.dumps(body).encode(),
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            code, raw = response.status, response.read().decode()
    except urllib.error.HTTPError as error:
        code, raw = error.code, error.read().decode()
    try:
        return code, json.loads(raw)
    except ValueError:
        return code, raw


def check(condition, message):
    if not condition:
        raise RuntimeError(message)
    print("PASS:", message, flush=True)


def attr(key, value):
    return {"key": key, "value": {"stringValue": value}}


def save_state(path, state):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, "w") as handle:
        json.dump(state, handle)


def probe(base, state, tenant, marker):
    now = time.time_ns()
    attributes = [attr("service.namespace", state["namespace"])]
    spans = []
    for name, kind, span_id, parent in [
        ("e2e-caller", 3, "0000000000000001", None),
        ("e2e-target", 2, "0000000000000002", "0000000000000001"),
    ]:
        span = {
            "traceId": tenant["trace"], "spanId": span_id,
            "name": "GET /helm-e2e", "kind": kind,
            "startTimeUnixNano": str(now), "endTimeUnixNano": str(now + 10000000),
            "attributes": [attr("http.request.method", "GET"), attr("http.route", "/helm-e2e"),
                           attr("server.address", "e2e-target"), attr("e2e.marker", marker)],
        }
        if parent:
            span["parentSpanId"] = parent
        spans.append({"resource": {"attributes": attributes + [attr("service.name", name)]},
                      "scopeSpans": [{"spans": [span]}]})
    resource = {"attributes": attributes + [attr("service.name", "e2e-target")]}
    payloads = {
        "traces": {"resourceSpans": spans},
        "logs": {"resourceLogs": [{"resource": resource, "scopeLogs": [{"logRecords": [{
            "timeUnixNano": str(now), "body": {"stringValue": marker}, "severityText": "INFO",
        }]}]}]},
        "metrics": {"resourceMetrics": [{"resource": resource, "scopeMetrics": [{"metrics": [{
            "name": "iyzitrace_k8s_e2e_probe", "gauge": {"dataPoints": [{
                "asDouble": tenant["value"], "timeUnixNano": str(now),
                "attributes": [attr("e2e_run", state["run"])],
            }]},
        }]}]}]},
    }
    for signal, body in payloads.items():
        code, _ = request(base, "/ingest/otlp/v1/" + signal, "POST", body, tenant["key"])
        check(code == 200, marker + ": nginx accepts " + signal)


def seed(args):
    base = args.base_url
    license_token = Path(args.license_file).read_text().strip()
    check(bool(license_token), "test license file is present")
    code, config = request(base, "/console/auth/config")
    check(code == 200 and not config["setup_complete"], "fresh console is ready for bootstrap")
    check(request(base, "/console/auth/keys")[0] == 401, "anonymous key administration is denied")
    check(request(base, "/query/v1/metrics/api/v1/query?query=vector(1)")[0] == 402,
          "queries without an installed license are denied")
    state = {"run": secrets.token_hex(6), "username": "helm-e2e", "password": secrets.token_urlsafe(24)}
    state["namespace"] = "helm-e2e-" + state["run"]
    check(request(base, "/console/auth/setup", "POST", state)[0] == 200, "console bootstrap succeeds")
    code, login = request(base, "/console/auth/login", "POST", state)
    check(code == 200, "console login succeeds")
    state["admin"] = login["token"]
    save_state(args.state_file, state)
    check(request(base, "/api/v1/platform/license/config", "POST", {"token": license_token}, state["admin"])[0] == 200,
          "license installs through the public gateway")
    state["tenants"] = []
    for side, value in [("a", 11), ("b", 22)]:
        slug = "helm-e2e-" + side + "-" + state["run"]
        code, tenant = request(base, "/console/auth/tenants", "POST",
                               {"name": slug, "slug": slug, "keys": "combined"}, state["admin"])
        check(code == 201, "department " + side + " and its credential are created")
        state["tenants"].append({"slug": slug, "key": tenant["keys"][0]["raw_key"],
                                  "trace": secrets.token_hex(16), "value": value, "marker": slug})
        save_state(args.state_file, state)
    check(request(base, "/console/auth/config", "POST", {"agent_api_key": True, "external_api_key": True},
                  state["admin"])[0] == 200, "ingest and query API-key enforcement is enabled")
    check(request(base, "/ingest/otlp/v1/traces", "POST", {"resourceSpans": []})[0] == 401,
          "anonymous ingestion is denied")
    check(request(base, "/query/v1/metrics/api/v1/query?query=vector(1)")[0] == 401,
          "anonymous queries are denied")
    state["started"] = int(time.time())
    for tenant in state["tenants"]:
        probe(base, state, tenant, tenant["marker"])
    save_state(args.state_file, state)
    verify(args, state, inventory=True)


def wait_for(label, action, predicate, timeout=180):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        last = action()
        if predicate(last):
            check(True, label)
            return last
        time.sleep(3)
    raise RuntimeError(label + " timed out (last HTTP status: " + str(last[0]) + ")")


def query(base, path, params, key):
    return request(base, path + "?" + urllib.parse.urlencode(params), token=key)


def verify(args, state=None, inventory=False):
    state = state or json.loads(Path(args.state_file).read_text())
    base = args.base_url
    check(request(base, "/healthz")[0] == 200, "nginx is healthy")
    code, login = request(base, "/console/auth/login", "POST",
                          {"username": state["username"], "password": state["password"]})
    check(code == 200, "console credentials persist")
    for tenant in state["tenants"]:
        slug, key = tenant["slug"], tenant["key"]
        code, identity = request(base, "/api/v1/platform/auth/whoami", token=key)
        check(code == 200 and identity.get("tenant", {}).get("slug") == slug, slug + ": API key resolves its tenant")
        metric = 'last_over_time(iyzitrace_k8s_e2e_probe{e2e_run="' + state["run"] + '"}[24h])'
        wait_for(slug + ": metrics round-trip and tenant isolation", lambda: query(
            base, "/query/v1/metrics/api/v1/query", {"query": metric}, key),
            lambda r: r[0] == 200 and len(r[1].get("data", {}).get("result", [])) == 1
            and float(r[1]["data"]["result"][0]["value"][1]) == tenant["value"])
        wait_for(slug + ": trace round-trip", lambda: request(
            base, "/query/v1/traces/api/v2/traces/" + tenant["trace"], token=key),
            lambda r: r[0] == 200 and tenant["marker"] in json.dumps(r[1]))
        wait_for(slug + ": logs round-trip", lambda: query(
            base, "/query/v1/logs/loki/api/v1/query_range",
            {"query": '{service_name="e2e-target"} |= "' + tenant["marker"] + '"',
             "start": str((state["started"] - 30) * 1000000000)}, key),
            lambda r: r[0] == 200 and bool(r[1].get("data", {}).get("result")))
        other = next(t for t in state["tenants"] if t["slug"] != slug)
        code, trace = request(base, "/query/v1/traces/api/v2/traces/" + other["trace"], token=key)
        check(code in (200, 404) and other["marker"] not in json.dumps(trace), slug + ": other tenant trace is hidden")
        code, logs = query(base, "/query/v1/logs/loki/api/v1/query_range", {
            "query": '{service_name="e2e-target"} |= "' + other["marker"] + '"',
            "start": str((state["started"] - 30) * 1000000000)}, key)
        check(code == 200 and not logs.get("data", {}).get("result"), slug + ": other tenant logs are hidden")
        if inventory:
            # Not service.traced: a writer batch keeps each entity's last sighting, so a
            # one-shot probe whose metrics follow its span may never store the flag.
            _, entities = wait_for(slug + ": inventory receives the service", lambda: query(
                base, "/inventory/api/v1/entities", {"type": "service", "limit": 1000}, key),
                lambda r: r[0] == 200 and any(e.get("attrs", {}).get("service.name") == "e2e-target"
                    and e.get("tenant") == slug for e in r[1].get("entities", [])))
            check(all(e.get("tenant") == slug for e in entities["entities"]),
                  slug + ": inventory returns only its tenant")
        wait_for(slug + ": service graph is derived from the paired spans", lambda: query(
            base, "/query/v1/metrics/api/v1/query", {"query":
                'last_over_time(iyzitrace_service_graph_request_total{client="e2e-caller",server="e2e-target",'
                'client_service_namespace="' + state["namespace"] + '",server_service_namespace="'
                + state["namespace"] + '"}[24h])'}, key),
            lambda r: r[0] == 200 and bool(r[1].get("data", {}).get("result")))
    check(request(base, "/api/v1/platform/ai/openai", "POST", {})[0] == 404,
          "internal-only AI routes stay hidden at nginx")
    print("PASS: installed Kubernetes platform end-to-end checks", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=["seed", "refresh", "verify"])
    parser.add_argument("--base-url", required=True, help="nginx URL; use a port-forward to an isolated test release")
    parser.add_argument("--state-file", required=True, help="private credential file outside the repository")
    parser.add_argument("--license-file", help="valid test license; required for seed")
    args = parser.parse_args()
    args.base_url = args.base_url.rstrip("/")
    if args.phase == "seed" and not args.license_file:
        parser.error("seed requires --license-file")
    if args.phase == "seed" and Path(args.state_file).exists():
        parser.error("state file already exists; use refresh/verify or choose a new file")
    if args.phase == "seed":
        seed(args)
    elif args.phase == "refresh":
        state = json.loads(Path(args.state_file).read_text())
        state["started"] = int(time.time())
        for tenant in state["tenants"]:
            tenant["trace"] = secrets.token_hex(16)
            probe(args.base_url, state, tenant, tenant["marker"])
        save_state(args.state_file, state)
        verify(args, state, inventory=True)
    else:
        verify(args)


if __name__ == "__main__":
    main()
