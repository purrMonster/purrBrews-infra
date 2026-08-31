# stacks/silo — security, QoL & fleet ops (Section 18.3)

Second node in deploy order (sieve → **silo** → cellar → percolator →
mochaPot → ristretto). Same tooling as `stacks/sieve` — see that stack's
README for the general pattern (`compose.sh`, `render-configs.sh`,
`.env.local`/`secrets.env.local` split). This file only covers what's
silo-specific: setup, secrets, and the bring-up steps for each app.

Apps come up in this order:

1. **unbound** — recursive resolver feeding sieve's Pi-hole; no dependencies
2. **homepage** — stopgap dashboard; not part of Section 18.3's own sequence, brought up early since it doesn't depend on or block anything
3. crowdsec, netalertx, speedtest tracker, komodo, scrutiny, diun — not built yet

For the "why" behind any choice below (image picks, networking mode,
config approach, secrets model) see the dated runbook entries linked
inline — this file is deliberately just the how.

## Secrets: SOPS+age

Different from sieve's stack (plain gitignored local generation) — see
`secrets/README.md` for the full layout and the runbook's 2026-08-31
"Moving to silo" entry for why. Two steps, split across where each has to
run:

1. **On roastery**: add a `Set-SopsSecretIfAbsent` call to
   `generate-secrets.ps1` for any new secret, run it, `git add`/commit/push.
2. **On silo**, after `git pull`: `./decrypt-secrets.sh` before
   `./render-configs.sh` — needs the age private key at
   `/etc/purrbrews/age/keys.txt` (copied from sieve once, per
   `secrets/README.md`).

## First-time setup on silo

```sh
cd /opt/purrbrews/stacks/silo
chmod +x *.sh   # harmless if already set — see stacks/sieve/README.md's note on why

command -v sops || echo "sops not installed — see secrets/README.md"

cp local.env.example .env.local
# Fill in by hand:
#   SILO_LAN_IP   this node's real LAN IP
#   DOMAIN        same real domain as stacks/sieve/.env.local
# SIEVE_LAN_IP is already defaulted (192.168.0.10) — only change it if that ever changes.

./decrypt-secrets.sh   # secrets/silo/*.sops.yaml -> */secrets.env.local (no-op until an app has one)
./render-configs.sh    # bakes SILO_LAN_IP/SIEVE_LAN_IP/DOMAIN into every config
```

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

## Known gaps / things to double-check before relying on this

- `unbound`'s `klutchell/unbound:main` tag is a rolling tag, not a version
  pin (no semver releases exist for this image) — revisit once Diun exists
  later in this same build order.
- `homepage` (port 3000) isn't routed through Traefik/Authelia yet — same
  standing gap as lldap's admin UI on sieve.
- `homepage` is a stopgap dashboard, not the real one — see the runbook
  backlog for the DIY replacement, still undesigned.
