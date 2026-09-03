# stacks/silo — security, QoL & fleet ops (Section 18.3)

Second node in deploy order (sieve → **silo** → cellar → percolator →
mochaPot → ristretto). Same tooling as `stacks/sieve` — see that stack's
README for the general pattern (`compose.sh`, `render-configs.sh`,
`.env.local`/`secrets.env.local` split). This file only covers what's
silo-specific: setup, secrets, and the bring-up steps for each app.

Apps come up in this order:

1. **unbound** — recursive resolver feeding sieve's Pi-hole; no dependencies
2. **homepage** — stopgap dashboard; not part of Section 18.3's own sequence, brought up early since it doesn't depend on or block anything
3. **netalertx** — LAN device discovery/presence alerting; no dependencies
4. **speedtest tracker**, **komodo**, **scrutiny**, **diun** — no
   interdependencies between these four, any order is fine. **komodo is
   the one that matters beyond silo itself**: it's what's meant to manage
   containers on percolator/cellar/mochaPot too, once those nodes exist —
   see its own section below and `stacks/_templates/komodo-periphery/`
   for the reusable piece those future nodes will need.

**crowdsec lives on `stacks/sieve/`, not here** (decided 2026-09-01,
despite Section 18.3 naming silo as its home) — see
`stacks/sieve/README.md`'s crowdsec section and the runbook's 2026-09-01
entry for why: sieve turned out to be the only node with anything worth
watching (silo has no public exposure at all), and running everything on
one node avoided a genuinely unconfirmed cross-node registration/bouncer
deployment problem for no real benefit at this fleet's size.

For the "why" behind any choice below (image picks, networking mode,
config approach, secrets model) see the dated runbook entries linked
inline — this file is deliberately just the how.

## Ports in use on this host (added 2026-09-01)

**Check this table before publishing a new port in any app's
`docker-compose.yml`.** Same reasoning as sieve's own version of this
table — added after a real port collision on sieve (crowdsec vs. Pi-hole)
made it obvious this should be checked up front, not discovered at
`docker compose up` time. silo is a separate host from sieve — nothing
here shares a port space with sieve's table in `stacks/sieve/README.md`.

| Port | Proto | Owner | Notes |
|------|-------|-------|-------|
| 53 | tcp+udp | unbound | Recursive resolver — access-control restricted to sieve only, see below. |
| 3000 | tcp | homepage | Stopgap dashboard, LAN-reachable directly — not yet routed through Traefik. |
| 20211 | tcp | netalertx | Web UI, password-protected (see below). `network_mode: host`, same category as sieve's Pi-hole — no `ports:` list of its own, binds directly on the host. |
| 20212 | tcp | netalertx | GraphQL API — bound on the host (host networking) but deliberately **not** given a LAN-wide ufw rule (see netalertx's own section) — open it only if the UI turns out to need direct browser access to it, which isn't confirmed either way. |
| 8080 | tcp | speedtest-tracker | Web UI. |
| 8443 | tcp | speedtest-tracker | Web UI, HTTPS. |
| 8081 | tcp | scrutiny | Web UI — moved off Scrutiny's own default 8080 to dodge the speedtest-tracker collision above (container's own internal port is still 8080, only the host-side publish moved). No auth in this app at all — see Known gaps. |
| 9120 | tcp | komodo | Core's web UI/API. Also needs to accept connections from future nodes' Periphery agents once percolator/cellar/mochaPot exist — see komodo's own section. |

Not published to the host at all, for contrast: scrutiny's embedded
InfluxDB (8086 — reached over loopback inside its own container, nothing
external needs it), diun and its docker-socket-proxy sidecar (no web UI
or API surface, nothing to publish).

## Secrets: local generation

