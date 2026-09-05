# roastery

Gaming + opportunistic-AI node (Ryzen 5 5600F, RTX 3080 10GB, Windows +
WSL2 + Docker Desktop). Unlike every other node in this fleet, roastery is
the user's own daily driver, not dedicated server hardware — apps here are
resource-capped so gaming isn't affected, and this node stays **Headscale
tailnet-only, no public exposure** (initiation.txt Risk R9: Vanguard
anti-cheat on this machine widens the attack surface of anything exposed
here, so nothing on roastery is reachable from the LAN or the internet,
only from other tailnet members).

First app built here, 2026-09-05: **immich-machine-learning**, the
GPU-accelerated ML worker for mochaPot's Immich instance (face
recognition, smart search) — per initiation.txt's own architecture,
`immich-server` on mochaPot calls out to roastery over the tailnet for
inference rather than running it on mochaPot's own CPU.

Second app, same day: **Jellyfin**, moved here from mochaPot's original
plan — Quick Sync transcoding struggled noticeably in an earlier real
deployment on percolator's same-generation iGPU (user's own report), and
roastery's RTX 3080 is a materially stronger NVENC/NVDEC transcode path.
See initiation.txt's Section 0.3 correction note and the runbook's
2026-09-05 entry for the full reasoning. Unlike immich-ml, Jellyfin is
reachable on the normal LAN (real authentication, not the ML worker's
zero-auth situation) — only immich-ml is tailnet-restricted.

Ollama is planned here too (initiation.txt) but not built yet.

**Correction to initiation.txt, found while building this (2026-09-05):**
the doc lists roastery's stack as needing "NVIDIA Container Toolkit."
Immich's own current hardware-acceleration docs
(docs.immich.app/features/ml-hardware-acceleration/) state Windows/WSL2
only needs the NVIDIA driver itself (>=545, CUDA >=12.3) — Docker
Desktop's built-in WSL2 GPU support handles the rest, no separate
Container Toolkit package. Not fixed in initiation.txt itself here (same
discipline as the cellar-disk and other mismatches found elsewhere —
flagged, not silently rewritten) — worth a real driver-version check on
roastery before assuming this is settled.

## What's here

- `compose.sh` — wrapper so `immich-ml`'s docker-compose.yml sees the
  shared `.env.local` plus its own `secrets.env.local`. Same pattern as
  every other node's compose.sh, **with one deliberate difference**: it
  does not create a shared docker network. See its own header comment for
  why — no roastery app currently needs to reach another roastery app by
  container name.
- `render-configs.sh` — renders `*.template` files into their real
  counterparts. No app here has one yet; kept for consistency and for
  whenever Ollama gets added.
- `setup-secrets.sh` — one-command first-time setup: creates `.env.local`
  from `local.env.example`, prompts for any `REPLACE_ME`, runs
  `generate-secrets.sh`, then `render-configs.sh`. Copied from silo's
  version of this script (identical logic, silo-specific wording
  adjusted).
- `generate-secrets.sh` — currently near-empty: immich-ml needs zero
  secrets (no auth of any kind — see its own compose file's comment and
  the security note below). Kept as a real file so `setup-secrets.sh`'s
  chained flow works the same as every other node, and so Ollama has a
  place to add secrets later if it ever needs one.
- `immich-ml/` — the GPU-accelerated ML worker for mochaPot's Immich.
- `jellyfin/` — media server, moved here from mochaPot 2026-09-05 (see
  intro above).

## Before you bring anything up: this is not like the other nodes

Every other node in this fleet is Linux hardware reached over SSH, where
Claude edits files directly via the device bridge and you run the actual
`docker compose` commands over SSH yourself. **roastery is different**:
it's your own Windows/WSL2 machine, and the device-bridge shell Claude
uses here runs in an isolated sandbox VM — it can read and write files in
this repo, but it cannot run Docker, cannot see your GPU, and cannot
enroll this machine in Headscale. Every step below that touches Docker,
the GPU, or the network has to be run by you, in your own WSL2 terminal.

## Enroll roastery in Headscale (do this first — nothing else works without it)

immich-ml's port is deliberately bound to roastery's *tailnet* address,
not `0.0.0.0` (see immich-ml/docker-compose.yml's own comment on why —
short version: the container has no authentication at all, so the tailnet
binding is the only thing standing between it and anyone who can reach
this machine). That means you need a real tailnet IP before
`docker compose up` will even start.

