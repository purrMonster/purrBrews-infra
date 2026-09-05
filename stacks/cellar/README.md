# cellar

Stack directory scaffolded 2026-09-01, ahead of cellar actually existing
as hardware/a VM. Real build started 2026-09-03 (after percolator's --
see percolator/README.md's own note on why cellar's original go-first
reason, early Vaultwarden availability for secrets, stopped applying once
SOPS+age was dropped 2026-09-02). Hardware for cellar/percolator/mochaPot
confirmed ready by User Penguin as of 2026-09-03.

## Bringing each app up

### vaultwarden

Human-facing password vault -- unrelated to how this fleet generates ITS
OWN container secrets (`generate-secrets.sh` everywhere, unchanged).

**Bring `caddy` up first (see its own section below)** -- as of
2026-09-04, Vaultwarden no longer publishes a port of its own at all; it
needs `caddy` up and the `cellar_net` network it creates before it's
reachable by anything, Caddy included.

```sh
sudo mkdir -p /srv/data/vaultwarden
./compose.sh vaultwarden up -d
```

Reachable at `https://vault.${DOMAIN}` (once sieve's Pi-hole has the
Local DNS Record, see caddy's own section) -- **not** a bare LAN IP/port
anymore. Confirmed 2026-09-04 via Vaultwarden's own wiki: real HTTPS was
never optional here, Bitwarden clients (browser extension, mobile, CLI)
refuse plain HTTP except exactly `http://localhost` since WebCrypto
requires a secure context -- this wasn't a security nice-to-have, the
apps you'd actually use this with won't connect without it. First real
account you create there is the one to keep -- **then manually set
`SIGNUPS_ALLOWED=false`** in `docker-compose.yml` and restart. Confirmed
2026-09-03 this doesn't happen automatically; leaving it `true` means
anyone who finds this URL can register their own account.

**Admin token upgrade, not done automatically**: `VAULTWARDEN_ADMIN_TOKEN`
is currently a random plaintext value (works, but Vaultwarden's own
current docs recommend an Argon2id hash instead). Once the container's
up:

```sh
docker exec -it vaultwarden /vaultwarden hash
```

Paste the resulting `$argon2id$...` string into `ADMIN_TOKEN` in
`vaultwarden/docker-compose.yml` directly (doubling every `$` to `$$` --
compose does its own `$` interpolation), remove the `${VAULTWARDEN_ADMIN_TOKEN}`
reference, restart.

### caddy

Added 2026-09-04, specifically to give Vaultwarden real HTTPS -- see
vaultwarden's own section above for why this isn't optional. TLS
termination only, no auth middleware -- deliberately not Traefik/
Authelia, and deliberately not routing through silo's Traefik either
(that would mean Vaultwarden traffic crossing to a different physical
host for no reason). ForwardAuth in front of Vaultwarden breaks native
Bitwarden clients (they hit `/api`/`/identity` directly, no browser
session to redirect through an SSO flow), and Vaultwarden already has its
own real auth (master password + 2FA + admin token) -- there's nothing a
gate would add here. This is exactly what Vaultwarden's own wiki
recommends over its built-in `ROCKET_TLS` (documented as "not
recommended", RSA-only, can't parse the ECDSA certs Certbot defaults to
since v2.0).

Custom-built image (official Caddy has no Cloudflare DNS plugin baked
in) -- `docker compose build` handles this automatically as part of
`up`, nothing separate to run. DNS-01 challenge via Cloudflare, not
HTTP-01: cellar has no port 80 exposed to the internet (no port
forward), so HTTP-01 validation isn't possible here regardless -- DNS-01
needs no inbound access at all, and Caddy renews and reloads
automatically with no cron job or restart-on-renew needed.

Needs a real Cloudflare credential -- `caddy/secrets.env.local`'s
`CLOUDFLARE_API_TOKEN`, prompted by `setup-secrets.sh`/`generate-secrets.sh`
since it can't be randomly generated (same category as mochaPot's
Roundcube mail hosts). Needs `Zone:DNS:Edit` permission on whatever zone
`${DOMAIN}` is under -- reuse sieve's own `CF_DNS_API_TOKEN` if it
already has that scope, or create a new narrowly-scoped one.

```sh
sudo mkdir -p /srv/data/caddy/data /srv/data/caddy/config
sudo ufw allow from 192.168.0.0/24 to any port 443 proto tcp
./compose.sh caddy up -d
docker logs caddy --tail 50   # look for a successful cert issuance, not just a clean startup
```