Same pattern as sieve's stack: `generate-secrets.sh` runs directly on silo
and writes real values straight into each app's `secrets.env.local` —
gitignored, never committed. (Changed 2026-09-02: silo originally used a
SOPS+age bridge instead — secrets generated and encrypted on roastery,
committed as ciphertext, decrypted here — replaced fleet-wide with this
simpler local-only approach; see that day's runbook entry for why.)

Adding a new secret: add a `set_if_absent` (or `prompt_if_placeholder`)
call to `generate-secrets.sh`, then just run it — right here on silo, no
roastery step, no key to manage.

## First-time setup on silo

```sh
cd /opt/purrbrews/stacks/silo
chmod +x *.sh   # harmless if already set — see stacks/sieve/README.md's note on why

./setup-secrets.sh
```

`setup-secrets.sh` (added 2026-08-31) is the one command that does everything
else in this section: creates `.env.local` from `local.env.example` if it
doesn't exist, prompts for any `REPLACE_ME` value still in it (`SILO_LAN_IP`,
`DOMAIN`, `SIEVE_LAN_IP` — confirm that last one matches
`stacks/sieve/.env.local`'s own value exactly; `SILO_LAN_INTERFACE`/
`SILO_LAN_SUBNET` as of 2026-09-01, for netalertx — see that app's own
section below for how to find the real interface name; only `TZ` has a real
default it won't ask about), runs `./generate-secrets.sh`,
warns (without trying to fix) if a generated secret still has a `REPLACE_ME`
in it, then runs `./render-configs.sh`. Safe to re-run any time — a value
that's already set is never touched. See its own header comment for why
this exists: Homepage's first real bring-up (2026-08-31) failed its host
check because `.env.local` had no automated fill-in the way sieve's
`generate-secrets.sh` handles its own, and "fill in by hand" turned out to
be an easy step to skip past without noticing.

## Bringing each app up

### unbound

```sh
./compose.sh unbound up -d

# Required before it's reachable from sieve at all — scoped to sieve
# specifically, not the whole LAN:
sudo ufw allow from 192.168.0.10 to any port 53 proto tcp
sudo ufw allow from 192.168.0.10 to any port 53 proto udp
```

Verify the access-control restriction actually holds before trusting it
with any real traffic:

```sh
dig @<SILO_LAN_IP> example.com   # from sieve — should answer
dig @<SILO_LAN_IP> example.com   # from any OTHER LAN device — should REFUSE or time out
```

Once verified, point sieve's Pi-hole at it instead of the public fallback:
edit `stacks/sieve/pihole/docker-compose.yml`'s `FTLCONF_dns_upstreams`
(currently `1.1.1.1;1.0.0.1`) to `${SILO_LAN_IP}`, then on sieve:

```sh
./compose.sh pihole up -d
```

Deliberately a separate, later step — not bundled into bringing Unbound up
itself. See the runbook's 2026-08-31 "Unbound" entry for the image choice
(`klutchell/unbound` over `mvance/unbound`), the networking mode (bridge,
not host), and the config approach (one additive access-control file, not
a full rewrite).

### homepage

```sh
sudo ufw allow from 192.168.0.0/24 to any port 3000 proto tcp
./compose.sh homepage up -d
```

Reachable at `http://<SILO_LAN_IP>:3000`. To add a link (e.g. once another
silo app is up): edit `homepage/config/services.yaml.template`, then
`./render-configs.sh && ./compose.sh homepage restart`. See the runbook's
2026-08-31 "Stopgap Homepage dashboard" entry for why this app, why
`HOMEPAGE_ALLOWED_HOSTS` is required, and the image pin.

### netalertx

Before bringing it up, find silo's actual LAN interface name and fill in
`SILO_LAN_INTERFACE`/`SILO_LAN_SUBNET` in `.env.local` (`./setup-secrets.sh`
prompts for these if still `REPLACE_ME` — see above):

```sh
ip -o link show | awk -F': ' '!/lo|vir|docker/ {print $2}'   # run on silo itself
```

Also needs a secret, unlike unbound/homepage: `NETALERTX_PASSWORD` (see
`generate-secrets.sh`'s netalertx section) — a randomly generated login
password.
**Deliberately not left unauthenticated**: NetAlertX has no login
requirement by default, and has real published CVE history for
unauthenticated remote command execution / auth bypass (see the runbook's
2026-09-01 entry). The pinned image tag postdates the fixes for those
specific CVEs, but running it open to the whole LAN regardless wasn't
worth it — same reasoning that keeps Pi-hole's admin UI gated on sieve.
`./setup-secrets.sh` picks this up automatically the same way it does
every other secret — nothing extra to run.

Then:

```sh
sudo mkdir -p /srv/data/netalertx
sudo ufw allow from 192.168.0.0/24 to any port 20211 proto tcp
./compose.sh netalertx up -d
```

Only 20211 gets a LAN-wide ufw rule — 20212 (GraphQL) deliberately does
not, since it's not confirmed whether the browser UI needs to reach it
directly or everything's proxied through 20211 internally (NetAlertX's
own docs don't say either way). If the UI is visibly broken (check the
browser's network tab for failed requests to port 20212) once it's up,
that's the signal to add `sudo ufw allow from 192.168.0.0/24 to any port
20212 proto tcp` too — don't open it preemptively given this app's CVE
history above.

**Verify it's actually scanning something before trusting the device
list** — this is the exact "runs clean, does nothing" failure mode a real
NetAlertX user hit (a wrong/missing interface, no error, no crash, just
zero devices found):

```sh
docker logs netalertx --tail 50   # look for scan activity, not just a clean startup
```

Then open `http://<SILO_LAN_IP>:20211`, log in with the password from
`netalertx/secrets.env.local` (`NETALERTX_PASSWORD` — no separate
username field, per NetAlertX's docs, not independently confirmed until
you actually see the login screen), and confirm it actually lists real
devices on your LAN — not just silo and the gateway, which is what a
wrong `SILO_LAN_INTERFACE` looks like (see the runbook's 2026-09-01 entry
for the real GitHub discussion this pattern is based on). If the device
count looks obviously short, double check `SILO_LAN_INTERFACE` against
the command above before assuming it's a scan-timing issue.

### speedtest-tracker

```sh
sudo mkdir -p /srv/data/speedtest-tracker/config
sudo ufw allow from 192.168.0.0/24 to any port 8080 proto tcp
sudo ufw allow from 192.168.0.0/24 to any port 8443 proto tcp
./compose.sh speedtest-tracker up -d
```

Log in at `http://<SILO_LAN_IP>:8080` with `barista` / the password from
`speedtest-tracker/secrets.env.local` (`SPEEDTEST_TRACKER_ADMIN_PASSWORD`)
— **not** the image's own documented default (`admin@example.com` /
`password`), which never gets created here since `ADMIN_EMAIL`/
`ADMIN_PASSWORD`/`ADMIN_NAME` are set before first boot.

**Verify a speed test actually runs** — this app's own most common
first-deploy failure, per multiple real GitHub issues, is the UI silently
showing "no speedtest scheduled" forever with no error:

```sh
docker logs speedtest-tracker --tail 50   # look for a scheduler tick, not just a clean startup
```

If nothing's run within the hour (`SPEEDTEST_SCHEDULE` is `0 * * * *`,
on the hour), check that variable made it into the container correctly
before assuming it's just slow.

