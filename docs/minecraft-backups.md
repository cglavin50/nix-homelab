# Minecraft World Backups (MinIO + restic) — Implementation Plan

Goal: back up the live Minecraft world to self-hosted object storage, be able
to wipe `/data` and start a fresh world (as we did for the Paper→NeoForge
switch), and restore an older world later without losing it permanently.
Trigger backups manually at first; wire a Discord command as a follow-up.

**Status: planning only — nothing in this doc is deployed yet.**

## Decisions

- **Storage backend: self-hosted MinIO**, not a 3rd-party cloud bucket. User
  choice — avoids new cloud accounts/credentials. Tradeoff accepted: backups
  are not truly off-site (see [Risk](#risk--not-off-site) below).
- **Dedicated MinIO instance**, not reusing `loki-minio` (`k8s/monitoring/loki.yaml`).
  Reasons:
  - Loki's MinIO PVCs are 2× 5Gi (`export-0`/`export-1`), already sized only
    for log chunks — a modded world + backup history would contend for that
    same small pool.
  - Coupling backup availability to the observability stack's MinIO means a
    Loki storage incident also takes down Minecraft backup/restore. Keep
    blast radius separate.
  - Namespace/ownership stays clean: `gaming` owns its own storage instead of
    reaching into `monitoring`.
- **Backup tool: restic**, via the `mcbackup` sidecar already built into the
  `itzg/minecraft` Helm chart (`mcbackup.enabled`, currently `false` in
  `k8s/apps/minecraft.yaml`). Not `tar`/`rclone`:
  - Incremental + deduplicated — a Create world is large; restic only
    uploads changed blocks, not a full archive every run.
  - Encrypted at rest (`RESTIC_PASSWORD`).
  - Snapshots are tagged (`BACKUP_NAME` + `RESTIC_ADDITIONAL_TAGS`), so
    multiple distinct worlds can live in one repository and be restored
    independently by snapshot ID.
  - Chart already has sane retention defaults
    (`pruneResticRetention: --keep-daily 7 --keep-weekly 5 --keep-monthly 12 --keep-yearly 75`).
- **Trigger model: manual first, Discord command later.** No `CRON_SCHEDULE`/
  `BACKUP_INTERVAL` initially — every backup is deliberate (`backup now`
  exec, or the Job described in [Milestone 3](#milestone-3-discord-trigger-follow-up-separate-piece-of-work)).
  Revisit a standing schedule once backup size/duration is known from real
  usage.

## Risk — not off-site

MinIO on this cluster lives on the same 3 nodes (`alpha`/`bravo`/`charlie`)
as the Minecraft server itself (`k8s/monitoring/loki.yaml` → `local-path`
storage class → node-local disk). A full node failure, disk failure, or
accidental `local-path` PVC deletion can take out the live world **and**
its backups simultaneously. This is a deliberate scope reduction from the
original cloud-storage recommendation — acceptable for "undo a bad mod
install / switch worlds," **not** sufficient for disaster recovery. If that
changes, revisit a cloud (R2/B2/S3) `restic` target — the chart-side wiring
is identical, only `RESTIC_REPOSITORY`/credentials change.

## Environment notes

- Minecraft server: `k8s/apps/minecraft.yaml`, `gaming` namespace, PVC
  `minecraft-datadir` (`local-path`, nominally 10Gi — see prior note that
  the bound PVC is actually 1Gi due to chart-value drift; `local-path` has
  no enforced quota so this hasn't mattered in practice).
  RCON already enabled (`minecraftServer.rcon`, secret
  `minecraft-rcon-secret`) — `mcbackup` needs the same RCON credentials to
  flush/pause the world during backup.
- SOPS/age encryption already used for all secrets in this repo
  (`k8s/apps/minecraft-rcon-secret.enc.yaml` is the existing pattern to
  follow for new secrets).
- Flux + Kustomize GitOps — new manifests go in `k8s/apps/kustomization.yaml`
  (Minecraft lives there, not `k8s/monitoring/`).

## Target structure

```
k8s/apps/
  minecraft.yaml                    # add mcbackup.* block (existing file)
  minecraft-minio.yaml               # new: dedicated MinIO HelmRelease/StatefulSet for backups
  minecraft-minio-secret.enc.yaml    # new: SOPS, MinIO root creds
  minecraft-restic-secret.enc.yaml   # new: SOPS, RESTIC_REPOSITORY/PASSWORD + MinIO access key
  minecraft-backup-job.yaml          # new (Milestone 3): Job template for on-demand/triggered backup
```

---

## Milestone 1 — Dedicated MinIO for Minecraft backups

- [ ] Add a MinIO `HelmRelease` (reuse the `minio` chart already proven via
      Loki's `k8s/monitoring/loki.yaml`, or the official
      `minio/minio` chart) in `k8s/apps/minecraft-minio.yaml`, namespace
      `gaming`.
  - PVC sized for real headroom — nodes have ~200GB free (`charlie`
    confirmed at 200GB avail at time of writing); start at 20–30Gi, single
    drive (no erasure coding needed for a single-node homelab backup
    target — simplicity over durability here, since the whole point is a
    *secondary* copy, not a third storage layer to maintain).
  - `resources.requests`/`limits` modest (512Mi/1 CPU is plenty for an
    internal-only backup target with no public traffic).
- [ ] `minecraft-minio-secret.enc.yaml` (SOPS) — root user/password,
      following the `grafana-admin-secret.yaml` pattern (fully encrypted
      file, referenced via `rootUser`/`rootPassword` equivalent values keys
      per whichever chart is used).
- [ ] Create a dedicated bucket `minecraft-backups` and a **scoped MinIO
      access key** (not the root credentials) for restic to use — via `mc`
      one-off Job/exec against the new MinIO, or the chart's bucket
      provisioning hook if the chosen chart supports it. Scope the policy to
      that bucket only.
- [ ] Verify: `kubectl -n gaming get pods -l app=minecraft-minio` ready;
      bucket visible via MinIO console port-forward.

## Milestone 2 — Wire restic backups into the Minecraft server

- [ ] `minecraft-restic-secret.enc.yaml` (SOPS) — keys:
      `RESTIC_REPOSITORY` (`s3:http://minecraft-minio.gaming.svc.cluster.local:9000/minecraft-backups`),
      `RESTIC_PASSWORD` (new, random — this is the *encryption* password,
      losing it means losing the backups, store it in the password manager
      too, not just SOPS), `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` (the
      scoped key from Milestone 1).
- [ ] `k8s/apps/minecraft.yaml`: add to the `minecraft` `HelmRelease` values:
  ```yaml
  mcbackup:
    enabled: true
    backupMethod: restic
    backupInterval: 0          # on-demand only for now, see Decisions
    backupOnStartup: false     # don't surprise-backup an empty/fresh world on every pod roll
    pauseIfNoPlayers: "false"
    resticAdditionalTags: "mc_backups gaming"
    envFrom:
      - secretRef:
          name: minecraft-restic-secret
    resources:
      requests:
        memory: 256Mi
        cpu: 100m
      limits:
        memory: 512Mi
  ```
  `BACKUP_NAME` should be set per-world (see Milestone 4) so distinct worlds
  don't collide under the same restic "host"/name — the chart doesn't
  expose `BACKUP_NAME` directly, pass it via the same `envFrom`/secret or an
  additional `extraEnv` entry.
- [ ] Verify: `kubectl -n gaming exec deploy/minecraft -c mcbackup -- backup now`
      completes, `restic snapshots` (via a throwaway debug pod with the
      same env) shows the new snapshot.

## Milestone 3 — Discord trigger (follow-up, separate piece of work)

The existing `discord-bot` (`k8s/apps/discord-bot.yaml`,
`cglavin50/homelab-discord-bot:latest`) is a bot app built **outside this
repo** — its command-handling code isn't here, so this milestone is a
contract definition for whoever/whatever implements the bot-side command,
plus the cluster-side plumbing that command needs to call.

- [ ] Add a `ServiceAccount` + `Role` (namespace `gaming`, verbs
      `create`/`get`/`list` on `jobs`, scoped to a label like
      `app=minecraft-backup-trigger`) + `RoleBinding`, bound to the
      `discord-bot` deployment's pod (new `serviceAccountName`).
      `discord-bot` currently runs with the default SA and no RBAC — this
      is new, narrowly scoped (Jobs only, not pod exec/secrets/etc).
- [ ] `k8s/apps/minecraft-backup-job.yaml`: a `Job` template (not a
      `CronJob` — stays manual/triggered) that execs `backup now` against
      the running `mcbackup` sidecar, e.g. via `kubectl exec` from a
      lightweight `bitnami/kubectl`-style image, or by having the Job's
      container call the K8s exec subresource directly. Discord bot creates
      an instance of this Job (`kubectl create -f ... --dry-run=client ... | kubectl apply -f -`
      equivalent via the K8s API client library the bot already uses for
      Tailscale management) when the command fires.
  - Interface contract for the bot side: create a `Job` named
    `minecraft-backup-<timestamp>` from this template in namespace
    `gaming`; report success/failure back to the invoking Discord channel
    by watching the Job's `status.succeeded`/`status.failed`.
- [ ] Discord slash command (bot-repo side, not here): `/minecraft backup`
      → creates the Job. `/minecraft backups list` → optional, run
      `restic snapshots` via a similar Job and format the output.

## Milestone 4 — World switching (backup → wipe → restore)

Manual runbook (automate later if this becomes frequent):

**Back up current world before switching:**
```sh
kubectl -n gaming exec deploy/minecraft -c mcbackup -- backup now
```

**Start a fresh world** (same procedure used for the Paper→NeoForge
cutover):
```sh
POD=$(kubectl -n gaming get pods -l app=minecraft -o jsonpath='{.items[0].metadata.name}')
kubectl -n gaming exec "$POD" -- sh -c 'rm -rf /data/* /data/.* 2>/dev/null'
# then edit k8s/apps/minecraft.yaml (version/type/mods as needed), commit, push, reconcile
```

**Restore an older world later** (restic has no chart-provided restore
path — `mcbackup` only auto-restores for `tar`/`rsync`; restic restore is a
manual CLI step by design, since it needs you to pick *which* snapshot):
```sh
# 1. find the snapshot (run against a throwaway pod/Job with the same
#    RESTIC_* env as the mcbackup sidecar)
restic snapshots --tag <world-tag>

# 2. scale the server to 0 so nothing writes to /data during restore
kubectl -n gaming scale deploy/minecraft --replicas=0

# 3. wipe /data, then restore the chosen snapshot into it (via a debug pod
#    mounting the same minecraft-datadir PVC + the restic secret)
restic restore <snapshot-id> --target /data

# 4. scale back up
kubectl -n gaming scale deploy/minecraft --replicas=1
```

---

## Open follow-ups

- Fix the `minecraft-datadir` PVC size drift (bound at 1Gi vs the chart's
  declared 10Gi) noted during the Paper migration — unrelated to backups
  but worth cleaning up since a restore workflow will make people look at
  PVC sizing more closely.
- If backup/world-storage needs outgrow a single-node MinIO, or the
  "not off-site" risk becomes unacceptable, swap `RESTIC_REPOSITORY` to a
  cloud S3-compatible endpoint (R2/B2/S3) — no architecture change, just
  different credentials in `minecraft-restic-secret.enc.yaml`.