1. Make sure Tailscale is installed in your WSL2 distro (or use Windows
   Tailscale directly, if you'd rather run the client outside WSL2 —
   either works, `tailscale ip -4` reports the same address either way).
2. Generate a pre-auth key **on sieve** (the `barista` headscale user
   already exists — created 2026-08-30, no need to create it again):
   ```sh
   sudo docker exec headscale headscale preauthkeys create \
     --user barista --expiration 1h
   ```
3. On roastery:
   ```sh
   sudo tailscale up --login-server=https://headscale.${DOMAIN} \
     --authkey=<key from step 2>
   ```
4. Confirm and record the address:
   ```sh
   tailscale ip -4
   ```
   That's your `ROASTERY_TAILNET_IP`.

**Namespace call, flagged not silently assumed:** step 2 reuses `barista`
(the namespace every other fleet server node uses), on the reasoning that
roastery — while your daily driver — is acting as a fleet server here,
the same role as sieve/silo/cellar/percolator/mochaPot. `penguin` (your
personal-device namespace) would also work, since no ACL policy exists
yet to make the choice functionally different either way (see
stacks/sieve/README.md's headscale-bootstrap.sh section). If you'd rather
keep roastery under `penguin` since it's not dedicated server hardware,
that's a one-line change to step 2 — say so and it's easy to redo before
anything depends on it.

## First-time setup on roastery

In WSL2, from this directory:

```sh
chmod +x *.sh   # same NTFS-no-executable-bit reason as every other node
./setup-secrets.sh
```

Then fill in `.env.local`'s `REPLACE_ME` by hand:

- `ROASTERY_TAILNET_IP` — from the Headscale enrollment above. Only
  needed for immich-ml; Jellyfin doesn't use it.
- `ROASTERY_MEDIA_PATH` — the WSL2 path to your existing media library
  (e.g. `/mnt/d/Media`). Only needed for Jellyfin.

(`TZ` already defaults to `Asia/Kolkata`, same as every other node — change
it if that's wrong for you.)

## Bringing immich-ml up

Verify your GPU is actually visible to Docker Desktop before the first
real bring-up — this is the step initiation.txt's Risk R10 warns about
(silent CPU fallback if GPU passthrough is misconfigured, which looks
identical to "it's working" until you notice inference is much slower
than it should be).

**Corrected 2026-09-05** — there is no GPU-support toggle in Docker
Desktop's settings (this file originally said there was; there isn't —
confirmed against Docker's own current docs at
docs.docker.com/desktop/features/gpu/ after the user looked and didn't
find one). GPU support on Windows/WSL2 is automatic once three
prerequisites hold, not something you switch on:

1. WSL2 backend enabled — Settings → General → "Use the WSL 2 based
   engine" (on by default in current Docker Desktop versions).
2. A current NVIDIA driver installed on Windows itself (not inside
   WSL2) that supports WSL2 GPU Paravirtualization. Check with
   `nvidia-smi` in PowerShell — if it runs and shows the RTX 3080,
   you're very likely fine.
3. WSL2's own kernel up to date — from an elevated PowerShell:
   `wsl --update`.

Once those three hold, there's nothing left to configure — just verify:

```sh
docker run --rm --gpus all nvidia/cuda:12.3.1-base-ubuntu22.04 nvidia-smi
```

That should print your RTX 3080 from inside a container. If it fails
(e.g. "could not select device driver with capabilities: [[gpu]]"),
it's almost always #2 or #3 above, not a missing setting — fix that
before bringing up immich-ml.

```sh
./compose.sh immich-ml up -d
```

No web UI to visit — this container is a backend inference service only,
with nothing to log into. Confirm it's alive with:

```sh
./compose.sh immich-ml logs -f
curl http://<its tailnet IP>:3003/ping
```

Then, on mochaPot, in Immich's own Admin UI (Administration → Settings →
Machine Learning Settings), confirm the URL field shows
`http://${ROASTERY_TAILNET_IP}:3003` (already set via
`IMMICH_MACHINE_LEARNING_URL` in mochaPot's immich/docker-compose.yml, but
the maintainers call that env var deprecated — the UI is the
forward-looking way to confirm/change it). Once connected, also set a job
concurrency cap there (Job Settings) per Risk R10 — this compose file has
no way to pre-configure that.

