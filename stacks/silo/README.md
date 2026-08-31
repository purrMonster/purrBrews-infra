# stacks/silo

silo's app stack. Second node in deploy order (sieve → **silo** → cellar → percolator → mochaPot → ristretto). Same per-app `docker-compose.yml` layout as `stacks/sieve` — see that stack's README for the general pattern (`compose.sh`, `render-configs.sh`, `.env.local`/`secrets.env.local` split) — this file only covers what's different for silo.

Apps land here as they're built, in the order from Section 18.3: Unbound → CrowdSec → NetAlertX + Speedtest Tracker → Komodo → Scrutiny + Diun. A dashboard app wasn't in that list — deliberately deferred 2026-08-31 in favor of building something custom later — but a **stopgap Homepage instance was added the same day** to have something usable in the meantime; see below. Nothing else is built yet as of this entry — this README currently documents the secrets tooling, shared scaffolding, and Homepage.

## `homepage/` — stopgap dashboard

[Homepage](https://gethomepage.dev) (`gethomepage/homepage`), chosen 2026-08-31 for simplicity over Homarr — plain YAML config, no database. This is explicitly a placeholder until the real DIY dashboard exists (still backlogged): swap it out later, don't build on top of it.

Host-published directly at `http://<SILO_LAN_IP>:3000` — no Traefik/Authelia in front of it yet, same interim pattern as lldap's admin UI on sieve. Needs a LAN-scoped ufw rule before it's reachable, same as every other host-published port in this project:

```
sudo ufw allow from 192.168.0.0/24 to any port 3000 proto tcp
```

Config lives at `homepage/config/*.yaml` (rendered by `render-configs.sh` from the tracked `*.template` files — `settings.yaml`, `services.yaml`). Deliberately minimal: `services.yaml.template` links to sieve's existing apps only (Traefik, Pi-hole, Headscale) — add silo's own apps to it as they get built. Homepage auto-creates any other config files it wants (e.g. `bookmarks.yaml`, `widgets.yaml`) on first run if they're missing; none are tracked here since none are needed yet.

`HOMEPAGE_ALLOWED_HOSTS` (in `docker-compose.yml`) is required as of Homepage 1.0 — it rejects any request whose `Host` header isn't in that list. Set to `${SILO_LAN_IP}:3000`; add a real hostname there too if this ever gets routed through Traefik.

Image pinned to `v1.13.2` (current release as of 2026-08-31, confirmed via GitHub releases, not guessed) — check for a newer tag before real deploy if enough time has passed, same caveat as every other pinned image in this project.

## Secrets: SOPS+age, not sieve's pattern

Unlike sieve (which generates secrets locally, plaintext, never committed — see `stacks/sieve/generate-secrets.sh`), silo onward uses SOPS+age: secrets are committed to the repo as ciphertext (`secrets/silo/<app>.sops.yaml`) and decrypted locally at deploy time. Decided 2026-08-31 — see `secrets/README.md` for the full layout and why the split, and `.sops.yaml` at the repo root for the encryption rule itself.

Two-step workflow, split across where each half has to run (no live coding on fleet nodes — Section 19.6):

1. **On roastery**, whenever an app needs a new secret: add a `Set-SopsSecretIfAbsent` call to `generate-secrets.ps1` (see its own comments for the pattern), run it, then `git add`/commit/push. The script only ever adds missing values — safe to re-run.
2. **On silo**, after `git pull`: run `./decrypt-secrets.sh`, then `./render-configs.sh` as usual. `decrypt-secrets.sh` needs the age private key at `/etc/purrbrews/age/keys.txt` (copied from sieve once, per `secrets/README.md`) — it'll tell you plainly if that's missing rather than failing cryptically.

Bring-up order for a fresh silo, once at least one app has secrets defined:

```
cp local.env.example .env.local   # fill in SILO_LAN_IP and DOMAIN
./decrypt-secrets.sh          # secrets/silo/*.sops.yaml -> */secrets.env.local (no-op until an app has one)
./render-configs.sh
./compose.sh homepage up -d   # first app up; the rest follow in Section 18.3 order
```
