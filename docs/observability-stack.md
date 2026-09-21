# Observability Stack Plan (Prometheus / Grafana / Loki)

Goal: add a lean observability stack to the k3s homelab.

**Milestone 1 (do first, land it fully):** Grafana + Prometheus + node metrics,
end to end and verified.

**Milestone 2 (distinct, separate step, only after M1 is stable):** add Loki +
Alloy for logs.

**Milestone 3:** app/service-level metrics, dashboards, and alerting.

## Decisions

- **Grafana exposure:** internal only, via Traefik `IngressRoute` at
  `grafana.cglavin50.com` (resolves on LAN via Pi-hole `customDnsEntries`). No
  Cloudflare tunnel.
- **Log collector:** Grafana Alloy (Promtail is deprecated/EOL as of 2025).
- **Loki mode:** single-binary / monolithic with filesystem storage (not the
  scalable object-store mode). Right-sized for a homelab.
- **Loki auth:** `auth_enabled: false` (multi-tenant `X-Scope-OrgID` auth
  disabled). Single-tenant homelab, no external exposure of the Loki API
  (only reachable via the Grafana datasource inside the cluster) — see
  [Auth model changelog](#auth-model-changelog) for the incident that
  surfaced this and the tradeoff.
- **Metrics:** `kube-prometheus-stack` (bundles Prometheus, Alertmanager,
  Grafana, node-exporter, kube-state-metrics).

## Environment notes / constraints

- 3× M920q (i5-8500T, 16 GB RAM, 256 GB NVMe), all k3s **servers** (HA embedded
  etcd), `10.0.0.50/60/70`. Keep resource requests/limits modest.
- Flux + Kustomize GitOps. Ordering via Flux `Kustomization` objects in
  `k8s/cluster.yaml`; each has SOPS decryption (`sops-age`).
- Install pattern: `HelmRepository` + `HelmRelease` per component, namespace
  declared inline, resource requests/limits always set.
- Storage: k3s default `local-path` (node-local, RWO PVCs).
- Secrets: SOPS/age `*.enc.yaml`; the `k8s/.*` creation rule already covers a
  new dir. **Secret name + keys in the file must exactly match the HelmRelease
  reference.**
- **k3s gotcha:** `kubeControllerManager`, `kubeScheduler`, `kubeProxy`,
  `kubeEtcd` scrape jobs aren't exposed the standard way → show as "down".
  Set them `.enabled: false` initially.
- **CRD caveat:** kube-prometheus-stack CRDs are large; Flux applies them fine
  via server-side apply.

## Target structure

```
k8s/monitoring/
  kustomization.yaml
  kube-prometheus-stack.yaml      # HelmRepository (prometheus-community) + HelmRelease
  grafana-admin-secret.enc.yaml   # SOPS
  loki.yaml                       # HelmRepository (grafana) + Loki HelmRelease   (Milestone 2)
  alloy.yaml                      # Grafana Alloy HelmRelease + config            (Milestone 2)
  servicemonitors/                # Milestone 3
```

Plus a `monitoring` Flux `Kustomization` block in `k8s/cluster.yaml`
(`path: ./k8s/monitoring`, `dependsOn: infra-controllers`, SOPS decryption,
`prune: true`).

---

## Milestone 1 — Grafana + Prometheus + node metrics

### Scaffolding

- [x] Create `k8s/monitoring/` directory + `kustomization.yaml`
- [x] Add `monitoring` Flux `Kustomization` to `k8s/cluster.yaml`
      (dependsOn `infra-controllers`, SOPS decryption, prune)
- [x] Declare `monitoring` namespace

### Metrics + Grafana

- [x] Add `prometheus-community` `HelmRepository`
- [x] Add `kube-prometheus-stack` `HelmRelease` (pin chart version)
- [x] Disable k3s-incompatible scrape jobs (kubeControllerManager,
      kubeScheduler, kubeProxy, kubeEtcd)
- [x] Prometheus: retention ~15d, PVC ~20 Gi, memory req/limit ~512Mi/1Gi
- [x] Create `grafana-admin-secret.enc.yaml` (SOPS) and reference via
      `grafana.admin.existingSecret` — verify name/keys match
- [x] Grafana: PVC ~2 Gi, datasource **sidecar enabled** (ready for Loki later)
- [x] Grafana Traefik `IngressRoute` at `grafana.cglavin50.com`
      (websecure, TLS default store in kube-system)
- [x] Add Pi-hole `customDnsEntry` for `grafana.cglavin50.com → 10.0.0.50`

### Verify (Milestone 1 done when all green)

- [x] `flux reconcile kustomization monitoring --with-source`
- [x] `kube-prometheus-stack` HelmRelease `Ready`
- [x] node-exporter running on all 3 nodes
- [x] Grafana reachable at `grafana.cglavin50.com`, login works
- [x] Prometheus targets green (node metrics flowing, no k3s "down" noise)

---

## Milestone 2 — Logs (Loki + Alloy)  *(separate step, after M1 is stable)*

- [x] Add `grafana` `HelmRepository`
- [x] Add Loki `HelmRelease` — single-binary mode, filesystem storage,
      PVC ~10 Gi, retention ~7d
- [x] Add Grafana Alloy `HelmRelease` (DaemonSet) — collect pod logs, push to Loki
- [x] Add Loki as a Grafana datasource via sidecar-labeled ConfigMap
- [x] Verify: logs visible in Grafana Explore

---

## Milestone 3 — App/service-level metrics + dashboards

- [ ] `ServiceMonitor` for cloudflared (already exposes `/metrics` on :8000)
- [ ] `ServiceMonitor`/`PodMonitor` for Traefik, Pi-hole, Minecraft, Vaultwarden (as desired)
- [ ] Provision per-app Grafana dashboards (labeled ConfigMaps)
- [ ] Optional: Alertmanager route to Discord (existing discord-bot / webhook)

---

## Auth model changelog

Audit trail for changes to auth/authz on any component in this stack. Append
an entry — never edit history — whenever an auth setting changes (enabling,
disabling, or reconfiguring authentication/authorization on Grafana,
Prometheus, Loki, or Alertmanager).

### 2026-09-20 — Loki `auth_enabled` set to `false`

- **Component:** Loki (`k8s/monitoring/loki.yaml`)
- **Change:** `loki.auth_enabled: true` (chart default, implicit) →
  `loki.auth_enabled: false` (explicit)
- **Commit:** `f40c6e7`
- **Trigger:** Grafana Explore returned `no org id` on every Loki query.
  Loki chart 6.55.0 defaults `auth_enabled: true`, which requires an
  `X-Scope-OrgID` header on every request for tenant isolation; the
  Grafana Loki datasource (sidecar-provisioned, `k8s/monitoring/loki.yaml`
  `loki-datasource` ConfigMap) does not send one.
- **Alternative considered:** keep `auth_enabled: true` and inject a static
  `X-Scope-OrgID` header via the Grafana datasource `jsonData`
  (`httpHeaderName1`/`httpHeaderValue1`). Rejected — adds a fake-tenant
  header for no isolation benefit in a single-tenant deployment; more
  moving parts to keep in sync for zero gain.
- **Risk accepted:** Loki API has no per-request authentication once
  `auth_enabled: false`. Mitigated by network exposure being unchanged:
  Loki is only reachable in-cluster (`http://loki:3100`, ClusterIP, no
  Ingress/IngressRoute); Grafana itself remains the only externally
  reachable surface, gated by the existing `grafana-admin-secret` login.
- **Reviewer follow-up:** if Loki is ever exposed outside the cluster
  (e.g. a second Grafana instance, direct LogCLI access from another
  host), re-enable `auth_enabled` and wire a real per-tenant header
  instead of reverting this decision silently.
