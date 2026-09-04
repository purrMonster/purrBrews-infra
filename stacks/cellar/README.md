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

```sh
sudo mkdir -p /srv/data/vaultwarden
./compose.sh vaultwarden up -d
```

Reachable at `http://<CELLAR_LAN_IP>:8000`. First real account you create
there is the one to keep -- **then manually set `SIGNUPS_ALLOWED=false`**
in `docker-compose.yml` and restart. Confirmed 2026-09-03 this doesn't
happen automatically; leaving it `true` means anyone on the LAN who finds
this URL can register their own account.

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
  runbook entry.) Currently has no per-app entries — nothing to generate
  yet.
- `local.env.example` — copy to `.env.local` and fill in. Minimal for now
  (`CELLAR_LAN_IP`, `TZ`, `DOMAIN`) — grows as apps are added, same
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

- The deploy-order guess above (cellar positioned after silo, before/after
  whichever of percolator/cellar/mochaPot/ristretto) is unverified against
  the initiation doc.
- No apps exist here yet — this whole directory is untested scaffolding,
  copied from a working silo setup but never itself run through
  `setup-secrets.sh` or `compose.sh` against a real host.
- If cellar will run a Komodo Periphery agent (so silo's Komodo Core can
  manage it), see `stacks/_templates/komodo-periphery/docker-compose.yml`
  — copy it into an app subdirectory here once cellar exists and fill in
  its `REPLACE_ME` values.
