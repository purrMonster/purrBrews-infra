# Weekend plan — 2026-09-05 (Sat) to 2026-09-06 (Sun)

Goal: percolator fully working, mochaPot fully built and brought up,
ristretto brought online, and the fleet-wide loose ends (auth, DNS, backups,
the ufw gap) closed out or explicitly, knowingly deferred — not just
documented as a "known gap" again.

Check items off as you go (`- [x]`). Update this file directly; it's
tracked in git like everything else here. When something turns out to be
already done, or done differently than planned, note it inline rather than
just checking the box silently — same discipline as the runbook.

---

## 0. Quick wins — do these first, each is 5–15 minutes

- [ ] **Apply the two fixes already sitting ready from today**, if not
      done yet: (a) `pihole-dns-bootstrap.sh` on sieve, with
      `PERCOLATOR_LAN_IP` filled in, so `nextcloud`/`paperless`/
      `homeassistant`.${DOMAIN} actually resolve; (b) `git pull` +
      `./compose.sh <app> up -d` on percolator for all three, to pick up
      today's Traefik labels.
- [ ] **Scrutiny's `SCRUTINY_DISK_DEVICE`** on silo — diagnosed days ago,
      never applied: `echo 'SCRUTINY_DISK_DEVICE=/dev/sda' | sudo tee -a
      .env.local && sudo ./compose.sh scrutiny up -d`.
- [ ] **Confirm Diun is actually up on silo**, not just documented —
      `docker logs diun --tail 50`, look for a completed scan, not a
      docker-socket-proxy connection error.
- [ ] **Confirm `lldap-bootstrap.sh` has been run for real** (creates
      `LLDAP_INFRA_ADMIN_GROUP` + the `barista` account via lldap's API) —
      if it's only ever been `--dry-run`'d, Authelia's group-based access
      control for infra-admin-only surfaces (`pihole.${DOMAIN}`,
      `traefik.${DOMAIN}`) has nothing real to check against.

## 1. Finish percolator

- [ ] Verify all three hostnames load in a real browser with a valid
      padlock: `nextcloud`/`paperless`/`homeassistant`.${DOMAIN}.
- [ ] Nextcloud: complete the first-run install wizard, then set
      `trusted_proxies`/`overwriteprotocol`/`overwritehost` in
      `/srv/data/nextcloud/config/config.php` (can't be set before the
      wizard creates that file).
- [ ] Home Assistant: complete onboarding, then add both deferred manual
      steps to `configuration.yaml` — the Postgres `recorder: db_url` block
      AND `http: trusted_proxies` — restart once after both.
- [ ] Paperless: log in as `barista`/`PAPERLESS_ADMIN_PASSWORD`, confirm a
      test PDF actually gets consumed from `/srv/data/paperless/consume`.
- [ ] Decide, deliberately, whether any of the three get Authelia's
      ForwardAuth middleware layered on top of their native login (left
      off today on purpose, revisit as a real choice, not an oversight).
- [ ] Known, accepted gap for later, not this weekend: `gotenberg`/`tika`
      for Paperless's non-PDF conversion, and non-English OCR language
      packs — both optional, PDF-only consumption works fine without them.

## 2. Build and bring up mochaPot — the bulk of the weekend

Nothing on mochaPot has ever been brought up against real hardware yet —
every compose file here is written and YAML-validated only. Do
`./setup-secrets.sh` first if you haven't (fills `MOCHAPOT_LAN_IP`,
`MOCHAPOT_RENDER_GID`, `SILO_LAN_IP`, `DOMAIN` into `.env.local`).

- [x] `komodo-periphery` — **up 2026-09-05.** bring up first, same now-confirmed mechanism as
      cellar/percolator/sieve (`core.pub` copied from silo). Quick, low-risk,
      and gets mochaPot showing up in Komodo's UI immediately.
- [x] `immich` — **up 2026-09-05** (server; ML worker connection to roastery still to verify — see §2b). first-ever bring-up of yesterday's restructured file
      (its own colocated `postgres-immich` + dedicated `valkey`, no more
      cross-host percolator dependency). Watch `depends_on:
      condition: service_healthy` actually gate startup correctly.
      `IMMICH_MACHINE_LEARNING_URL` still points at a roastery ML worker
      that doesn't exist — expected, ML features (face/object search) stay
      off until that's built separately; not a blocker.
- [ ] ~~`jellyfin`, `musicassistant` — bring up together~~ — **Jellyfin
      moved to roastery 2026-09-05** (Quick Sync struggled decoding video
      in an earlier real deployment; roastery's RTX 3080 is a materially
      stronger transcode path, and its GPU passthrough is already
      confirmed working). See §2b below. `musicassistant` still belongs
      here, on its own: `sudo ./compose.sh musicassistant up -d`. **Up 2026-09-05.**