**Before this actually works**, add a Local DNS Record in sieve's Pi-hole
(Settings → Local DNS Records, or `/etc/pihole/custom.list` directly) for
`vault.${DOMAIN}`, pointing at `${CELLAR_LAN_IP}` -- same pattern as
silo's `*.${DOMAIN}` hostnames from the same day, not added yet, not part
of this build. Test with `curl -H "Host: vault.${DOMAIN}"
https://<CELLAR_LAN_IP>/ -k` (the `-k` is expected until DNS is real --
Caddy's cert is issued for the real hostname, so hitting it by raw IP
will always show a cert-mismatch warning, that's not a failure).

### smb

Confirmed 2026-09-03: `dperson/samba` (the commonly-tutorialized image) is
stale/unmaintained -- using `ghcr.io/servercontainers/samba` instead,
actively maintained.

```sh
sudo mkdir -p /srv/media/household /srv/media/archive
./compose.sh smb up -d
```

Household share + one archive share (Immich originals/Paperless-ngx
archive/Nextcloud cold storage will land under `archive/` subfolders once
percolator's apps actually write to it -- not split per-app yet, nothing
consumes it via SMB individually). One user, `barista`, password in
`smb/secrets.env.local`. Add real household accounts with more
`ACCOUNT_<name>`/`UID_<name>` env vars as needed -- not done here, this is
a starting point.

**NFS is intentionally not in this directory at all.** Confirmed
2026-09-03: containerized NFS servers are still not recommended --
the common image (`erichough/nfs-server`) is effectively abandoned and
needs `--privileged`/broad `SYS_ADMIN`. Set up NFS natively on cellar
instead, once percolator/mochaPot are actually ready to mount from it:

```sh
sudo apt install nfs-kernel-server
# add exports for /srv/media/archive (and household, if wanted) to
# /etc/exports, then:
sudo exportfs -ra
```

Not done yet -- percolator/mochaPot don't have anything trying to mount
from cellar as of 2026-09-03. **UID/GID gotcha to resolve before this
matters**: whatever UID NFS exports use must match `smb/docker-compose.yml`'s
`UID_barista` and whatever UID percolator/mochaPot's containers run as, or
SMB and NFS clients touching the same files get permission mismatches --
not yet reconciled.

### komodo-periphery

Added 2026-09-04, so silo's Komodo Core can see and manage cellar's
containers too -- no Core/Mongo here, just the agent (see
`komodo-periphery/docker-compose.yml`'s own header comment for the full
architecture note, same as every other node's Periphery agent).

```sh
sudo mkdir -p /srv/data/komodo-periphery/keys
./compose.sh komodo-periphery up -d
```

**Two things need to be true before `up -d` actually connects, neither
automatic**:

1. `komodo-periphery/secrets.env.local`'s `PERIPHERY_ONBOARDING_KEY` needs
   a real value from silo's Komodo UI (Settings -> the onboarding/servers
   section) -- `generate-secrets.sh` prompts for it, same as caddy's
   Cloudflare token.
2. `PERIPHERY_CORE_PUBLIC_KEYS` needs silo's `core.pub` copied onto
   cellar first -- **confirmed working 2026-09-05** (percolator/sieve/cellar all now show up as Servers in silo's Komodo UI), see
   `komodo-periphery/docker-compose.yml`'s own comment for the `scp`
   command and why it isn't asserted as confirmed-correct.

Same outbound-only connection as every other node's Periphery (cellar ->
silo on port 9120, no inbound rule needed on cellar) -- and same caveat
as Komodo everywhere else in this fleet: whoever controls Core on silo
has root-equivalent access to cellar once this is connected.

### scrutiny-collector

Added 2026-09-05 -- Scrutiny's own "hub and spoke" multi-host pattern
(see `scrutiny-collector/docker-compose.yml`'s own comment): silo's
existing omnibus Scrutiny container is the hub, this pushes cellar's
SMART data to it over the LAN instead of running its own web UI.

**Fill in real disk device paths first** -- `.env.local`'s
`CELLAR_DISK_DEVICE_NVME`/`CELLAR_DISK_DEVICE_HDD` are placeholders,
confirm the real values on cellar itself:

```sh
lsblk -d -o NAME,TYPE,SIZE,MODEL
```

then

```sh
./compose.sh scrutiny-collector up -d
```

Requires silo's `scrutiny` service to have its port 8080 republished
(done 2026-09-05 -- see `stacks/silo/scrutiny/docker-compose.yml`'s own
comment for the real security tradeoff this reopens, not a free lunch).
Confirm cellar's disks actually show up in silo's Scrutiny UI afterward,
distinguished by hostname -- that's the real test, not just that this
container starts.

### backup-mirror

**Not a container, deliberately.** Confirmed 2026-09-03: no well-
maintained rsync-in-a-container image exists. This is a plain script +
systemd timer instead:

```sh
sudo cp backup-mirror/backup-mirror.service backup-mirror/backup-mirror.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now backup-mirror.timer
```

`backup-mirror/mirror.sh` has no real sources configured yet (see its own
`REPLACE_ME_*` placeholders) -- percolator/mochaPot don't have real data
worth mirroring as of 2026-09-03. Fill those in once they do. Uses plain
`rsync -a` with **no `--delete`** -- deliberately append-only, since this
is cellar's SECOND copy alongside the separate household NAS (Section
4.3); a source-side deletion (bug, mistake) shouldn't propagate here and
wipe the only other copy too. No snapshot/rotation implemented -- known
gap, revisit if disk usage becomes a real concern.

## What's here now

- `compose.sh` — wrapper so every app's docker-compose.yml sees the shared
  `.env.local` plus its own `secrets.env.local`. Copied verbatim from
  silo — nothing node-specific in the logic.
- `render-configs.sh` — renders `*.template` files into their real
  counterparts. Copied verbatim from silo.
- `setup-secrets.sh` — first-time-setup script: creates `.env.local` from
  `local.env.example`, prompts for any `REPLACE_ME`, runs
  `generate-secrets.sh` then `render-configs.sh`. Copied from silo, with
  its silo-specific prose adjusted to cellar.
- `generate-secrets.sh` — generates cellar's own secrets, locally, right
  here on cellar, straight into each app's `secrets.env.local` — no
  encryption, no key, nothing committed to git. (Changed 2026-09-02:
  cellar originally had a two-half SOPS+age bridge here instead —
  `decrypt-secrets.sh` plus a roastery-side `generate-secrets.ps1` —
  dropped fleet-wide for this simpler local-only approach; see that day's
  runbook entry.) Covers vaultwarden, smb, komodo-periphery, and caddy as
  of 2026-09-04 — see each app's own section above.
- `local.env.example` — copy to `.env.local` and fill in. Has
  `CELLAR_LAN_IP`, `SILO_LAN_IP` (added 2026-09-04 for komodo-periphery),
  `TZ`, `DOMAIN` as of 2026-09-04 — grows further as apps are added, same
  as silo's did.
- `.gitignore` — same rules as sieve's/silo's: `.env.local`,
  `*/secrets.env.local`, and rendered `*/config/*` (except the tracked
  `.template` sources) are never committed.

## First-time setup on cellar

Once cellar exists and has at least one app built:

```
git pull
./setup-secrets.sh
```

Same one-command flow as silo — see stacks/silo/README.md's "First-time
setup on silo" section for what this actually does step by step (the
script itself is identical).

