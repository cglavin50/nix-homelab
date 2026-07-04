# Flux v2 Migration — Implementation Plan

Make sure to follow official [flux docs](https://fluxcd.io/flux/migration/flux-v1-migration/) for migration.

## Baseline (verified)
- Fresh 3-node k3s cluster: alpha (10.0.0.50), bravo (.60), charlie (.70) — all Ready, one etcd quorum.
- No Flux CRDs, no workloads. Clean slate.
- Fresh `kubeconfig.yaml` fetched from alpha (server rewritten to 10.0.0.50).
- Traefik ships with k3s (its CRDs — IngressRoute/TLSStore — are already present).

## Progress checklist

### Phase 0 — Branch + Bootstrap
- [x] `git checkout -b flux-v2-migration`
- [x] Write new tree (manifests + `cluster.yaml` + root `kustomization.yaml`); remove old scattered files
- [x] Commit + push branch
- [x] `flux bootstrap github … --path=k8s` against the branch
- [x] Create `sops-age` secret in `flux-system`
- [ ] `flux check` + controllers Ready

### Phase 1 — cert-manager (controller)
- [ ] Write `infrastructure/controllers/cert-manager.yaml`
- [ ] Reconcile `infra-controllers`
- [ ] Verify: 3 pods Ready + `cert-manager.io` CRDs present

### Phase 2 — cert-manager configs (issuer + cert)
- [ ] Write `infrastructure/configs/cert-manager.yaml` + `cloudflare-token.enc.yaml`
- [ ] Reconcile `infra-configs`
- [ ] Verify: ClusterIssuer Ready; `wildcard-cert` Ready; `wildcard-tls` secret exists

### Phase 3 — Traefik TLSStore
- [ ] Write `infrastructure/configs/traefik-tlsstore.yaml`
- [ ] Reconcile `infra-configs`
- [ ] Verify: `curl -vkI https://…` serves LE wildcard

### Phase 4 — cloudflared
- [ ] Write `infrastructure/configs/cloudflared.yaml`
- [ ] Reconcile `infra-configs` (pods pend on missing secret)
- [ ] `tofu apply` to create `cloudflared-token`
- [ ] Verify: pods Running; tunnel Healthy

### Phase 5 — pihole
- [ ] Write `infrastructure/configs/pihole.yaml` + `pihole-password.enc.yaml` (IP → 10.0.0.50)
- [ ] Reconcile `infra-configs`
- [ ] Verify: web UI up; `dig @10.0.0.50` resolves

### Phase 6 — vaultwarden
- [ ] Write `apps/vaultwarden.yaml` + `vaultwarden-secret.enc.yaml`
- [ ] Reconcile `apps`
- [ ] Verify: `vault.cglavin50.com` over TLS

### Phase 7 — discord-bot
- [ ] Write `apps/discord-bot.yaml` + `discord-bot-secret.enc.yaml`
- [ ] Reconcile `apps`
- [ ] Verify: bot online

### Phase 8 — minecraft + rcon
- [ ] Write `apps/minecraft.yaml` + `minecraft-rcon-secret.enc.yaml`
- [ ] Reconcile `apps`
- [ ] Verify: server joinable; `rcon.cglavin50.com` loads

### Cutover & wrap-up
- [ ] Delete legacy flat-sync remnants + old per-service files
- [ ] All `flux get kustomizations` Ready; `git status` clean
- [ ] Update README (bootstrap, cluster reset, Tailscale key rotation, kubeconfig refresh)
- [ ] Merge `flux-v2-migration` → `main`

## Target layout (clean/minimal — no clusters/ nesting)
```
k8s/
├── kustomization.yaml            # root sync: resources: [flux-system, cluster.yaml]
├── cluster.yaml                  # 3 Flux Kustomizations w/ dependsOn (only ordering logic)
├── flux-system/                  # bootstrap output (gotk-*), auto-generated
├── infrastructure/
│   ├── controllers/
│   │   └── cert-manager.yaml      # namespace + HelmRepository + HelmRelease
│   └── configs/
│       ├── cert-manager.yaml      # ClusterIssuer + wildcard Certificate
│       ├── cloudflare-token.enc.yaml
│       ├── traefik-tlsstore.yaml
│       ├── cloudflared.yaml       # namespace + deployment + service
│       ├── pihole.yaml            # namespace + repo + release + pvc + route + dns-svc
│       └── pihole-password.enc.yaml
└── apps/
    ├── vaultwarden.yaml           + vaultwarden-secret.enc.yaml
    ├── discord-bot.yaml           + discord-bot-secret.enc.yaml
    └── minecraft.yaml             + minecraft-rcon-secret.enc.yaml
```

**Conventions**
- One multi-doc YAML per service for non-secret resources; SOPS secrets stay separate `.enc.yaml`.
- No per-service `kustomization.yaml` — Flux auto-generates one for each Kustomization subpath.
- `cluster.yaml` holds the 3 ordering Kustomizations:
  1. `infra-controllers` → `./k8s/infrastructure/controllers`
  2. `infra-configs` → `./k8s/infrastructure/configs`  (dependsOn infra-controllers; healthChecks: cert-manager HelmRelease)
  3. `apps` → `./k8s/apps`  (dependsOn infra-configs)

## Fixes folded in
- HelmRepository `source.toolkit.fluxcd.io/v1beta2` → `v1` (pihole, minecraft).
- pihole `patchesStrategicMerge` → removed (PVC folded into Helm values `persistentVolumeClaim`).
- pihole stale `192.168.1.50` → `10.0.0.50` (customDnsEntries + LB externalIP).
- monitoring dropped.

## External bootstrap dependencies (GitOps can't self-provide)
1. **`sops-age`** secret in `flux-system` — created manually at bootstrap from cooper's admin age private key.
2. **`cloudflared-token`** secret in `cloudflared` ns — created by `tofu apply` (`kubernetes_secret_v1.cloudflare_credentials`). Namespace must exist first (Flux creates it), so cloudflared pods pend until `tofu apply` runs.

---

## Phase 0 — Branch + Bootstrap
1. `git checkout -b flux-v2-migration`
2. Write new tree (all manifests + cluster.yaml + root kustomization.yaml). Remove old scattered files.
3. Commit + push branch.
4. Bootstrap Flux against the branch:
   ```
   flux bootstrap github \
     --owner=cglavin50 --repository=nix-homelab \
     --branch=flux-v2-migration --personal --path=k8s
   ```
   (uses GITHUB_TOKEN from .env)
5. Create SOPS age secret so kustomize-controller can decrypt:
   ```
   kubectl create secret generic sops-age -n flux-system \
     --from-file=age.agekey=$HOME/.config/sops/age/keys.txt
   ```
6. Verify controllers: `flux check`, `kubectl -n flux-system get pods`.

**Note on branch:** working + bootstrapping on `flux-v2-migration` keeps `main` untouched until everything is green. When verified, fast-forward `main` to it (optionally re-bootstrap `--branch=main`, or just merge and keep syncing main).

---

## Phase 1 — cert-manager (controller)
- File: `infrastructure/controllers/cert-manager.yaml` = namespace + HelmRepository(jetstack, v1) + HelmRelease(v1.19.2, installCRDs:true, resource limits as today).
- Deploy: push commit → `flux reconcile kustomization infra-controllers --with-source`.
- **Verify:** `kubectl -n cert-manager get pods` (3 Ready: controller/webhook/cainjector); `kubectl get crd | grep cert-manager.io`.

## Phase 2 — cert-manager configs (issuer + cert)
- File: `infrastructure/configs/cert-manager.yaml` = ClusterIssuer(letsencrypt-prod, DNS-01 via cloudflare) + Certificate(wildcard-cert in kube-system, `*.cglavin50.com` + apex).
- File: `infrastructure/configs/cloudflare-token.enc.yaml` = SOPS secret `cloudflare-api-token` (api-token) in cert-manager ns.
- Deploy: push → `flux reconcile kustomization infra-configs --with-source`.
- **Verify:** `kubectl get clusterissuer` Ready; `kubectl -n kube-system get certificate wildcard-cert` → Ready=True (ACME DNS-01 solves; may take 1–3 min); `kubectl -n kube-system get secret wildcard-tls`.

## Phase 3 — Traefik TLSStore
- File: `infrastructure/configs/traefik-tlsstore.yaml` = TLSStore `default` in kube-system → `wildcard-tls`.
- Deploy: same infra-configs reconcile.
- **Verify:** `curl -vkI https://<any-host>.cglavin50.com` presents the LE wildcard cert (not Traefik default self-signed).

## Phase 4 — cloudflared
- File: `infrastructure/configs/cloudflared.yaml` = namespace + Deployment(cloudflared:2024.12.2, 2 replicas, TUNNEL_TOKEN from `cloudflared-token`) + Service(metrics).
- Deploy infra-configs → pods will be `CreateContainerConfigError`/pending (missing secret).
- Provision secret: `cd tofu && tofu apply` (creates `cloudflared-token` in the now-existing ns).
- **Verify:** `kubectl -n cloudflared get pods` Running; `kubectl -n cloudflared logs deploy/cloudflared` shows "Registered tunnel connection"; Cloudflare dashboard tunnel = Healthy.

## Phase 5 — pihole
- File: `infrastructure/configs/pihole.yaml` = namespace + HelmRepository(mojo2600, v1) + HelmRelease(pihole 2.*, adminPasswordSecret, **customDnsEntries → 10.0.0.50**, persistence PVC 10Gi folded into values, Recreate strategy) + IngressRoute(pihole.cglavin50.com) + LB DNS Service(**externalIP 10.0.0.50**).
- File: `infrastructure/configs/pihole-password.enc.yaml` = SOPS secret.
- **Verify:** `kubectl -n pihole get pods` Running; web UI at `https://pihole.cglavin50.com`; `dig @10.0.0.50 example.com` resolves.

## Phase 6 — vaultwarden
- Files: `apps/vaultwarden.yaml` (Deployment 1.35.3 + PVC 5Gi + Service + IngressRoute vault.cglavin50.com) + `apps/vaultwarden-secret.enc.yaml`.
- Deploy: push → `flux reconcile kustomization apps --with-source`.
- **Verify:** pod Running; `https://vault.cglavin50.com` loads over the wildcard TLS.

## Phase 7 — discord-bot
- Files: `apps/discord-bot.yaml` (Deployment) + `apps/discord-bot-secret.enc.yaml`.
- **Verify:** pod Running; `kubectl -n services logs deploy/discord-bot` shows bot connected; bot online in Discord.

## Phase 8 — minecraft + rcon
- Files: `apps/minecraft.yaml` (HelmRepository itzg v1 + HelmRelease minecraft 4.x LB + HelmRelease minecraft-rcon rcon-web-admin) + `apps/minecraft-rcon-secret.enc.yaml`.
- **Verify:** `kubectl -n gaming get pods` (server Ready after world gen); connect a client to the LB IP; `rcon.cglavin50.com` admin loads.

---

## Cutover & cleanup
- Delete legacy `flux-system/gotk-sync.yaml` flat-sync remnants and any old per-service `kustomization.yaml`/`namespace.yaml`/`source.yaml`/`release.yaml` files replaced by consolidated manifests.
- `git status` clean; all reconciliations green: `flux get kustomizations` all Ready.
- Merge `flux-v2-migration` → `main`.

## Rollback
- Each phase is an isolated commit; `git revert` + reconcile rolls a service back.
- Since it's a fresh cluster, worst case is re-`flux bootstrap` after fixing manifests. No production data at risk except vaultwarden/pihole PVCs (fresh, empty at migration time).

## README updates (end)
- Replace bootstrap section with `flux bootstrap github … --path=k8s` + the `sops-age` secret step.
- Add "Cluster reset" section (stop k3s → rm /var/lib/rancher/k3s /etc/rancher/k3s → start; start alpha first; all 3 nodes).
- Add "Rotating the Tailscale auth key" section (reusable key → `sops secrets/tailscale-auth.yaml` → colmena apply).
- Add "Refreshing kubeconfig after a reset" (scp k3s.yaml from alpha, rewrite 127.0.0.1→10.0.0.50).
