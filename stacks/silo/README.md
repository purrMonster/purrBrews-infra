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
4. speedtest tracker, komodo, scrutiny, diun — not built yet (no
   interdependencies between these four, any order is fine)

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
| 20211 | tcp | netalertx | Web UI. `network_mode: host`, same category as sieve's Pi-hole — no `ports:` list of its own, binds directly on the host. |
| 20212 | tcp | netalertx | GraphQL API — opened to the LAN alongside 20211 on the assumption the browser UI calls it directly, not verified as server-side-only. See Known gaps. |

## Secrets: SOPS+age

Different from sieve's stack (plain gitignored local generation) — see
`secrets/README.md` for the full layout and the runbook's 2026-08-31
"Moving to silo" entry for why. Two steps, split across where each has to
run:

1. **On roastery**: add a `Set-SopsSecretIfAbsent` call to
   `generate-secrets.ps1` for any new secret, run it, `git add`/commit/push.
2. **On silo**, after `git pull`: `./setup-secrets.sh` (runs
   `./decrypt-secrets.sh` as one of its steps — see below) — needs the age
   private key at `/etc/purrbrews/age/keys.txt` (copied from sieve once,
   per `secrets/README.md`).

## First-time setup on silo

```sh
cd /opt/purrbrews/stacks/silo
chmod +x *.sh   # harmless if already set — see stacks/sieve/README.md's note on why

command -v sops || echo "sops not installed — see secrets/README.md"

./setup-secrets.sh
```

`setup-secrets.sh` (added 2026-08-31) is the one command that does everything
else in this section: creates `.env.local` from `local.env.example` if it
doesn't exist, prompts for any `REPLACE_ME` value still in it (`SILO_LAN_IP`,
`DOMAIN`, `SIEVE_LAN_IP` — confirm that last one matches
`stacks/sieve/.env.local`'s own value exactly; `SILO_LAN_INTERFACE`/
`SILO_LAN_SUBNET` as of 2026-09-01, for netalertx — see that app's own
section below for how to find the real interface name; only `TZ` has a real
default it won't ask about), runs `./decrypt-secrets.sh`,
warns (without trying to fix) if a decrypted secret still has a `REPLACE_ME`
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

Then:

```sh
sudo mkdir -p /srv/data/netalertx
sudo ufw allow from 192.168.0.0/24 to any port 20211 proto tcp
sudo ufw allow from 192.168.0.0/24 to any port 20212 proto tcp
./compose.sh netalertx up -d
```

**Verify it's actually scanning something before trusting the device
list** — this is the exact "runs clean, does nothing" failure mode a real
NetAlertX user hit (a wrong/missing interface, no error, no crash, just
zero devices found):

```sh
docker logs netalertx --tail 50   # look for scan activity, not just a clean startup
```

Then open `http://<SILO_LAN_IP>:20211` and confirm it actually lists
real devices on your LAN — not just silo and the gateway, which is what
a wrong `SILO_LAN_INTERFACE` looks like (see the runbook's 2026-09-01
entry for the real GitHub discussion this pattern is based on). If the
device count looks obviously short, double check `SILO_LAN_INTERFACE`
against the command above before assuming it's a scan-timing issue.

## Known gaps / things to double-check before relying on this

- `unbound`'s `klutchell/unbound:main` tag is a rolling tag, not a version
  pin (no semver releases exist for this image) — revisit once Diun exists
  later in this same build order.
- `homepage` (port 3000) isn't routed through Traefik/Authelia yet — same
  standing gap as lldap's admin UI on sieve.
- `homepage` is a stopgap dashboard, not the real one — see the runbook
  backlog for the DIY replacement, still undesigned.
- `netalertx`'s GraphQL port (20212) is opened to the whole LAN subnet
  alongside the web UI (20211), on the assumption the browser calls it
  directly — not confirmed against the actual app's network traffic. If
  it turns out to be server-side-only, narrow that ufw rule to
  loopback/localhost only.
- `netalertx`'s image tag (`26.8.5`) is pinned to what was current as of
  2026-09-01 — same "check before first real deploy, or wait for Diun"
  caveat as `unbound`'s tag above.
- `netalertx` runs with default `PUID`/`PGID` (20211:20211) — not
  reconciled against silo's actual host user, so files under
  `/srv/data/netalertx` may not be owned by `barista`. Only matters if
  you need to touch that directory directly from the host shell.
