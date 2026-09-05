# percolator

Stack directory scaffolded 2026-09-01, ahead of percolator actually existing
as hardware/a VM. Real build started 2026-09-03. Deploy order per
initiation.txt Section 0.4/18: sieve → silo → cellar → percolator →
mochaPot → ristretto — percolator's own build (this directory) started
before cellar's, since cellar's original reason for going first (Vaultwarden
available early for secrets storage) stopped applying once the fleet dropped
SOPS+age for local generation 2026-09-02 — Section 19.3 already says
Vaultwarden "was never in the critical path for container secrets either
way." cellar's remaining role (NFS archive/cold-storage backing for
Paperless-ngx/Nextcloud/Immich) is a soft, deferred dependency, not a
blocker for what's below.

**Deployment mechanism differs from sieve/silo, per Section 19.2**: Komodo
(live on silo) is the deploy engine for every stack from cellar onward —
`./compose.sh` here is for local dev/testing against percolator directly,
not the intended production bring-up path once Komodo's periphery agent is
configured for this node (not done yet). Compose files are still written
and committed the exact same way regardless.

## Cross-app networking (new as of this node)

**Restructured 2026-09-05** — each app now owns its own Postgres,
colocated in its own compose file (`homeassistant/`, `nextcloud/`,
`paperless/` each define their app service AND their own dedicated
`postgres-<app>` service side by side); there's no more shared
`postgres/` directory bringing up all four at once. See the runbook's
2026-09-05 entry for why: that shared layout let two unrelated apps'
databases collide on the same host port without anyone noticing.

What `percolator_net` (a shared external Docker network, created
idempotently by `./compose.sh` before every call — see that script's own
header comment) is STILL for: Paperless-ngx and Nextcloud both need to
reach `valkey/`'s shared instance, which remains its own separate
compose project. Nothing else needs it anymore — each app's own database
is colocated in the same file/project as the app itself, reached over
that file's own default network, with no shared network involved at all.

## Bringing each app up

### postgres — no longer a section of its own (moved 2026-09-05)

There's no `postgres/` directory anymore. Every app below (`homeassistant`,
`nextcloud`, `paperless`) brings its own dedicated Postgres up together
with itself, in the same `./compose.sh <app> up -d` call — see each app's
own section below for its `mkdir`/bring-up commands, which now include its
database's data directory too.

`postgres-immich` isn't here at all anymore — Immich's whole database
layer moved to mochaPot, colocated with `immich-server` itself (see
`stacks/mochaPot/README.md`'s own Immich section, and the runbook's
2026-09-05 entry for the full reasoning: a real port collision between
this file's old `postgres-immich` and `postgres-homeassistant`, plus a
deliberate call that growing mochaPot's own storage beats continuing to
publish database ports across the LAN for a cross-host setup).

Every remaining Postgres instance on percolator (`postgres-homeassistant`,
`postgres-nextcloud`, `postgres-paperless`) is now fully private to its
own app's compose file — none of them publish a host port to the LAN, and
none of them need `percolator_net` either (that's still used, but only by
the *apps* reaching the shared `valkey/` instance — see below). Data
stays at `/srv/data/postgres-<app>` each, local disk, same as before.

### valkey

**Valkey, not Redis** — confirmed 2026-09-03: Redis's 2024 license change
moved it off OSI-approved open source, and the self-hosting ecosystem has
shifted accordingly. Not a guess — Paperless-ngx's own official Postgres
reference compose uses `valkey/valkey:9-alpine` as its broker. One shared
instance for percolator's SAME-HOST apps, namespaced by Valkey's built-in
logical DB indexes rather than one container per consumer:

- DB 1 — paperless-ngx (`PAPERLESS_REDIS=redis://valkey:6379/1`)
- DB 2 — reserved for nextcloud once it's actually wired up (recommended
  by Nextcloud's own docs, not required)