- [x] `vikunja`, `freshrss`, `mealie`, `actualbudget`, `stirlingpdf` — **all up 2026-09-05.** Still owed: actually change Mealie's and Stirling PDF's default logins, not just "checked" them. no
      known interdependencies, any order. Check each one's DEFAULT LOGIN
      STATE as the first step before anything else, same standing
      discipline established on silo (some of these may ship an open
      setup wizard or a documented default account — Mealie specifically
      is noted to have one).
- [x] `n8n` — **up 2026-09-05.** needs `N8N_ENCRYPTION_KEY` from `generate-secrets.sh`,
      confirm it generated correctly and persists across a container
      restart (a changed key invalidates existing workflows/credentials).
- [x] `roundcube` — **up 2026-09-05.** needs real external SMTP values
      (`ROUNDCUBE_SMTP_HOST` etc., prompted by `generate-secrets.sh`, not
      generatable) — have your actual mail provider's settings ready.
- [x] `traefik` — **up 2026-09-06.** No `traefik.enable=true` labels
      here (mochaPot has no `providers.docker` — routing is hand-written
      `http.routers`/`http.services` pairs in `dynamic.yml.template`
      instead). `pihole-dns-bootstrap.sh`'s `HOST_TARGETS` got mochaPot's
      nine hostnames added on sieve *before* this bring-up this time, not
      after — learned that lesson from percolator's
      DNS_PROBE_FINISHED_NXDOMAIN detour. Still to confirm: every
      hostname actually loads with a valid padlock in a real browser.
- [ ] Decide Authelia gating per mochaPot app, same open call as
      percolator's three.

## 2b. roastery — Immich ML worker (added 2026-09-05)

Not part of the original weekend scope, but built today alongside
mochaPot since it's a hard dependency for Immich's face-recognition/smart-
search features. First-ever app on roastery — see
`stacks/roastery/README.md` for the full walkthrough; this is a summary
checklist.

- [ ] On sieve: generate a headscale pre-auth key for `barista`
      (`sudo docker exec headscale headscale preauthkeys create --user
      barista --expiration 1h`).
- [ ] On roastery, in WSL2: enroll with `tailscale up
      --login-server=https://headscale.${DOMAIN} --authkey=<key>`, then
      record `tailscale ip -4` as `ROASTERY_TAILNET_IP`.
- [ ] `cd stacks/roastery && chmod +x *.sh && ./setup-secrets.sh` — fill
      in `ROASTERY_TAILNET_IP` when prompted.
- [ ] Verify GPU passthrough BEFORE first bring-up: `nvidia-smi` (driver
      >=545), then `docker run --rm --gpus all
      nvidia/cuda:12.3.1-base-ubuntu22.04 nvidia-smi` (should show the RTX
      3080 from inside a container — if not, fix Docker Desktop's GPU
      support first, don't bring up immich-ml against a silent CPU
      fallback).
- [ ] `./compose.sh immich-ml up -d`, confirm with `./compose.sh immich-ml
      logs -f` and `curl http://<tailnet IP>:3003/ping`.
- [ ] On mochaPot's Immich Admin UI (Administration → Settings → Machine
      Learning Settings): confirm the ML worker URL, then set a job
      concurrency cap (initiation.txt Risk R10 — not doable from a
      compose file).
- [ ] Also fill mochaPot's own `.env.local`'s `ROASTERY_TAILNET_IP` (added
      2026-09-05 — was referenced in a comment there since 2026-09-03 but
      never actually declared, now fixed).
- [ ] Known unconfirmed: the `immich-machine-learning:v3.0.2-cuda` image
      tag hasn't been checked against a real `docker pull` — if it 404s,
      check github.com/immich-app/immich/pkgs/container/immich-machine-learning
      for the closest real tag.

### 2c. roastery — Jellyfin, moved from mochaPot (added 2026-09-05)

Quick Sync struggled decoding video in an earlier real deployment on
percolator — moving Jellyfin to roastery's RTX 3080 instead. See
`stacks/roastery/README.md`'s Jellyfin section for the full walkthrough.

- [ ] Fill in `ROASTERY_MEDIA_PATH` in roastery's `.env.local` (WSL2 path
      to your media library, e.g. `/mnt/d/Media`).
- [ ] `./compose.sh jellyfin up -d`, complete the first-run setup wizard
      at `http://<roastery LAN IP>:8096`.
- [ ] In Jellyfin's Admin Dashboard → Playback, set hardware acceleration
      to NVENC and confirm codec options populate.
- [ ] Play something that actually needs transcoding and watch
      `nvidia-smi` on roastery during playback — confirm a process shows
      up under the GPU, not a silent CPU fallback (the exact failure mode
      percolator's Quick Sync had, just now on different hardware if it
      recurs).
