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

Unlike sieve/silo, apps on percolator need to reach EACH OTHER by hostname
across separate `./compose.sh` projects (Home Assistant/Nextcloud/
Paperless-ngx each need their own Postgres instance; Paperless-ngx and,
recommended, Nextcloud also need Valkey). `./compose.sh` now creates a
shared external Docker network, `percolator_net`, idempotently before every
call — see that script's own header comment. Every compose file below
joins it via `networks: { percolator_net: { external: true } }`.

## Bringing each app up

### postgres (4 instances, one compose file)

One `docker-compose.yml`, four separate Postgres containers — matches
initiation.txt's own "Postgres ×4" phrasing (Section 5.4), not four
databases on one server, since each consuming app is independent and this
keeps failure domains separate:

- `postgres-immich` — **not** generic `pgvector/pgvector`. Uses Immich's
  own maintained image, `ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0`
  — confirmed 2026-09-03 against Immich's own current
  `docker/docker-compose.yml` and `docs.immich.app/administration/postgres-standalone`:
  pgvecto.rs support was dropped in Immich v3.0, it now needs VectorChord
  specifically. A community vuln scan flagged ~90 CVEs in this image's OS
  layer (immich-app/immich discussion #23211); the maintainer called most
  of it scanner noise on unused packages and declined to change base
  images. Real risk is low given this container is never exposed past
  `percolator_net`, but worth knowing, not assuming clean.
- `postgres-homeassistant`, `postgres-nextcloud` — plain `postgres:16`.
- `postgres-paperless` — plain `postgres:18`, matching Paperless-ngx's own
  official reference compose (`docker/compose/docker-compose.postgres.yml`)
  rather than defaulting to 16 like the other two — each app's Postgres
  version choice is independent, they don't share a server.

None of the four publish a host port — internal-only, reached via
`percolator_net` by whichever app owns each database. Data at
`/srv/data/postgres-<app>` each, local disk (never cellar's NFS — Immich's
own docs are explicit that DB storage must be local, and there's no reason
to treat the other three differently).

```sh
sudo mkdir -p /srv/data/postgres-immich /srv/data/postgres-homeassistant /srv/data/postgres-nextcloud /srv/data/postgres-paperless
sudo ufw allow from <mochaPot's LAN IP> to any port 5432 proto tcp
./compose.sh postgres up -d
```

Only `postgres-immich` publishes a port (5432) — corrected 2026-09-03,
originally designed internal-only, but Immich's server component lives on
mochaPot, a different physical host, and Docker networks don't span
hosts. Scoped in ufw to mochaPot's specific LAN IP, not the whole subnet
— tighter than most of this fleet's ufw rules since this is direct
database access. `postgres-homeassistant`/`-nextcloud`/`-paperless` stay
unpublished, same-host consumers only.

### valkey

**Valkey, not Redis** — confirmed 2026-09-03: Redis's 2024 license change
moved it off OSI-approved open source, and the self-hosting ecosystem has
shifted accordingly. Not a guess — Immich's own current official compose
already uses `valkey/valkey:9`, and Paperless-ngx's own official Postgres
reference compose independently uses `valkey/valkey:9-alpine` as its
broker too. One shared instance, namespaced by Valkey's built-in logical
DB indexes rather than one container per consumer (neither app's docs
require isolation, and it's worth conserving percolator's RAM):

- DB 0 — immich (`REDIS_DBINDEX=0`, the image's own default)
- DB 1 — paperless-ngx (`PAPERLESS_REDIS=redis://valkey:6379/1`)
- DB 2 — reserved for nextcloud once its compose file exists (recommended
  by Nextcloud's own docs, not required)

No password configured, no volume (cache/queue only, ephemeral is correct
for both current consumers) — matches Immich's own official compose.

```sh
sudo ufw allow from <mochaPot's LAN IP> to any port 6379 proto tcp
./compose.sh valkey up -d
```

Also published to the LAN as of 2026-09-03, same cross-host reason as
`postgres-immich` above — scope the ufw rule to mochaPot specifically.

### homeassistant

`network_mode: host`, required per Home Assistant's own Cast integration
docs (mDNS discovery doesn't work otherwise) — confirmed 2026-09-03, not
assumed. Consequence: it can't reach `postgres-homeassistant` via
`percolator_net` container DNS the way the other apps do, since host
networking bypasses Docker's embedded DNS entirely — that instance is
published to `127.0.0.1:5432` instead, loopback only.

```sh
sudo mkdir -p /srv/data/homeassistant
./compose.sh homeassistant up -d
```

No default credentials — onboarding wizard at `http://<PERCOLATOR_LAN_IP>:8123`.
**The Postgres recorder needs a manual step after first boot** —
confirmed there's no compose-level way to configure this, it's
`configuration.yaml`-only. Add to `/srv/data/homeassistant/configuration.yaml`:

```yaml
recorder:
  db_url: postgresql://homeassistant:<HA_DB_PASSWORD from ../postgres/secrets.env.local>@127.0.0.1:5432/homeassistant
```

then restart. Runs fine on its own default SQLite until you do this —
not a blocker to bringing HA up, just to getting the recorder onto
Postgres.

### nextcloud

```sh
sudo mkdir -p /srv/data/nextcloud
./compose.sh nextcloud up -d
```

Admin login: `barista` / `NEXTCLOUD_ADMIN_PASSWORD` from
`nextcloud/secrets.env.local`. Uses `postgres-nextcloud` and `valkey`
(DB 2) via `percolator_net`. **Known gap**: `trusted_proxies`/
`overwriteprotocol`/`overwritehost` (`config.php` keys, don't exist until
after first install) aren't set yet — required once this is actually
routed through `traefik/`, confirmed via Nextcloud's own reverse-proxy
docs the symptom otherwise is redirect loops or "not accessible" errors.
Set these once traefik/ is verified working, not before.

### paperless

```sh
sudo mkdir -p /srv/data/paperless/{data,media,export,consume}
./compose.sh paperless up -d
```

Admin login: `barista` / `PAPERLESS_ADMIN_PASSWORD` from
`paperless/secrets.env.local`. Uses `postgres-paperless` and `valkey`
(DB 1). **Known gaps, not built here**: gotenberg/tika (non-PDF document
conversion) aren't included — PDF-only consumption works without them.
Non-English OCR needs tesseract language packs not bundled in this base
image.

### traefik

Internal-only reverse proxy for percolator's own apps — not sieve's
tunnel-facing instance. `providers.docker.exposedByDefault=false` —
confirmed this is the right default for a homelab host running several
unrelated stacks on `percolator_net`; apps opt in per-container with
`traefik.enable=true` (not yet added to nextcloud/paperless/homeassistant's
own compose files — do that once Traefik itself is confirmed healthy, to
avoid breaking their current direct-port access first). **When you do,
use `traefik.http.routers.<name>.entrypoints=websecure`, not `web`** —
see below for why.

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
   percolator first -- **this mechanism is unverified**, see
   `komodo-periphery/docker-compose.yml`'s own comment for the best-guess
   `scp` command.

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
  2026-09-04 (see each app's own section above) — postgres/nextcloud/
  paperless's secrets are generated, not prompted.
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

- postgres/ and valkey/ are written and locally YAML-validated but not yet
  run against real hardware — percolator itself doesn't exist as
  hardware/a VM yet as of 2026-09-03. First real test of `setup-secrets.sh`
  and `./compose.sh postgres up -d` happens once it does.
- homeassistant/, nextcloud/, paperless/ have no compose files yet —
  research is done (see the runbook's 2026-09-03 entry), writing them is
  next. `traefik/` does have one now (2026-09-04, including the
  Cloudflare DNS-01 TLS fix — see its own section above), but it's
  entirely untested: percolator doesn't exist as hardware/a VM yet, so
  nothing in this file has ever actually been brought up. Confirm the
  cert issuance and the Authelia ForwardAuth hop both actually work on
  percolator's first real bring-up, not just on silo's.
- The Immich postgres image (`ghcr.io/immich-app/postgres`) carries ~90
  flagged CVEs in its OS layer per a community scan (immich-app/immich
  discussion #23211) that its maintainer has declined to remediate —
  acceptable given it's never exposed past `percolator_net`, but revisit
  if that isolation assumption ever changes.
- If percolator will run a Komodo Periphery agent (so silo's Komodo Core can
  manage it), see `stacks/_templates/komodo-periphery/docker-compose.yml`
  — copy it into an app subdirectory here once percolator exists and fill in
  its `REPLACE_ME` values.