## Known gaps / things to double-check before relying on this

- **Vaultwarden has zero fallback access as of 2026-09-04** -- its old
  `http://<CELLAR_LAN_IP>:8000` is gone, and it's only reachable through
  `caddy` now. Until `caddy` is up AND sieve's Pi-hole has the
  `vault.${DOMAIN}` Local DNS Record (see caddy's own section), there is
  no way to reach it at all -- not a partial gap, a full outage until
  both exist.
- **Caddy's own image is built locally, not pulled** (`docker compose
  build`) -- unlike every other image in this fleet, its freshness isn't
  pinned or tracked by Diun (Diun watches image tags, not what a local
  Dockerfile's `xcaddy build` step happened to pull in at build time).
  Re-run `docker compose build --no-cache caddy` periodically by hand.
- **SMB's ports (139/445) carry the same Docker-NAT-bypasses-ufw
  exposure found on silo 2026-09-04** (see silo's README/the runbook for
  the full finding) -- any `ufw allow`/`deny` rule on these ports is
  currently a no-op, same as it was for Komodo. Not fixed here: SMB
  requires its own login (`ACCOUNT_barista`'s password) regardless, so
  this isn't the same "wide open with zero protection" situation
  Scrutiny was in on silo, but it's worth knowing the port itself isn't
  actually LAN-scoped by ufw the way the table might suggest.
