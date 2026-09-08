# This week's fleet reinit plan

Scope: sieve, silo, cellar, percolator, mochaPot get a full OS reinit this
week. Roastery is a fully decoupled parallel track (its own rebuild, not
sequenced with the 5 nodes below). Ristretto is parked -- dead hardware,
excluded entirely.

## What changed before this rebuild, and why it matters

Two real bugs, found and fixed during a pre-reinit audit (not just
documentation) -- see runbook.md's 2026-09-07 entry for the full story:

- **`stacks/sieve/generate-secrets.sh`** used to require running the
  *entire* script under `sudo` to get one `docker run` call (OIDC secret
  hashing) working, because `barista` is deliberately not in the docker
  group. That silently made every file the script touched that run
  root-owned -- including apps needing zero privilege. Fixed: only that
  one line now runs via `sudo docker run`; run the script as plain
  `barista` from now on, never `sudo ./generate-secrets.sh` as a whole.
- **`render-configs.sh` on all 7 nodes** used to abort rendering
  everything else the moment any single app's `secrets.env.local` failed
  to read (e.g. from the ownership bug above). Fixed and tested: one
  app's failure is now reported clearly and skipped; everything else
  still renders, and the script exits non-zero with a full list of what
  failed. **Always check the exit code / read to the end of the output**
  -- a clean-looking run with no errors is now a real guarantee, not an
  assumption.

Also fixed: `README.md`, `RECOVERY.md`, and
`initialization/purrbrews-init.sh` still described the SOPS+age
secrets-in-git design dropped 2026-09-02 -- corrected to match how secrets
actually work (generated locally per node, never encrypted-in-git,
a printed copy-paste table for the one cross-node OIDC-secret case).

**Repass (2026-09-07, done while User Penguin was out) found three more
real gaps, now fixed** -- see that day's runbook entry for the full
detail:

- `initialization/purrbrews-init.sh` was missing `jq` from the base apt
  install list, even though four of sieve's own bootstrap scripts require
  it -- would have failed a fresh sieve immediately.
- `stacks/mochaPot/local.env.example` was missing `SIEVE_LAN_IP`, which
  `mochaPot/traefik/`'s ForwardAuth has needed since 2026-09-06. Since
  `envsubst` doesn't error on an unset variable, a fresh mochaPot would
  have silently rendered a broken ForwardAuth address with no error at
  any step, breaking SSO gating for every Traefik-fronted app there. Now
  added, matching silo's/percolator's own `local.env.example`.
- `stacks/percolator/generate-secrets.sh`'s header and the
  `local.env.example` summaries in `percolator/README.md` and
  `mochaPot/README.md` had drifted stale (still describing each file's
  original scaffold, not what it actually grew into) -- corrected.

Everything else checked in the repass -- the other nodes'
`generate-secrets.sh`/`setup-secrets.sh`, sieve's remaining bootstrap
scripts, and the full OIDC secret pipeline end to end for all 11 apps
plus Headscale -- came back consistent, no further fixes needed.

**2026-09-08 update**: roastery was reformatted (its own planned rebuild,
see below) before the repass fixes above were pushed. They were lost from
the working tree and reapplied fresh via a small script rather than
redone from scratch -- see runbook.md's 2026-09-08 entry. This plan
itself is a from-scratch rewrite for the same reason; if you're reading a
version of it that predates 2026-09-08, that one may be more complete on
small details this rewrite didn't fully recall.

## Values to have on hand before starting (don't discover these mid-rebuild)

- One Cloudflare API token, `Zone:DNS:Edit` scope on ${DOMAIN}'s zone --
  reused across sieve/silo/cellar/percolator/mochaPot's Traefik/Caddy
  instances.
- `DOMAIN` itself.
- A `cloudflared tunnel token` for sieve's tunnel.
- Roundcube's real IMAP/SMTP host values (mochaPot).
- SSH keys already loaded (or a `ssh_authorized_keys.txt`/env var
  purrbrews-init.sh can read) for each node.
- The repo's remote clone URL.

## Order

sieve before silo is required -- Authelia and LLDAP have to exist before
anything else can SSO against them. After that, cellar/percolator/
mochaPot can go in any order -- each is gated only by silo's Komodo
issuing it a `PERIPHERY_ONBOARDING_KEY`, not by each other.

## Per-node sequence (the five Debian nodes)

1. Fresh OS install (manual).
2. SSH keys in place, repo remote URL known.
3. `sudo ./purrbrews-init.sh <node>` -- OS bootstrap: base packages
   (including `jq` now), Docker+Compose, the `barista` admin user
   (sudo-capable, deliberately NOT in the docker group), SSH hardening,
   static IP, git clone, `.env`/`DATA_DIR`/`MEDIA_DIR`, a morning
   `git pull --ff-only` cron, baseline UFW (SSH only).
4. `cd /opt/purrbrews/stacks/<node>`
5. **sieve only**: run `./generate-secrets.sh` then `./render-configs.sh`
   directly (no `setup-secrets.sh` wrapper on sieve).
   **Every other node**: run `./setup-secrets.sh` (chains
   `.env.local` creation, `REPLACE_ME` prompts, `generate-secrets.sh`,
   `render-configs.sh` in one step).
6. Bring up each app with `./compose.sh <app> up -d`, in that node's own
   README order -- not all-at-once, and not in arbitrary order; several
   apps have real setup steps (manual JWKS key generation for Authelia,
   OIDC secret paste-in from sieve's printed table, Local DNS Records in
   Pi-hole, etc.) that only make sense once the previous app is confirmed
   working.
7. Confirm each app's own success signal (padlock/cert issuance, a real
   login, `docker logs` showing real activity -- not just "container
   started") before moving to the next one.

## Known gaps to actually resolve this time, not defer again

- **Fleet-wide**: Docker's own iptables DNAT for published bridge-network
  ports bypasses `ufw` entirely (confirmed on silo 2026-09-04). Only
  silo's Scrutiny/Homepage/Speedtest-tracker are actually fixed (routed
  through Traefik + Docker-internal DNS instead of a published port).
  Worth deciding fleet-wide during this rebuild rather than carrying the
  same gap into every node again.
- UID/GID reconciliation for NFS/SMB-shared data directories across
  nodes -- flagged before, never actually resolved.
- OIDC login testing order -- test each app's login promptly after its
  secret handoff, not batched at the end, so a broken handoff is caught
  against the app it broke, not three apps later.

## Roastery (separate track -- any time this week)

Format + rebuild: immich-ml, Jellyfin (LAN-only, no Traefik front end),
join the fleet's Headscale tailnet. Not sequenced with the 5 nodes above.
This is the track that actually started 2026-09-08 (ahead of the other
5), and needs finishing.

## Ristretto -- parked

Dead hardware (Pi Zero W). Excluded from this week's work entirely. A
future "ntfy plan" was floated, never designed -- not blocking anything
above.