- [ ] `git rm -r stacks/mochaPot/jellyfin` once you're confident roastery
      is the version to keep — it's currently a non-functional stub, not
      deleted (device-bridge tooling can't delete files).

## 3. Ristretto — deploy LAST, once the rest of the fleet has real
       endpoints worth monitoring (this is initiation.txt's own explicit
       sequencing, Section 18.7 — not just a scheduling convenience)

**Flag before starting**: `stacks/ristretto/` currently has the generic
Docker-based `compose.sh`/`generate-secrets.sh` scaffolding copied
verbatim from silo — but ristretto is a Raspberry Pi Zero W, ARMv6,
native-binaries-only, no Docker at all (confirmed, initiation.txt Section
17/18.1/18.7). That scaffolding doesn't apply here and shouldn't be used;
ristretto needs a different provisioning approach entirely (systemd units
running native binaries, not docker-compose). Worth deciding now whether
to delete/ignore that scaffolding or repurpose the directory just for
config/docs, before building anything on the actual hardware.

- [ ] Confirm ristretto is flashed (`rpi-imager --cli`, per Section 18.1)
      and has basic hardening done (SSH keys, updates, a static IP) — this
      may already be done; check before assuming it isn't.
- [ ] Install **Gatus** (native ARMv6 binary, no Docker) — configure it to
      check every other node's real endpoints: each Traefik-fronted
      hostname fleet-wide (sieve/silo/cellar/percolator/mochaPot's apps),
      plus raw TCP/ping checks for anything without HTTP.
- [ ] Install **ntfy** (native ARMv6 binary) — wire it as Gatus's alerting
      target, and confirm you actually get a push notification on your
      phone from a deliberately-broken test check before trusting it for
      real incidents.
- [ ] Document ristretto properly in its own README once real, the same
      structure every other node's README uses — it currently has none of
      that, just the scaffolding stub's disclaimer.

## 4. Fleet-wide fine-tuning — interleave with the above as time allows

- [ ] **The Docker-NAT-bypasses-ufw gap** — raised repeatedly (Komodo
      9120, Authelia 9091, SMB 139/445, and now implicitly every
      Traefik-fronted app) without ever being resolved. Make an actual
      decision this weekend: either a real fix (e.g., DOCKER-USER iptables
      chain rules, which Docker respects unlike plain `ufw`), or a
      written, deliberate "accepted risk, LAN is the trust boundary"
      call — but stop letting it recur as a bullet with no resolution.
- [ ] **Vaultwarden** — confirm the `vault.${DOMAIN}` DNS entry (already
      in today's Pi-hole run) actually resolves and Caddy serves it, then
      start migrating real household passwords in if you haven't.
- [ ] **Cellar's backup mirror job** — confirm the local secondary backup
      (initiation.txt Section 18.4) is actually scheduled and has run at
      least once, not just present in a compose file.
- [ ] **Headscale + Cloudflare Tunnel** — confirm sieve's external-exposure
      layer (deliberately built last in sieve's own sequence) is actually
      live and tested from outside your LAN, not just configured.
- [ ] **Authelia access-control policy** — review it against the fleet's
      *current* real app list; it was written early and the app count has
      grown a lot since (percolator's three, mochaPot's eleven).
- [ ] **Scrutiny's SMART "Failed" status** — the debugging you deferred
      earlier this week. Once `SCRUTINY_DISK_DEVICE` (Quick win #1 above)
      is applied and Scrutiny is reading the right device, actually look
      at whether "Failed" is a real early warning on that drive or a
      Scrutiny misconfiguration — don't let a real disk failure hide
      behind an assumed tooling bug.
- [ ] **Multi-host Scrutiny (added 2026-09-05)** — compose files are
      written for `sieve`/`cellar`/`percolator`/`mochaPot`'s
      `scrutiny-collector` (sieve was nearly missed — it's a separate
      physical host with its own disk too, silo being the hub doesn't
      exempt it), and silo's own `scrutiny` republishes port 8080 as the
      hub. Still needed: confirm real disk device paths via `lsblk` on
      each of the four nodes (`.env.local` placeholders are unfilled),
      bring each collector up, and confirm all disks show up in silo's
      Scrutiny UI. Also: this reopened a deliberately-closed zero-auth
      port on silo — worth actually resolving via the ufw gap fix above
      rather than leaving it as a second accepted-risk port.

---

## Suggested sequencing across the two days

**Today (remaining):** Section 0 (quick wins) in full, then Section 1
(percolator) in full — it's nearly done already, finishing it is cheap
and clears mental space for mochaPot.

**Tomorrow:** Section 2 (mochaPot) — the biggest single block, budget most
of the day for it — then Section 3 (ristretto) once mochaPot's apps give
it something real to monitor. Section 4 items are fill-in work between or
after the above, not a separate time block — pull one whenever you're
blocked waiting on something else (e.g. an image pull, a DNS propagation
wait).