## Bringing Jellyfin up

Same GPU-passthrough prerequisites as immich-ml above (WSL2 backend, a
current NVIDIA driver, `wsl --update`) — if `docker run --rm --gpus all
nvidia/cuda:12.3.1-base-ubuntu22.04 nvidia-smi` already worked for
immich-ml, nothing further to check here.

Fill in `ROASTERY_MEDIA_PATH` in `.env.local` first (see "First-time
setup" above) — decide now whether it points at a folder that already has
real media in it, or an empty one you'll copy into afterward.

```sh
./compose.sh jellyfin up -d
```

UI: `http://<roastery LAN IP>:8096`. No default credentials — first-run
setup wizard creates the admin account, same as mochaPot's original plan.

**Confirm NVENC is actually being used, not a silent CPU fallback** — the
same class of failure mode as immich-ml's Risk R10 concern, just for video
transcoding instead of ML inference: in Jellyfin's Admin Dashboard →
Playback, set the Hardware acceleration dropdown to NVENC and confirm the
codec checkboxes below it populate (if NVENC isn't even offered as an
option, the GPU reservation isn't reaching the container — check
`docker logs jellyfin` for an NVIDIA-related error first). Then actually
play something that needs transcoding (a codec/resolution your playback
device doesn't support directly) and watch `nvidia-smi` on roastery during
playback — you should see a process appear under the GPU's process list.
If nothing shows up there during playback despite NVENC being selected,
it's transcoding on CPU regardless of the setting, and worth digging into
before trusting it — this is exactly the failure mode that made Quick
Sync on percolator disappointing without ever throwing a visible error.

## Security note (read before exposing immich-ml any further than it already is)

Immich's own docs state this container plainly: **"The machine learning
container has no security measures whatsoever. Please be mindful of where
it's deployed and who can access it."** No login, no API key, nothing.
The tailnet-only port binding in immich-ml/docker-compose.yml is the
entire mitigation — don't republish this port to `0.0.0.0` or to
roastery's LAN interface for convenience later without re-deriving a new
mitigation first. Jellyfin doesn't have this problem — it has real
authentication, which is exactly why it's LAN-reachable instead.

## Known gaps

- Ollama (initiation.txt's other planned app for this node) isn't built
  yet — this directory currently has two apps (immich-ml, jellyfin).
- Jellyfin's `capabilities: [gpu, video, compute, utility]` GPU
  reservation is not confirmed against a real bring-up — immich-ml's
  simpler `[gpu]`-only reservation is proven working (2026-09-05), but
  NVENC/NVDEC hardware video encode/decode is a genuinely different
  capability set and hasn't been tested. If NVENC doesn't show up as an
  option in Jellyfin's dashboard, this is the first thing to revisit.
- No media has been migrated to `ROASTERY_MEDIA_PATH` yet — this is a
  fresh path, not a move of any existing library (mochaPot's own Jellyfin
  was never actually brought up, so there's nothing to migrate from
  there either).
- Whether losing mochaPot's "kiosk locality" (running Jellyfin's server
  co-located with its touchscreen) is noticeable in practice hasn't been
  evaluated — the kiosk can still run a Jellyfin client pointed at
  roastery over the LAN, just not against local-loopback latency.
- The `immich-machine-learning:v3.0.2-cuda` image tag pinned in
  immich-ml/docker-compose.yml hasn't been confirmed to exist against a
  real `docker pull` — Immich's release/tag scheme strongly suggests it
  does (every image in a release ships matching version tags), but this
  wasn't verified against the actual container registry before writing
  the file. If the pull fails, check
  github.com/immich-app/immich/pkgs/container/immich-machine-learning
  for the closest real tag.
- GPU reservation (`deploy.resources.reservations.devices`) has not been
  tested against a real bring-up yet — first real test is whatever
  bring-up happens next, per the "verify before trusting it" step above.
- Job concurrency capping (Risk R10) has to be set by hand in Immich's
  Admin UI after first connection; nothing in this compose file enforces
  it.
- No resource limits (`deploy.resources.limits`) are set on the container
  itself yet, despite initiation.txt's "resource-capped so gaming isn't
  affected" framing for this node generally — worth adding once you've
  seen real GPU/CPU usage under an actual photo-library scan, rather than
  guessing a number now.
