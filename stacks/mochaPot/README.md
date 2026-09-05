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
  `MOCHAPOT_RENDER_GID` (Jellyfin's Quick Sync group), `PERCOLATOR_LAN_IP`
  (Immich's cross-host DB/Redis), `DOMAIN`.
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
- `PERCOLATOR_LAN_IP` — must match `stacks/percolator/.env.local`'s own
  `PERCOLATOR_LAN_IP` exactly; Immich reaches its Postgres+VectorChord and
  shared valkey instance there directly over the LAN (Docker networks
  don't span hosts).
- `DOMAIN` — same real domain every other node's `.env.local` uses.

`ROASTERY_TAILNET_IP` (Immich's ML worker endpoint) is deliberately not in
`local.env.example` yet — roastery's GPU-accelerated ML worker isn't built.
Immich runs fine without it, it just skips ML inference until that exists.

## Bringing each app up

Bring every app up on its own published port first and confirm it's
healthy before touching mochaPot's own Traefik — see that app's own note
below for why.

### Jellyfin (media server)

```
sudo ./compose.sh jellyfin up -d
```

UI: `http://<mochaPot LAN IP>:8096`. No default credentials — first-run
setup wizard creates the admin account.

Before first bring-up, confirm `MOCHAPOT_RENDER_GID` is filled in
correctly (`getent group render | cut -d: -f3` on mochaPot) — device
passthrough (`/dev/dri/renderD128`) alone silently falls back to software
transcoding if the container's group membership doesn't also match; there
is no error, just slower transcodes. `/media` is currently a local bind
mount (`/srv/media`) as a stopgap — cellar's NFS export isn't set up yet
(see stacks/cellar/README.md's smb/ section); swap this once that exists.

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
sudo ./compose.sh immich up -d
```

UI: `http://<mochaPot LAN IP>:2283`. First visit creates the admin
account. Depends on percolator being up first — its Postgres
(VectorChord-enabled) and shared valkey instance (DB index 0) are reached
over the LAN via `PERCOLATOR_LAN_IP`, not container DNS, since Docker
networks don't span physical hosts. Confirm percolator's `ufw` rules allow
mochaPot's IP through on 5432/6379 (see stacks/percolator/README.md) before
expecting this to connect.

ML inference (`IMMICH_MACHINE_LEARNING_URL`) points at
`${ROASTERY_TAILNET_IP}:3003`, which doesn't exist yet — Immich works
without it, just without ML features (face recognition, smart search)
until roastery's ML worker is actually built.

### Vikunja (tasks)

```
sudo ./compose.sh vikunja up -d
```

UI: `http://<mochaPot LAN IP>:3456`. SQLite, not Postgres — a deliberate
deviation from Vikunja's own reference compose, per initiation.txt Section
18.6's decision to keep mochaPot's remaining apps off dedicated Postgres
instances at this household's 2-user scale. No default admin — register
the first account through the UI.

### n8n (automation)

```
sudo ./compose.sh n8n up -d
```

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

### Traefik — deliberately deferred

`traefik/docker-compose.yml` exists but is not part of this bring-up pass.
Per initiation.txt Section 18.6, mochaPot's own Traefik comes up last,
once every app above is confirmed healthy on its own published port.
Unlike percolator's Traefik, this one has no `providers.docker` — mochaPot's
apps don't share a Docker network with each other, so routing goes through
the file provider straight to each app's `localhost:<published-port>`.
`traefik/config/dynamic.yml.template` is currently a placeholder (exists
only so the bind mount has a real file — Docker would otherwise create a
directory at a missing bind-mount source). Write real `http.routers` /
`http.middlewares` entries — same ForwardAuth-to-sieve's-Authelia pattern
as `stacks/percolator/traefik/config/dynamic.yml.template` — once every
app above is confirmed working directly, not before.

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
   mochaPot first -- **this mechanism is unverified**, see
   `komodo-periphery/docker-compose.yml`'s own comment for the best-guess
   `scp` command.

Same outbound-only connection as every other node's Periphery (mochaPot ->
silo on port 9120, no inbound rule needed on mochaPot) — and the same
root-equivalent caveat: whoever controls Core on silo has root-equivalent
access to mochaPot once this is connected.

## Known gaps / things to double-check before relying on this

- The deploy-order guess in this file's intro is still unverified against
  the initiation doc.
- Every port above is what's written in each compose file, not yet
  cross-checked against a live `ss -tlnp` on real mochaPot hardware — the
  FreshRSS/Music-Assistant collision was caught by inspection, but nothing
  guarantees there isn't another one.
- `ROASTERY_TAILNET_IP` isn't wired into `local.env.example` yet — add it
  once roastery's Immich ML worker actually exists.
- Immich's cross-host reach into percolator's Postgres/valkey depends on
  percolator's `ufw` rules already allowing mochaPot's specific LAN IP
  through on 5432/6379 — confirm that's actually been applied there, not
  just documented.
- If mochaPot will run a Komodo Periphery agent (so silo's Komodo Core can
  manage it), see `stacks/_templates/komodo-periphery/docker-compose.yml`
  — copy it into an app subdirectory here and fill in its `REPLACE_ME`
  values. Not done as part of this build pass.