### scrutiny

**Device path already filled in** (2026-09-02, from silo's own `lsblk -d
-o NAME,TYPE,SIZE,MODEL`): silo has one physical disk, `/dev/sda` (931.5G,
Seagate BarraCuda `ST1000LM035-1RK172`), already set in
`scrutiny/docker-compose.yml`'s `devices:` list. If a disk is ever
added/removed/replaced on silo, that list needs a matching manual edit —
`setup-secrets.sh` never touches a `docker-compose.yml` directly, only
`.env.local`, so this doesn't auto-update:

```sh
lsblk -d -o NAME,TYPE,SIZE,MODEL   # or: smartctl --scan
```

One line per real physical disk (not partitions) — `/dev/sda`, `/dev/sdb`,
etc. For NVMe, use the controller node (`/dev/nvme0`), not the namespace
block device (`/dev/nvme0n1`). Getting this wrong fails loudly at `docker
compose up` (the device doesn't exist) rather than starting successfully
with no disk access — that's the safety net here.

```sh
sudo mkdir -p /srv/data/scrutiny/config /srv/data/scrutiny/influxdb
sudo ufw allow from 192.168.0.0/24 to any port 8081 proto tcp
./compose.sh scrutiny up -d
```

Reachable at `http://<SILO_LAN_IP>:8081` — **no login**, see Known gaps.
Confirm it actually sees your disks (not just that the container started):
open the UI and check every physical disk shows up with real S.M.A.R.T.
data, not an error/missing state.

### diun

No `.env.local`/secrets changes needed — nothing here is a secret (no web
UI, no login, see Known gaps).

```sh
sudo mkdir -p /srv/data/diun
./compose.sh diun up -d
```

Confirm the docker-socket-proxy sidecar actually works before trusting
this — there's a real, previously reported unresolved connectivity issue
with this exact pattern (see `diun/docker-compose.yml`'s own comment):

```sh
docker logs diun --tail 50   # look for a completed scan of your containers, not a connection error
```

If it shows a connection failure reaching `diun-docker-socket-proxy`, the
documented fallback (less safe, simpler) is dropping the proxy sidecar
from `diun/docker-compose.yml` entirely and pointing
`DIUN_PROVIDERS_DOCKER_ENDPOINT` at `unix:///var/run/docker.sock` with a
direct `:ro` bind mount instead.

**No notification channel is configured yet — deliberately, not an
oversight.** Diun will watch and log what it finds (`docker logs diun`),
but has nowhere to send it until a channel gets picked (Telegram, ntfy, a
generic webhook, etc. — see the runbook's 2026-09-01 entry for the
options). This is worth deciding together with the still-open CrowdSec
remote-unban-method backlog item (`stacks/sieve/README.md`'s crowdsec
section) — a Telegram or Nextcloud Talk bot could plausibly serve both.

### komodo

The most involved app on silo so far — three containers (Mongo, Core,
Periphery), and the one other future nodes will depend on. Read the
compose file's own header comment before bringing this up, especially
the AVX preflight check:

```sh
grep avx /proc/cpuinfo   # MUST show something — MongoDB 5.0+ crashes outright without it
```

**Already checked for silo** (2026-09-02): `avx` shows on every core —
clear to proceed. Kept as a documented step anyway, both as the safety
net if silo's CPU/VM config ever changes, and as the thing to run on any
future node before it gets its own Periphery (see below) — Mongo itself
never runs anywhere but silo, but this is worth knowing regardless. If
this ever comes back empty on a re-check, stop — this compose file needs
rethinking (see its header comment), not just retrying.

```sh
sudo mkdir -p /srv/data/komodo/mongo-data /srv/data/komodo/mongo-config \
              /srv/data/komodo/keys /srv/data/komodo/backups
sudo mkdir -p /etc/komodo   # deliberately NOT under /srv/data — see the compose file's comment
sudo ufw allow from 192.168.0.0/24 to any port 9120 proto tcp
./compose.sh komodo up -d
```

Log in at `http://<SILO_LAN_IP>:9120` with `barista` / the password from
`komodo/secrets.env.local` (`KOMODO_INIT_ADMIN_PASSWORD`) — again, not
the official reference file's own default (`admin`/`changeme`), never
created here.

**Treat this app's credentials with real weight, not homelab-casual
weight**: `KOMODO_JWT_SECRET`, `KOMODO_WEBHOOK_SECRET`, and the admin
account together control something that has root-equivalent access (via
Periphery's Docker socket mount) to every node Komodo ends up managing —
see the compose file's own comment on `komodo-periphery`'s volumes for
why. This isn't a bigger deal than, say, sieve's Cloudflare DNS API
token, but it's in that same category, not the category of "another
app's admin password."

**Preparing percolator/cellar/mochaPot for Komodo management**, once
those nodes physically exist: copy
`stacks/_templates/komodo-periphery/docker-compose.yml` into that node's
own stack directory, follow the setup steps in its header comment
(get an onboarding key from silo's Komodo UI, fill in the node's real
name/TZ/silo's LAN IP), and open port 9120 to that node's LAN IP on silo
if the existing ufw rule above doesn't already cover it. Nothing about
this needs Komodo Core or Mongo touched again — only a new Periphery
agent per node.

## Known gaps / things to double-check before relying on this

- `unbound`'s `klutchell/unbound:main` tag is a rolling tag, not a version
  pin (no semver releases exist for this image) — revisit once Diun exists
  later in this same build order.
- `homepage` (port 3000) isn't routed through Traefik/Authelia yet — same
  standing gap as lldap's admin UI on sieve.
- `homepage` is a stopgap dashboard, not the real one — see the runbook
  backlog for the DIY replacement, still undesigned.
- `netalertx`'s image tag (`26.8.5`) is pinned to what was current as of
  2026-09-01 — same "check before first real deploy, or wait for Diun"
  caveat as `unbound`'s tag above.
- `netalertx` runs with default `PUID`/`PGID` (20211:20211) — not
  reconciled against silo's actual host user, so files under
  `/srv/data/netalertx` may not be owned by `barista`. Only matters if
  you need to touch that directory directly from the host shell.
- `netalertx`'s `SETPWD_password` is assumed to take a plaintext value
  (hashed internally by the app) based on how NetAlertX's own docs show
  the example — not confirmed against the actual source. If the login
  screen rejects the real password from `secrets.env.local`, this
  assumption is the first thing to check.
- `netalertx`'s GraphQL port (20212) is bound on the host but has no ufw
  rule by default — see its own section above for why (unconfirmed
  whether the browser needs direct access to it, and this app's CVE
  history made "open it just in case" the wrong default this time).
- `speedtest-tracker` runs with the LinuxServer image's own default
  `PUID`/`PGID` — same accepted gap, same reasoning, as `netalertx`'s
  above.
- `scrutiny` has **no authentication of any kind** — not a documented
  design choice by its maintainers (no CVEs either, this is just a real
  absence), same "LAN-reachable, not yet gated" acceptance as
  `homepage`/`lldap`. Route it through Traefik/Authelia along with those,
  when that backlog item gets picked up — don't treat this one as lower
  priority just because it was found later.
- `scrutiny`'s `cap_add: SYS_ADMIN` (needed for NVMe smartctl access) is
  left in place even though silo's `lsblk` output (2026-09-02) confirms
  its one disk (`/dev/sda`) is a SATA HDD, not NVMe — so this capability
  is currently unused. Left in rather than narrowed to just `SYS_RAWIO`,
  in case an NVMe drive is ever added to this node later; revisit if that
  changes.
- `diun`'s `tecnativa/docker-socket-proxy` pin **was wrong on first
  bring-up** (2026-09-02): `0.4.2` doesn't exist on Docker Hub, the real
  tag needed a `v` prefix (`v0.4.2`). Fixed and moved to `v0.5.0` (current
  stable), this time verified against Docker Hub's registry API directly
  rather than a summarized page fetch — see the runbook's 2026-09-02
  entry for the full story. Worth remembering as a category, not just
  this one pin: a page-fetch summary can silently drop a detail like a
  tag prefix that a real `docker compose up` won't forgive.
- `diun` has no notification channel configured — deliberately deferred,
  see its own section above. It's watching and logging, just not alerting
  anywhere yet.
- `komodo`'s `PERIPHERY_DISABLE_CONTAINER_TERMINALS` is left at the
  official default (`false`, remote container shell access allowed from
  the Komodo UI) — not tightened, since Periphery's docker.sock access
  already grants equivalent capability regardless of this flag; disabling
  it would reduce UI convenience without reducing actual risk.
- ~~`komodo`'s MongoDB AVX requirement~~ — checked 2026-09-02, confirmed
  present on silo. No longer a gap; kept as a documented preflight step
  for any future node running its own Periphery.
