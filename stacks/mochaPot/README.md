# mochaPot

Media, automation, and personal-productivity node. Hardware confirmed ready
2026-09-03; this directory holds every app's `docker-compose.yml` plus
`generate-secrets.sh` wiring, written and verified the same day, staged for
first bring-up.

Deploy order note (still unconfirmed against the initiation doc's own
section for mochaPot, carried over from this file's earlier draft): treat
mochaPot's position relative to percolator/cellar/ristretto as inferred,
not settled fact, until checked there. It doesn't block bring-up of the
apps below.

## What's here

- `compose.sh` — wrapper so every app's docker-compose.yml sees the shared
  `.env.local` plus its own `secrets.env.local`. Copied verbatim from
  silo — nothing node-specific in the logic.
- `render-configs.sh` — renders `*.template` files into their real
  counterparts.
- `setup-secrets.sh` — first-time-setup script: creates `.env.local` from
  `local.env.example`, prompts for any `REPLACE_ME`, runs
  `generate-secrets.sh` then `render-configs.sh`.
- `generate-secrets.sh` — generates mochaPot's own secrets locally, right
  here on mochaPot, straight into each app's `secrets.env.local` — no
  encryption, no key, nothing committed to git. Wired 2026-09-03 for
  Vikunja (`VIKUNJA_SERVICE_SECRET`, random), n8n (`N8N_ENCRYPTION_KEY`,
  random, pinned — see n8n's own compose comment on why losing it breaks
  stored credentials), and Roundcube (`ROUNDCUBE_IMAP_HOST` /
  `ROUNDCUBE_SMTP_HOST`, prompted — real external mail-provider values,
  not something that can be randomly generated). Every other app on this
  node has no secrets of its own — first-run web setup wizards or, for
  Mealie, a documented default account (see that app's section below).
  Functionally tested in a throwaway copy: correct values generated on
  first run, confirmed idempotent (identical output, byte-for-byte, on a
  second run).
- `local.env.example` — copy to `.env.local` and fill in. Has grown past
  the original minimal stub as apps were added: `MOCHAPOT_LAN_IP`, `TZ`,
  `MOCHAPOT_RENDER_GID` (Jellyfin's Quick Sync group), `DOMAIN`.
  (`PERCOLATOR_LAN_IP` was here for Immich's cross-host DB/Redis; removed
  2026-09-05 once Immich's database layer moved onto this node itself.)
- `.gitignore` — same rules as every other node: `.env.local`,
  `*/secrets.env.local`, and rendered `*/config/*` (except tracked
  `.template` sources) are never committed.

## First-time setup on mochaPot

```
git pull
./setup-secrets.sh
```

Same one-command flow as every other node — see stacks/silo/README.md's
"First-time setup on silo" section for what this does step by step (the
script itself is identical). Then fill in `.env.local`'s `REPLACE_ME`
values by hand before first bring-up:

- `MOCHAPOT_LAN_IP` — this host's own LAN IP.
- `MOCHAPOT_RENDER_GID` — find it on mochaPot itself with
  `getent group render | cut -d: -f3`.
- `DOMAIN` — same real domain every other node's `.env.local` uses.

(`PERCOLATOR_LAN_IP` was removed 2026-09-05 — Immich's database layer
moved onto this node itself, see its own section below, so nothing here
needs percolator's LAN IP anymore.)

- `ROASTERY_TAILNET_IP` — roastery's GPU-accelerated ML worker now exists
  (`stacks/roastery/immich-ml/`, built 2026-09-05) but needs Headscale
  enrollment on roastery itself first — see that stack's own README for
  the walkthrough — before this has a real value to fill in. Immich runs
  fine without it, it just skips ML inference (face recognition, smart
  search) until it's filled in.

## Bringing each app up

Bring every app up on its own published port first and confirm it's
healthy before touching mochaPot's own Traefik — see that app's own note
below for why.

### Jellyfin — moved to roastery (2026-09-05)

**No longer built here.** Quick Sync transcoding struggled noticeably in
an earlier real deployment on percolator's same-generation iGPU — the
user's own report, and mochaPot's chip is the same 7th-gen family, so
that experience was judged likely to carry over rather than being
percolator-specific. Jellyfin now lives on roastery instead, using its
RTX 3080 for NVENC/NVDEC — see `stacks/roastery/README.md`'s Jellyfin
section and the runbook's 2026-09-05 entry for the full reasoning.
`stacks/mochaPot/jellyfin/docker-compose.yml` is left as a non-functional
stub (device-bridge tooling can't delete files) — run `git rm -r
stacks/mochaPot/jellyfin` to actually remove it. `MOCHAPOT_RENDER_GID` in
`local.env.example` is now unused by anything on this node; left in place
rather than removed in case a future mochaPot app needs Quick Sync for
something else.

### Music Assistant (audio player orchestration)

```
sudo ./compose.sh musicassistant up -d
```

UI: `http://<mochaPot LAN IP>:8095`. Runs with `network_mode: host`,
required for mDNS/UPnP player discovery and direct streaming to
Chromecast/AirPlay/Sonos/DLNA targets — same underlying reason as
percolator's Home Assistant. All target playback devices need to share a
flat network (no VLANs) for discovery to work.

### Immich (photos)

```
sudo mkdir -p /srv/data/immich /srv/data/postgres-immich
./compose.sh immich up -d
```

UI: `http://<mochaPot LAN IP>:2283`. First visit creates the admin
account. **Restructured 2026-09-05**: no longer depends on percolator at
all — its own Postgres (VectorChord-enabled, `postgres-immich`) and its
own dedicated Valkey instance now live colocated in this same
`immich/docker-compose.yml`, reached by container name on this file's own
default network. See the runbook's 2026-09-05 entry for why: percolator's
old shared 4-instance Postgres compose file caused a real port collision,
and rather than just patch that, Immich's whole database layer moved here
instead — trading a database port that used to be published across the
LAN for local storage growth on mochaPot instead (deliberate: easier to
grow this node's storage than to keep managing that exposure).

`PERCOLATOR_LAN_IP` is no longer needed for this — removed from
`local.env.example` 2026-09-05.

ML inference (`IMMICH_MACHINE_LEARNING_URL`) points at
`${ROASTERY_TAILNET_IP}:3003` — the worker itself now exists
(`stacks/roastery/immich-ml/`, built 2026-09-05), but two things still
have to happen before this actually connects: roastery needs to be
enrolled in the fleet's Headscale tailnet (manual, on roastery itself —
see its README), and this node's `.env.local` needs the real
`ROASTERY_TAILNET_IP` value. Until then Immich works fine without ML
features (face recognition, smart search); this isn't a broken fallback,
inference is just unconfigured.

### Vikunja (tasks)

```
sudo mkdir -p /srv/data/vikunja/db /srv/data/vikunja/files
sudo chown -R 1000:0 /srv/data/vikunja/db /srv/data/vikunja/files
sudo ./compose.sh vikunja up -d
```

**The `mkdir`+`chown` steps are required, not optional** — caught
2026-09-05 on a real bring-up: without them, Docker auto-creates the bind
mount as `root:root`, but the Vikunja image runs as a fixed non-root user
(`uid=1000, gid=0` — confirmed from the container's own error log), so it
can't write its file-storage test file and crash-loops with `permission
denied` forever. See the runbook's 2026-09-05 entry.

UI: `http://<mochaPot LAN IP>:3456`. SQLite, not Postgres — a deliberate
deviation from Vikunja's own reference compose, per initiation.txt Section
18.6's decision to keep mochaPot's remaining apps off dedicated Postgres
instances at this household's 2-user scale. No default admin — register
the first account through the UI.

### n8n (automation)

```
sudo mkdir -p /srv/data/n8n
sudo chown -R 1000:1000 /srv/data/n8n
sudo ./compose.sh n8n up -d
```

**The `mkdir`+`chown` steps are required, not optional** — same class of
bug as Vikunja's above, caught the same day: the official n8n image runs
as its `node` user, `uid/gid 1000:1000` (a well-documented n8n gotcha,
confirmed against n8n-io/n8n#1240), and fails outright
(`EACCES: permission denied, open '/home/node/.n8n/config'`) against a
root-owned bind mount. See the runbook's 2026-09-05 entry.

UI: `http://<mochaPot LAN IP>:5678`. No default credentials — first visit
sets up an owner account. `N8N_ENCRYPTION_KEY` is pinned (not left to
auto-generate) precisely so a container recreation with the same
`secrets.env.local` can always decrypt already-stored credentials —
regenerating it would brick every saved credential in the persisted
volume.

### FreshRSS (RSS reader)

```
sudo ./compose.sh freshrss up -d
```

UI: `http://<mochaPot LAN IP>:8090`. Note the non-standard port — FreshRSS
usually defaults closer to 8095, but Music Assistant's `network_mode: host`
on this same node binds that range directly on the host, so 8090 avoids
the collision. Web-based setup wizard on first load, no default
credentials. Double-check with `ss -tlnp` on mochaPot before bring-up
regardless — this port table hasn't been cross-checked against the real
host yet.

### Mealie (recipes)

```
sudo ./compose.sh mealie up -d
```

UI: `http://<mochaPot LAN IP>:9925`. Unlike the others, this image ships a
real default account — `changeme@example.com` / `MyPassword` — log in and
change the password immediately. SQLite is this image's default and
explicitly should not sit on network storage; `/srv/data` here is local
NVMe, so that's fine.

### Actual Budget (finances)

```
sudo ./compose.sh actualbudget up -d
```

UI: `http://<mochaPot LAN IP>:5006`. No forced password on first run — set
a password/passphrase through the web UI during initial setup, not via an
env var.

### Stirling PDF (PDF tools)

```
sudo ./compose.sh stirlingpdf up -d
```

UI: `http://<mochaPot LAN IP>:8080`. Login is on by default
(`SECURITY_ENABLELOGIN=true`) with a well-known default `admin`/`stirling`
account — change the password on first login. Pinned to `:latest`
deliberately, not this fleet's usual pinned-version discipline — Stirling
PDF has a meaningful CVE history (several SSRF/XSS CVEs, most recently
CVE-2026-33436) and processes untrusted PDFs, so staying current matters
more here than pin-stability. Revisit if that tradeoff ever feels wrong.

### Roundcube (webmail client)

```
sudo ./compose.sh roundcube up -d
```

UI: `http://<mochaPot LAN IP>:8091`. Purely a webmail client — this fleet
runs no mail server of its own, so `ROUNDCUBE_IMAP_HOST` /
`ROUNDCUBE_SMTP_HOST` have to point at a real external provider (Gmail,
Fastmail, whichever account this is actually for). `generate-secrets.sh`
prompts for these interactively since they can't be randomly generated;
re-run it once you have the real values, or edit
`roundcube/secrets.env.local` directly. No admin account — login is
per-user against whatever the configured IMAP server accepts.

### Traefik — real HTTPS, brought up 2026-09-06

Every app above (except jellyfin, moved to roastery 2026-09-05) was
confirmed healthy on its own published port first, per initiation.txt
Section 18.6's sequencing — this comes last.

Real HTTPS via Cloudflare DNS-01, same as every other node's Traefik/
Caddy instance — switched from the original plain-HTTP `command:` block
before this was brought up for real, same reasoning percolator's Traefik
needed: Authelia hard-requires an https/wss target before it'll issue a
session cookie for ForwardAuth, no config flag to relax it. Not actually
wired to Authelia yet here (see below), but doing this now avoids hitting
that wall later if it ever is turned on.

**Still no `providers.docker`** — mochaPot's apps don't share a Docker
network with each other, so `traefik.enable=true` labels wouldn't do
anything here even if added (there's no docker provider to read them).
Routing is entirely file-provider-based: `traefik/config/dynamic.yml.template`
has a hand-written `http.routers` + `http.services` pair for each app,
pointing at `${MOCHAPOT_LAN_IP}:<published-port>` — not container names,
since there's no shared network to reach them by name.

```sh
sudo mkdir -p /srv/data/traefik/letsencrypt
./compose.sh traefik up -d
```

**Before testing any hostname in a browser**, add mochaPot's nine
hostnames to sieve's `pihole-dns-bootstrap.sh` `HOST_TARGETS` (done
alongside this build, 2026-09-06) and run it on sieve with
`MOCHAPOT_LAN_IP` filled in:

```sh
# on sieve
./pihole-dns-bootstrap.sh --dry-run   # preview
./pihole-dns-bootstrap.sh             # apply
```

Skipping this is exactly the `DNS_PROBE_FINISHED_NXDOMAIN` detour
percolator hit on 2026-09-05 — a successfully issued cert proves Let's
Encrypt accepted DNS-01 zone-control proof, it does not create an actual
resolvable DNS record anywhere; that's Pi-hole's job, done by this script,
not by Traefik.

Hostnames, all `${DOMAIN}`-suffixed: `vikunja`, `n8n`, `freshrss`,
`mealie`, `actualbudget`, `stirlingpdf`, `roundcube`, `immich`,
`musicassistant`. Jellyfin deliberately excluded — it's on roastery now,
reachable directly by LAN IP, not routed through any Traefik.

**Authelia ForwardAuth gating — left off deliberately, not an oversight**,
same open call as percolator's three apps. The `authelia` middleware is
already defined in `dynamic.yml.template` (same direct-hop-to-sieve
pattern as percolator's copy) but not attached to any router yet. Most of
these apps already have their own login (Vikunja, n8n, Mealie, Stirling
PDF, Immich); Actual Budget and Music Assistant may not — worth deciding
per-app rather than blanket-applying ForwardAuth to all nine.

### komodo-periphery

Added 2026-09-04, so silo's Komodo Core can see and manage mochaPot's
containers too -- no Core/Mongo here, just the agent (see
`komodo-periphery/docker-compose.yml`'s own header comment for the full
architecture note, same pattern as cellar's/percolator's/sieve's own
copies of this file).

```sh
sudo mkdir -p /srv/data/komodo-periphery/keys
./compose.sh komodo-periphery up -d
```

**Two things need to be true before `up -d` actually connects, neither
automatic**:

1. `komodo-periphery/secrets.env.local`'s `PERIPHERY_ONBOARDING_KEY` needs
   a real value from silo's Komodo UI (Settings -> the onboarding/servers
   section).
2. `PERIPHERY_CORE_PUBLIC_KEYS` needs silo's `core.pub` copied onto
   mochaPot first -- confirmed working on cellar/percolator/sieve 2026-09-05 (all three now show up as Servers in silo's Komodo UI), though not yet tested on mochaPot specifically. See
   `komodo-periphery/docker-compose.yml`'s own comment for the `scp`
   command.

Same outbound-only connection as every other node's Periphery (mochaPot ->
silo on port 9120, no inbound rule needed on mochaPot) — and the same
root-equivalent caveat: whoever controls Core on silo has root-equivalent
access to mochaPot once this is connected.

### scrutiny-collector

Added 2026-09-05 -- Scrutiny's own "hub and spoke" multi-host pattern,
see `stacks/cellar/README.md`'s identical copy of this section for the
full explanation. Fill in the real disk path first:

```sh
lsblk -d -o NAME,TYPE,SIZE,MODEL
```

into `.env.local`'s `MOCHAPOT_DISK_DEVICE_NVME` (controller node
`/dev/nvme0`, not `/dev/nvme0n1`), then:

```sh
./compose.sh scrutiny-collector up -d
```

Same silo-side prerequisite as cellar's/percolator's copies: port 8080
republished on silo's `scrutiny` service (done 2026-09-05).

## Known gaps / things to double-check before relying on this

- The deploy-order guess in this file's intro is still unverified against
  the initiation doc.
- Every port above is what's written in each compose file, not yet
  cross-checked against a live `ss -tlnp` on real mochaPot hardware — the
  FreshRSS/Music-Assistant collision was caught by inspection, but nothing
  guarantees there isn't another one.
- `ROASTERY_TAILNET_IP` is now a real key in `local.env.example`
  (2026-09-05 — previously only referenced in a comment, never actually
  declared, caught while building roastery's ML worker for real) but
  still needs a real value: enroll roastery in Headscale first (see
  `stacks/roastery/README.md`), then fill this in.
- Immich's database layer (its own colocated Postgres+Valkey, see its
  section above) is new as of 2026-09-05 and hasn't been run against real
  hardware in this shape yet — first real test is whatever bring-up
  happens next. It no longer depends on percolator or any LAN-crossing
  `ufw` rule at all, which is the whole point of the move.
- mochaPot's own storage may need growing over time to comfortably hold
  Immich's database now that it's local here instead of on percolator's
  larger fast-storage pool — a deliberate, known tradeoff (see the
  runbook's 2026-09-05 entry), not an oversight.
- If mochaPot will run a Komodo Periphery agent (so silo's Komodo Core can
  manage it), see `stacks/_templates/komodo-periphery/docker-compose.yml`
  — copy it into an app subdirectory here and fill in its `REPLACE_ME`
  values. Not done as part of this build pass.
- Jellyfin moved off this node entirely (2026-09-05, see its own section
  above) — `stacks/mochaPot/jellyfin/` is a stub, not a working app.
  `initiation.txt`'s original Section 17 table and the `jellyfin`
  reference in `stacks/roastery/README.md`'s "What's here" are the two
  places that reflect this; nowhere else in this repo should still list
  Jellyfin as a mochaPot app going forward.
- Root-owned bind-mount crash loop (2026-09-05): Vikunja and n8n both hit
  this on first real bring-up (see their own sections above and the
  runbook's 2026-09-05 entry) — a fixed non-root-UID image against a
  Docker-auto-created `root:root` bind mount. Both are fixed now with an
  explicit `mkdir`+`chown` step. Mealie, FreshRSS, Actual Budget, Stirling
  PDF, and Roundcube were brought up the same session but NOT
  individually re-checked for the same failure mode — `sudo docker ps`
  showing them healthy (not restarting) is the quick check; their
  `docker-compose.yml` files don't yet have a preemptive `chown` step
  added, so if any of them also run as a fixed non-root user without a
  self-fixing entrypoint, they'd hit this too.