DB 0 (Immich's former slot) is free — Immich got its own dedicated valkey
instance on mochaPot as of 2026-09-05 (see `### postgres` above), so this
one never needs to leave percolator anymore.

No password configured, no volume (cache/queue only, ephemeral is correct
for both current consumers) — matches this fleet's LAN-trust posture for
same-host, `percolator_net`-only services.

```sh
./compose.sh valkey up -d
```

No `ufw` rule needed anymore — as of 2026-09-05 this no longer publishes
a host port at all (that was only ever for Immich's cross-host reach;
removed along with `postgres-immich`, see the runbook's 2026-09-05
entry). Nothing outside `percolator_net` can reach this.

### homeassistant

`network_mode: host`, required per Home Assistant's own Cast integration
docs (mDNS discovery doesn't work otherwise) — confirmed 2026-09-03, not
assumed. Consequence: it can't reach `postgres-homeassistant` via
container DNS the way the other apps reach theirs, since host networking
bypasses Docker's embedded DNS entirely — that instance is published to
`127.0.0.1:5432` instead, loopback only. `postgres-homeassistant` is now
colocated in THIS file as of 2026-09-05 (see this file's own
`docker-compose.yml` for the full story on why it briefly lived on port
5433 and is now safely back on 5432).

```sh
sudo mkdir -p /srv/data/homeassistant /srv/data/postgres-homeassistant
./compose.sh homeassistant up -d
```

Brings up both `homeassistant` and its own `postgres-homeassistant`
together — no separate `postgres` step anymore. No default credentials —
onboarding wizard at `http://<PERCOLATOR_LAN_IP>:8123`.
**The Postgres recorder needs a manual step after first boot** —
confirmed there's no compose-level way to configure this, it's
`configuration.yaml`-only. Add to `/srv/data/homeassistant/configuration.yaml`:

```yaml
recorder:
  db_url: postgresql://homeassistant:<HA_DB_PASSWORD from ./secrets.env.local>@127.0.0.1:5432/homeassistant
```

then restart. Runs fine on its own default SQLite until you do this —
not a blocker to bringing HA up, just to getting the recorder onto
Postgres.

### nextcloud

```sh
sudo mkdir -p /srv/data/nextcloud /srv/data/postgres-nextcloud
./compose.sh nextcloud up -d
```

Brings up both `nextcloud` and its own `postgres-nextcloud` together —
no separate `postgres` step anymore.

Admin login: `barista` / `NEXTCLOUD_ADMIN_PASSWORD` from
`nextcloud/secrets.env.local`. Uses its own colocated `postgres-nextcloud`
(moved into this file 2026-09-05, no `percolator_net` needed for that
anymore) and `../valkey`'s shared instance (DB 2) via `percolator_net`.
**Known gap**: `trusted_proxies`/
`overwriteprotocol`/`overwritehost` (`config.php` keys, don't exist until
after first install) aren't set yet — required once this is actually
routed through `traefik/`, confirmed via Nextcloud's own reverse-proxy
docs the symptom otherwise is redirect loops or "not accessible" errors.
Set these once traefik/ is verified working, not before.

### paperless

```sh
sudo mkdir -p /srv/data/paperless/{data,media,export,consume} /srv/data/postgres-paperless
./compose.sh paperless up -d
```

Brings up both `paperless` and its own `postgres-paperless` together —
no separate `postgres` step anymore.

Admin login: `barista` / `PAPERLESS_ADMIN_PASSWORD` from
`paperless/secrets.env.local`. Uses its own colocated `postgres-paperless`
(moved into this file 2026-09-05, no `percolator_net` needed for that
anymore) and `../valkey`'s shared instance (DB 1). **Known gaps, not built
here**: gotenberg/tika (non-PDF document
conversion) aren't included — PDF-only consumption works without them.
Non-English OCR needs tesseract language packs not bundled in this base
image.

### traefik

Internal-only reverse proxy for percolator's own apps — not sieve's
tunnel-facing instance. `providers.docker.exposedByDefault=false` —
confirmed this is the right default for a homelab host running several
unrelated stacks on `percolator_net`; apps opt in per-container with
`traefik.enable=true`, which all three (`nextcloud`, `paperless`,
`homeassistant`) now have as of 2026-09-05, added once Traefik itself was
confirmed healthy (no errors on startup — but also nothing to actually
test DNS-01 cert issuance against until at least one router existed; see
the runbook's 2026-09-05 entry). All three use
`traefik.http.routers.<name>.entrypoints=websecure`, not `web` — see
below for why. `homeassistant`'s label set is different from the other
two's: it's the one app here on `network_mode: host`, so it has no
container-network IP for Traefik's docker provider to auto-discover —
its `loadbalancer.server.url` points straight at
`${PERCOLATOR_LAN_IP}:8123` instead of the usual `.server.port`, see that
file's own comment.

**No Authelia ForwardAuth on any of the three, deliberately, for now** —
all three have their own native login, and none is the kind of tool (like
silo's Scrutiny/NetAlertX/Komodo) that has weak or no auth of its own.
Revisit adding `middlewares=authelia@file` to any of them later as a
considered defense-in-depth call, not something missing by accident.

**Each app needs one more manual step post-Traefik that couldn't be set
via compose** — config that only exists once the app has actually run
(`config.php`) or is file-based, not env-based:
- `nextcloud`: `trusted_proxies`/`overwriteprotocol`/`overwritehost` in
  `config.php`, after its first-run install wizard completes — see its
  own compose file's comment.
- `homeassistant`: `http: use_x_forwarded_for / trusted_proxies` in
  `configuration.yaml` — see its own compose file's comment.
- `paperless`: none needed — `PAPERLESS_URL` (env-settable) was enough.

Skipping these on `nextcloud`/`homeassistant` won't break DNS-01/TLS
itself, but expect "untrusted proxy" errors or redirect loops on actual
app requests through Traefik until each is done.

ForwardAuth calls sieve's Authelia directly over the LAN
(`http://${SIEVE_LAN_IP}:9091/api/authz/forward-auth`, confirmed via
Authelia's own current Traefik integration docs) — `SIEVE_LAN_IP` needs
to be set in `.env.local` before `render-configs.sh` runs, since Docker
service discovery can't reach a different physical host by container
name. This has to be a direct hop to Authelia's own port, not routed
through sieve's public Traefik -- confirmed the hard way on silo's
identical setup 2026-09-04 (Authelia's own logs: `error="header
'X-Forwarded-Method' is empty"` -- a second Traefik hop drops that
header). Also needs sieve's Authelia to actually publish 9091 to its own
host, which it now does for exactly this reason -- see
`stacks/sieve/authelia/docker-compose.yml`'s own comment.

**Real TLS via Cloudflare DNS-01, not plain HTTP** — the original
2026-09-03 decision here ("no ACME/TLS, this fleet's LAN is already the
trust boundary") turned out to be wrong, corrected 2026-09-04 before this
was ever brought up for real: found live on silo's identical pattern
that Authelia hard-requires an https/wss target URL before it'll issue a
session cookie, no config flag to relax it. DNS-01 needs no inbound
port-80 reachability, so "no public DNS" was never actually the blocker
it was assumed to be. Needs `traefik/secrets.env.local`'s
`CF_DNS_API_TOKEN`, prompted by `generate-secrets.sh` — same required
scope (`Zone:DNS:Edit` on `${DOMAIN}`'s zone) as sieve's/silo's/cellar's
own Cloudflare tokens, safe to reuse the same real value.

```sh
sudo mkdir -p /srv/data/traefik/letsencrypt
sudo ufw allow from 192.168.0.0/24 to any port 80 proto tcp
sudo ufw allow from 192.168.0.0/24 to any port 443 proto tcp
./compose.sh traefik up -d
docker logs traefik --tail 30   # look for a successful cert issuance, not just a clean startup
```

### komodo-periphery

Added 2026-09-04, so silo's Komodo Core can see and manage percolator's
containers too -- no Core/Mongo here, just the agent (see
`komodo-periphery/docker-compose.yml`'s own header comment for the full
architecture note, same pattern as cellar's/sieve's/mochaPot's own copies
of this file). This is also the intended replacement for
`./compose.sh`-driven bring-up per Section 19.2 (see this README's own
header) -- once this is actually connected, prefer deploying percolator's
apps through Komodo's UI/API instead of SSHing in directly, though
nothing here stops you from still using `./compose.sh` if that's easier.

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
   percolator first -- **confirmed working 2026-09-05** (percolator/sieve/cellar all now show up as Servers in silo's Komodo UI), see
   `komodo-periphery/docker-compose.yml`'s own comment for the `scp`
   command.

Same outbound-only connection as every other node's Periphery
(percolator -> silo on port 9120, no inbound rule needed on percolator)
— and the same root-equivalent caveat: whoever controls Core on silo has
root-equivalent access to percolator once this is connected.

## What's here now

- `compose.sh` — wrapper so every app's docker-compose.yml sees the shared
  `.env.local` plus its own `secrets.env.local`. Copied verbatim from
  silo — nothing node-specific in the logic.
- `render-configs.sh` — renders `*.template` files into their real
  counterparts. Copied verbatim from silo.
- `setup-secrets.sh` — first-time-setup script: creates `.env.local` from
  `local.env.example`, prompts for any `REPLACE_ME`, runs
  `generate-secrets.sh` then `render-configs.sh`. Copied from silo, with
  its silo-specific prose adjusted to percolator.
- `generate-secrets.sh` — generates percolator's own secrets, locally, right
  here on percolator, straight into each app's `secrets.env.local` — no
  encryption, no key, nothing committed to git. (Changed 2026-09-02:
  percolator originally had a two-half SOPS+age bridge here instead —
  `decrypt-secrets.sh` plus a roastery-side `generate-secrets.ps1` —
  dropped fleet-wide for this simpler local-only approach; see that day's
  runbook entry.) Covers `traefik/secrets.env.local`'s `CF_DNS_API_TOKEN` and
  `komodo-periphery/secrets.env.local`'s `PERIPHERY_ONBOARDING_KEY` as of
  2026-09-04 (see each app's own section above) — `homeassistant`/
  `nextcloud`/`paperless`'s own db credentials are generated too, not
  prompted (restructured 2026-09-05 to live in each app's own
  `secrets.env.local` rather than a shared `postgres/` one — see
  `### postgres` above).
- `local.env.example` — copy to `.env.local` and fill in. Minimal for now
  (`PERCOLATOR_LAN_IP`, `TZ`, `DOMAIN`) — grows as apps are added, same
  as silo's did.
- `.gitignore` — same rules as sieve's/silo's: `.env.local`,
  `*/secrets.env.local`, and rendered `*/config/*` (except the tracked
  `.template` sources) are never committed.

## First-time setup on percolator

Once percolator exists and has at least one app built:

```
git pull
./setup-secrets.sh
```

Same one-command flow as silo — see stacks/silo/README.md's "First-time
setup on silo" section for what this actually does step by step (the
script itself is identical).

## Known gaps / things to double-check before relying on this

- **Stale as of 2026-09-05, corrected here**: percolator is live hardware
  now, komodo-periphery is built AND confirmed connected to silo's Komodo
  Core (see that section above), and homeassistant/, nextcloud/,
  paperless/ all have real compose files — this section previously said
  otherwise from when percolator was still just scaffolding.
- `homeassistant`/`nextcloud`/`paperless` each bring up their own
  colocated Postgres now (restructured 2026-09-05, see `### postgres`
  above) — none of it has been run against real hardware in this new
  shape yet. First real test of each is whatever bring-up happens next;
  confirm each app's `depends_on: condition: service_healthy` actually
  gates startup the way intended, not just that the YAML parses.
- `traefik/`'s Cloudflare DNS-01 TLS + Authelia ForwardAuth hop
  (2026-09-04) is also still entirely untested on percolator itself —
  confirmed working on silo, not yet exercised here.
- Immich's postgres image (`ghcr.io/immich-app/postgres`) carries ~90
  flagged CVEs in its OS layer per a community scan (immich-app/immich
  discussion #23211) that its maintainer has declined to remediate —
  acceptable given it's never exposed past its own compose file's default
  network, but revisit if that isolation assumption ever changes. This
  container lives on mochaPot now, not here — see that node's own README.
- mochaPot's storage may need growing to comfortably hold Immich's
  database now that it's colocated there instead of on percolator's
  larger fast-storage pool — a deliberate tradeoff (see the runbook's
  2026-09-05 entry), not an oversight; keep an eye on it as the photo
  library grows.
