# PurrBrews Runbook

Living operational reference for Project PurrBrews. Entries are dated as decisions are made; this keeps the "why" attached instead of just the "what." See the full initiation document set (`purrbrews-project-initiation-set_4.html`) for the charter/scope/architecture this runbook implements.

## Backlog / open items

Pulled up from the dated entries below so nothing gets lost in the log. Check items off (or just delete the line) as they're done — leave a dated entry below for anything worth remembering *why* about.

- [x] Confirm physical cabling matches the floor plan (Section 0.12) — done 2026-08-27
- [x] Run `purrbrews-init.sh` for real on sieve, silo, cellar — done 2026-08-28 per User Penguin, and extended to all five (sieve, silo, cellar, percolator, mochaPot) rather than just the original three. Not independently verified from this session (no SSH access to the fleet) — taken on report.
- [x] Generate + distribute the age keypair (on sieve, first) — exists on sieve per User Penguin (2026-08-28). Not yet used, though: sieve's own app-stack secrets (2026-08-28 entry below) ended up going a different route entirely — see that entry for why, and the new backlog item below for what this means for silo/cellar/percolator/mochaPot.
- [ ] Roastery WoL: BIOS Wake-on-LAN enable, ErP/EuP disable, Windows Fast Startup disable
- [ ] `wakeonlan` trigger on silo once it's live, exposed remotely (Homepage/n8n)
- [ ] `git init` / `add` / `commit` / `remote add origin` / `push` for `purrBrews-infra` on roastery
- [x] Fix `step_git_repo` in `purrbrews-init.sh` — done 2026-08-27, now clones from a configured remote instead of `git init`ing a disconnected repo (see dated entry below)
- [ ] Drop a `remote_url.txt` (or `.env.local`) with `PURRBREWS_REMOTE_URL` next to `purrbrews-init.sh` on each node before running it, so `step_git_repo` has something to clone
- [ ] Pull `llama3.2:3b` on americano/roastery (`ollama pull llama3.2:3b`) and confirm `ollama serve` is reachable at `localhost:11434`, so `scripts/purrbrews-commit.{sh,ps1}` has something to talk to — this is now the script's default model, chosen for speed (see 2026-08-27 entry)
- [ ] Dry-run `scripts/purrbrews-commit.{sh,ps1}` at least once (`--dry-run`/`-DryRun`) with `llama3.2:3b` before trusting it unattended — confirm it's actually fast now, and that a 3B model's commit messages are good enough quality; bump to `--model qwen2.5:7b` if not
- [ ] Build the nightly runbook-entry job — a stronger model, more context (a day's worth of commits, not one diff at a time), separate from `purrbrews-commit.{sh,ps1}` entirely (see 2026-08-27 entry)
- [ ] Set up non-interactive git credentials for `barista` on each node (HTTPS + private GitHub repo needs a stored credential — `git config credential.helper store` after one manual authenticated pull with a PAT, or switch the remote to SSH with a read-only deploy key) — without this the new morning `git pull` cron (`step_cron_pull`) fails every run (see 2026-08-28 entry)
- [ ] Confirm each node's timezone (`timedatectl`) once provisioned, so the `06:15` morning pull cron actually lands in the morning
- [ ] On sieve: fill in `stacks/sieve/.env.local` (DOMAIN) and the two Cloudflare values (`traefik/secrets.env.local` CF_DNS_API_TOKEN, `cloudflared/secrets.env.local` TUNNEL_TOKEN), then `./generate-secrets.sh && ./render-configs.sh` and bring the six apps up in order — see `stacks/sieve/README.md` (see 2026-08-28 entry)
- [ ] Check current image tags for pihole/lldap/authelia/traefik/headscale/cloudflared before first deploy on sieve — the versions pinned in this session's build (2026-08-28) were current *that day*; several months may have passed by actual deploy time
- [ ] Decide the secrets approach for silo/cellar/percolator/mochaPot's app stacks: SOPS+age as originally planned (Section 19.3, key already exists on sieve), or the plaintext-generated-at-runtime pattern used for sieve's own stack instead (2026-08-28 entry) — currently only decided for sieve, not the rest of the fleet
- [ ] Route lldap's admin UI (sieve, port 17170) through Traefik + Authelia instead of its current direct host-port exposure
- [ ] On sieve: run `docker network inspect sieve_proxy` to get its real subnet, then `sudo ufw allow from <subnet> to any port 8080 proto tcp` — required for Pi-hole's admin UI to work through Traefik at all, and is the entire security boundary now that Pi-hole's own password is disabled (2026-08-29 entry). Also confirm the DNS ufw rules (`53/tcp`+`53/udp`, LAN-scoped) from the same troubleshooting session got applied.
- [ ] Check Pi-hole's own docs (and whether a community fork exists) for a real reverse-proxy auth-trust mechanism (header-based or OIDC), as a more robust replacement for disabling its password outright (2026-08-29 entry) — checked: no support exists today, upstream or fork; disabling the password is the recognized workaround, not a stopgap (2026-08-30 entry)
- [ ] Bake Pi-hole's DHCP settings (range, router, lease time) into `pihole/docker-compose.yml` as `FTLCONF_dhcp_*` env vars, same durability reasoning as `FTLCONF_dns_upstreams` — **only after** confirming real devices are picking up leases cleanly from Pi-hole over a few days. Router's own DHCP was switched off 2026-08-30 to let this take over as leases expire; don't touch the compose file's DHCP config until that's proven stable — getting it wrong here means every device in the house loses DHCP, not just a test container (2026-08-30 entry). **Include the `67/udp` ufw rule (see 2026-08-30 outage entry below) explicitly in that "proven stable" check** — it's a separate thing from the FTL config and just as easy to lose on a rebuild.
- [ ] Run `./lldap-bootstrap.sh` for real on sieve and confirm it works against lldap's actual GraphQL API — written 2026-08-30 from lldap's documented schema, never exercised live (see that entry). If a call fails, the field/mutation name it names is the thing to fix.
- [ ] Emergency access USB — deferred, no target date set:
  - [ ] Generate emergency SSH keypair on roastery (`ssh-keygen`, passphrase-protected), send Claude the `.pub` to add to `ssh_authorized_keys.txt`
  - [ ] Decide number/location of physical USB copies
  - [ ] Build the `age -p`-encrypted archive per `RECOVERY.md`
  - [ ] Add `age/keys.txt` + each node's console password to it as those come into existence

---

## 2026-08-26 — Pre-deployment decisions (base node init, source control, Cowork operating model)

### 1. Base node initialization — sieve / silo / cellar

`purrbrews-init.sh` (delivered, in this folder) covers WBS 18.1 pre-deployment for the three Debian 13 M710Qs. Run as `sudo ./purrbrews-init.sh <sieve|silo|cellar>`.

**Decisions baked into the script:**

- **Admin account:** `barista` (not `penguin`) — chosen to keep the human/project persona separate from a literal Unix account visible in every shell prompt and log, and it fits the coffee-equipment naming theme (the barista operates sieve/silo/cellar/etc.). Gets `sudo` + `docker` group membership. A narrower automation-only account (e.g. for unattended `git pull && docker compose up -d`) was considered but deferred — cheap to add later, not needed for a one-person-managed lab yet.
- **Static IPs** (gateway `192.168.0.1`, all one `/24`, bootstrap DNS `1.1.1.1` until Pi-hole is live on sieve):

  | Node | IP |
  |---|---|
  | sieve | 192.168.0.10 |
  | percolator | 192.168.0.11 |
  | silo | 192.168.0.12 |
  | cellar | 192.168.0.13 |

  (mochaPot / ristretto / roastery not yet assigned — extend `NODE_IP` in the script when decided.)

- **SSH keys are NOT hardcoded in the script.** They load at runtime from `ssh_authorized_keys.txt` (same folder as the script, one public key per line) and/or the `$PURRBREWS_SSH_KEYS` env var. To add a new key later (e.g. for americano): add a line to that file and re-run the script on whichever node(s) need it — already-installed keys are left untouched. The script refuses to run if it finds zero keys anywhere, since it's about to disable SSH password auth.
- **Hardening applied:** SSH key-only login (password + root login disabled, original `sshd_config` backed up first), `unattended-upgrades` for automatic security patching, baseline UFW (deny incoming except SSH).
- **Docker + Compose:** installed from Docker's official apt repo, with an automatic fallback to the `bookworm` suite if `trixie` isn't listed yet.
- **Directories + repo skeleton:** `/opt/purrbrews` (`$PROJECT_DIR`), `/srv/data` (`$DATA_DIR`), `/srv/media` (`$MEDIA_DIR`) created with a shared `.env`; the full `stacks/<node>/<app>/` skeleton is `git init`'d locally on every node (see Section 3 below — this is provisional until the real remote exists).
- **age keypair:** generated exactly once, only when the script runs on `sieve` (first in deploy order). Running it on silo/cellar first just warns that the key isn't there yet and tells you to `scp` it over once it exists — it will never generate a second, inconsistent keypair.

**Not yet done:** physical cabling confirmation (Section 0.12), running the script for real on the three boxes, actually generating/distributing the age key.

### 2. Cowork operating model — what this means for day-to-day work

Clarified this session, worth keeping in mind for how tasks get assigned going forward:

- **Dispatch** (assigning a task that works against a specific computer's local files) requires that computer's Claude Desktop app open and the machine awake for the whole task — no way around this, it's how local file access works.
- **A cloud session** (like the one that did today's work) runs on Anthropic's servers regardless of whether any device is on, but it only reaches local files through a specific device's Desktop app, and only while that app is connected — folder connections are tied to whichever computer made them, not shared across devices.
- **Practical implication:** for anything that doesn't strictly need to touch a file that only exists on americano's or roastery's disk, moving "the project files" onto a git remote (Section 3) lets a cloud session — triggerable from mobile, no device needs to be on — clone/read/edit/push directly. This is the main reason the git remote decision below matters beyond just "keeping two laptops in sync."

### 3. Source control strategy — GitHub now, self-hosted later, GitHub becomes a public mirror after

Decided today, resolving the "wire up a remote later" gap left by the init script:

- **Now:** GitHub (private repo) is the canonical remote and source of truth for the full `purrbrews` repo — compose files, SOPS-encrypted secrets, this runbook, everything per Section 19.1. This unblocks real development immediately without waiting on cellar/silo to exist.
- **Immediate next step:** consolidate the three separately-`git init`'d local repos currently sitting on sieve/silo/cellar (an artifact of running `purrbrews-init.sh` on each before a remote existed) onto this one GitHub remote — pick whichever copy is most current as canonical, push it, then have every other node/machine `git remote add origin ...` and reset onto it rather than keeping independent histories.
- **Later, once cellar/silo can host it:** stand up a self-hosted git server (Gitea/Forgejo) on cellar or silo, reachable via Headscale from anywhere, and switch the canonical remote's URL to that — nothing about the repo structure changes, just where `origin` points.
- **After that migration, GitHub's role flips:** it stops being the working source of truth and instead holds a deliberately stripped-down, sanitized version of the code — enough to be a public-facing developer-profile showcase, not the operational repo. (Scope of "stripped down" — which stacks/configs are worth showing publicly vs. kept private — is a decision for whenever that migration actually happens, not now.)

### 4. Wake-on-LAN for roastery — plan agreed, implementation deferred to next session

Roastery sits on the same LAN segment as sieve/silo/cellar (all fed from Router 1 via Switch 1/Switch 2 per Section 0.12), so a magic packet broadcast from any always-on box on that LAN reaches it without any router-level "WoL over WAN" configuration.

**Plan (not yet implemented):**

- On roastery: enable WoL in BIOS/UEFI, then in Windows Device Manager → NIC → Power Management, enable "Allow this device to wake the computer" + "Only allow a magic packet to wake the computer," disable "Allow the computer to turn off this device to save power," and disable Fast Startup (it interferes with WoL after a normal shutdown). Check whether the board uses classic S3 sleep vs. Modern Standby (S0) — WoL reliability differs. Need roastery's MAC address.
- Trigger host: **silo** (already always-on, already hosting Homepage/Homarr per Section 18.3) runs `wakeonlan <MAC>`.
- Remote reachability: expose the trigger over Headscale/a Homepage button/n8n webhook so it's a single tap from mobile, rather than SSHing into silo by hand each time.

**Next session:** check roastery's current NIC power-management state and MAC address directly via the device bridge (this session is bound to roastery, but the bridge was disconnected when this came up), then wire up the actual trigger on silo once it's live.

---

## 2026-08-27 — Wake-on-LAN investigation for roastery

Checked directly on roastery via the device bridge (board: Gigabyte B450 AORUS PRO WIFI).

**Finding: roastery's LAN cable is in a USB Ethernet dongle, not the onboard NIC — and that's intentional.**

- Active connection: "Ethernet" — Realtek USB GbE Family Controller, MAC `C8:4D:44:27:B1:E5`, currently 192.168.0.67 (DHCP).
- Onboard NIC: "Ethernet 2" — Intel(R) I211 Gigabit Network Connection, MAC `B4:2E:99:3B:3F:9E`, **not connected**.
- Confirmed with User Penguin: the onboard port is physically unreliable ("loose, breaks connection 99% of the times") — that's *why* the USB dongle is in use. Not something to reverse.

**Implication for WoL:** USB-attached NICs are far less reliable for Wake-on-LAN than onboard ones — many don't support magic-packet wake at all, and even ones that do typically only work from **Sleep (S3)**, not from a full shutdown (S5), since USB ports commonly lose power when the machine is fully off. Practical adjustment to the plan:

- Plan around **Sleep, not Shutdown**, as roastery's idle state — check "Power & sleep button controls" (currently: power button → Shut-down, sleep button → Sleep) and get in the habit of sleeping rather than shutting down when WoL matters.
- Use the USB dongle's MAC (`C8:4D:44:27:B1:E5`) for the magic packet, not the onboard NIC's — the onboard one isn't in use.
- **Still needs manual verification on roastery (couldn't be checked remotely — see below):** Device Manager → Network adapters → Realtek USB GbE Family Controller → Properties → Power Management tab. If that tab/the "allow this device to wake" option doesn't exist at all for this adapter, this specific dongle doesn't support WoL and a different approach (e.g. a smart plug for a hard power-cycle, relying on "Restore on AC power loss" in BIOS) would be needed instead.
- BIOS-level WoL enable and Fast Startup (Control Panel → Power Options → Choose what the power buttons do → Turn off fast startup) also still need manual confirmation — same reason as below.

**Why this needs a manual check:** Device Manager (and other elevated admin tools) can't be driven remotely through this session — Windows blocks synthetic input to elevated windows from a non-elevated automation session (UIPI), so clicks/keystrokes silently don't land once such a window is frontmost. This is a hard OS security boundary, not a bug to route around. Settings and Control Panel (non-elevated) worked fine for the MAC address lookup above.

**Not yet implemented:** the two checkboxes above, BIOS WoL enable, Fast Startup disable, and the actual `wakeonlan` trigger on silo.

Confirmed via screenshot: on the Realtek USB GbE Family Controller, "Allow this device to wake the computer" and "Only allow a magic packet to wake the computer" are both already checked — the driver genuinely supports WoL. "Allow the computer to turn off this device to save power" is also checked; leave as-is unless wake turns out flaky, then try unchecking it first. Remaining blockers are BIOS-side (ErP/EuP, Wake-on-LAN enable) and Fast Startup — none checkable remotely.

---

## 2026-08-27 (cont.) — Exposed/unexposed data convention, git remote setup

Nothing has been run on sieve/silo/cellar yet — this is clean-slate setup, not reconciliation of divergent repos.

**Convention adopted:** two tiers of config, not one `.env`.

- `PROJECT_DIR/.env` — identical on every node, non-secret, safe anywhere (`PROJECT_DIR`/`DATA_DIR`/`MEDIA_DIR`). Unchanged from Section 19.1.
- `PROJECT_DIR/.env.local` (new — already covered by the `*.env.local` `.gitignore` pattern from `purrbrews-init.sh`) — host/deployment-specific values that must never appear inside a tracked file or a script, starting with the GitHub remote URL as `PURRBREWS_REMOTE_URL`. Anything that goes here gets referenced by scripts as a variable, never typed as a literal into anything that lives in the repo. Rationale: the GitHub remote is private today but is planned to later hold a stripped-down public mirror (Section 3, 2026-08-26 entry) — treating the remote's location as unexposed-by-default from day one means there's no redaction step to remember later, it's just never in a committed file to begin with.

**Bug caught by the same logic, fixed in `purrbrews-init.sh`:** the age private key path was originally `$PROJECT_DIR/secrets/age/keys.txt` — inside the directory the repo's `.gitignore` deliberately *un-ignores* (`!secrets/**`, since SOPS ciphertext there is meant to be committed). That would have swept the private key into the repo on a plain `git add .`. Moved to `/etc/purrbrews/age/keys.txt` — entirely outside `$PROJECT_DIR`, so it's structurally impossible for a git command run inside the repo to pick it up, rather than relying on remembering a gitignore rule correctly. `AGE_KEY_DIR`/`AGE_KEY_FILE` in the script now point there; all downstream messages (backup reminder, scp-to-silo/cellar instructions) updated automatically since they reference the variable.

**GitHub repo:** not yet created — User Penguin creating a private, empty repo (no README/.gitignore/license) at github.com, named `purrBrews-infra` (matches the local `purrBrews-infra` folder already in use; no need for this to match `PROJECT_DIR=/opt/purrbrews` on the nodes).

**Resolved:** repo created at `https://github.com/purrMonster/purrBrews-infra.git` (private, empty). Local clone root is `C:\Users\jyotirmoyc\Projects\purrBrews-infra` — one level *up* from the `claude` folder this session has been writing to, which is why `claude/` is now in `.gitignore` at the repo root: it's this session's own working docs/scripts, not tracked project code. Note this means `purrbrews-init.sh` and `ssh_authorized_keys.txt` currently stay untracked too — worth revisiting if you want the init script itself under version control long-term (e.g. a tracked `scripts/` folder), but not done as part of this pass since it wasn't asked for.

Repo skeleton delivered: `README.md`, `.gitignore`, `.env` (tracked, shared path vars), `.env.local` (untracked, holds `PURRBREWS_REMOTE_URL`), `secrets/README.md` (SOPS+age convention), the full `stacks/<node>/<app>/` placeholder tree from Section 19.1, and this runbook copied to the repo root as the tracked canonical version (the `claude/` copy remains this session's working copy).

**Not yet done:** the actual `git init` / `add` / `commit` / `remote add origin` / `push` on roastery — commands provided, not yet run by User Penguin. The 32 pre-created `stacks/<node>/<app>/.gitkeep` placeholders were reconsidered and dropped before the first commit — git doesn't track empty directories, so they added 32 files to manually clean up later for no functional benefit; folders now get created organically when each app's actual compose file is authored.

---

## 2026-08-27 (cont.) — Emergency access plan (SSH key loss / access from elsewhere)

Problem: exactly one SSH key exists (roastery) with no fallback, no durable record of each node's console (`barista`) password, and the age key's "offline backup" (Section 19.3) was undefined.

**Plan — a single `age`-encrypted USB, not a new tool:**

- **Emergency SSH keypair**, generated by User Penguin directly on roastery (not by Claude — a break-glass key shouldn't transit the infrastructure it exists to route around; also moot, since typing into a terminal on roastery is blocked for this session anyway per the UIPI restriction found earlier). Passphrase-protected. Its public key gets added to `ssh_authorized_keys.txt` alongside roastery's, so it's authorized fleet-wide from first boot.
- **Encryption via `age -p`** (passphrase mode), not VeraCrypt/7z — already the project's standard tool, single portable binary, no driver/admin install needed on a borrowed machine, which matters for the "access from somewhere else" case specifically.
- **Contents, added incrementally as they come into existence** (not all buildable today): the emergency SSH keypair (now), `age/keys.txt` (once sieve generates it — this USB copy *is* the Section 19.3 offline backup, not a separate thing to remember), each node's console password (as `purrbrews-init.sh` prints it — unrecoverable after the terminal scrolls, so must be captured immediately), and a `RECOVERY.md` procedure doc.
- **Maintenance discipline:** re-encrypt and redistribute to every physical copy on any content change; test quarterly by actually decrypting and SSHing in from a non-primary machine — an untested backup isn't one.

`RECOVERY.md` drafted (delivered alongside this runbook). **Still open:** number/location of physical copies, and the emergency public key itself (waiting on User Penguin to run `ssh-keygen` locally).

---

## 2026-08-27 (cont.) — `barista` is not an admin account

Reviewed `purrbrews-init.sh` end to end with User Penguin; corrected on one point: `barista` originally got `sudo` group membership ("don't SSH in as root, use a sudo user" is standard Debian hardening advice, which is why it was there) — but that conflated "the account you log in as" with "an account that can become root," which isn't what `barista` was meant to be (it was named/conceived as a service-flavored account from the start, back when the admin-user naming question first came up).

**Changed:** `barista` (renamed internally from `ADMIN_USER` to `OPS_USER` in the script for accuracy) is now a plain user — no `sudo`, group memberships granted one at a time only for concrete needs (currently just `docker`, since it runs the fleet's containers; add others the same explicit way if something later actually needs them, never by default).

**Consequence, deliberately accepted:** combined with `PermitRootLogin no` (already in place), there is now **no remote path to root at all** on sieve/silo/cellar — any host-level admin task (installing something outside the base package set, editing a system config, debugging the Docker daemon itself) requires physical console access. This is the tradeoff for not keeping a standing privileged account reachable over SSH.

**Note surfaced but not acted on:** `docker` group membership is itself root-equivalent (trivial to get a root shell via a bind-mounted container), independent of `sudo`. Removing `sudo` alone doesn't shrink `barista`'s real blast radius while it's still in `docker` — that group is where the actual privilege lives. Not changed for now since `barista` genuinely needs to run containers; flagged here so it isn't mistaken for a solved problem.

**Reconsidered minutes later:** physical-console-only root turned out to be more restrictive than wanted for a two-flat lab. `barista` is back in `sudo` (SSH still never accepts root directly — `PermitRootLogin no` is unchanged; root is reached by SSH'ing in as `barista`, then `sudo su -`). Still not passwordless: sudo prompts for `barista`'s own console password, a separate credential from the SSH key, so there's still a second factor between "has the key" and "is root" — just reachable remotely again instead of requiring physical presence. Net effect of this whole sub-thread: the `ADMIN_USER`→`OPS_USER` rename and the docker-group-is-root-equivalent note both stand; the sudo removal itself was undone.

---

## 2026-08-27 (cont.) — Final call on `docker` group: never grant it, use `sudo docker ...` permanently

Follow-up to the note two entries up ("`docker` group membership is itself root-equivalent, independent of `sudo`"). User Penguin's gut check — "is this actually good practice?" — was right to raise: with `barista` in both `sudo` and `docker`, the `docker` group is a second, ungated root path that sits right next to the password-gated `sudo` one, quietly undoing the point of requiring a password for `sudo su -`.

Options weighed: (1) never add `barista` to `docker` at all, route everything through `sudo docker ...`; (2) grant `docker` temporarily during initial setup (until Komodo can manage the fleet), then revoke it once Komodo's up.

**Decided: option 1, permanently — not a temporary grant-then-revoke.** Reasoning: Section 19.2 has Komodo managing the *rest* of the fleet but explicitly *not* its own host or sieve (Komodo can't administer the machine it's running on) — so sieve, and by extension silo, need direct `docker`/`docker compose` access indefinitely, not just "until Komodo is ready." A revoke-later plan would have to be undone almost immediately, or would quietly never happen. `sudo docker ...` gives the exact same capability with no ungated path ever created, so there's no reason to open the gap even temporarily.

**Changed in `purrbrews-init.sh`:**

- `barista` is never added to the `docker` group — not in `step_admin_user`, not in `step_docker`. Comment above `OPS_USER="barista"` now spells out why (root reachable via `sudo su -`, gated by `barista`'s own password; `docker` group would be root-equivalent with no password gate at all, silently defeating that gate).
- `step_docker`'s closing log line now tells the operator to use `sudo docker ...` / `sudo docker compose ...`.
- `step_summary`'s Ops user line reflects the final state: `barista (sudo only, no docker group; SSH key-only login, sudo needs its own password — use 'sudo docker ...')`.

**Net security model, final:** SSH key-only login, no root over SSH, `barista` reaches root only via `sudo su -` gated by its own console password, and that password gate is never bypassed by a parallel ungated group membership. One second factor, no side doors.

---

## 2026-08-27 (cont.) — `step_git_repo` fixed; physical cabling confirmed; router/switch IPs assigned

### 1. `purrbrews-init.sh` now clones instead of `git init`-ing a disconnected repo

Fixes the stale behavior flagged twice earlier (script walkthrough, and the backlog item added right after). `step_git_repo` no longer runs `git init` on each node and no longer pre-creates the 32 `stacks/<node>/<app>/` placeholder folders — both artifacts of writing this step before a real remote existed.

**New behavior:**

- If `$PROJECT_DIR/.git` already exists, the step just does `git pull --ff-only` (safe re-run, doesn't clobber local state, warns instead of failing hard if the pull can't fast-forward).
- Otherwise it looks for a remote URL, in order: `$PURRBREWS_REMOTE_URL` env var → `remote_url.txt` next to the script (same pattern as `ssh_authorized_keys.txt` — one line, gitignore it) → `$PROJECT_DIR/.env.local` if one happens to already be sitting on the node (the same `PURRBREWS_REMOTE_URL=...` line the repo skeleton's own `.env.local` uses).
- Found → `git clone` straight into `$PROJECT_DIR`, then `chown -R` to `barista`.
- Not found → **no `git init` fallback.** `$PROJECT_DIR` is left as a plain empty directory with a clear warning telling you what to set and re-run. A disconnected local history was worse than no history at all — the whole point of the fix.
- `step_directories` (DATA_DIR/MEDIA_DIR + the shared `.env`) now runs *after* `step_git_repo`, since the clone needs to own creating `$PROJECT_DIR` itself (git clone won't target a pre-existing non-empty directory).

**Still manual, by design:** getting a `remote_url.txt`/`.env.local` onto each node before first run. Not automated — it's host-specific, gitignored data, same category as SSH keys.

### 2. Physical cabling confirmed done

Section 0.12 cabling matches the floor plan — no longer a blocker for running `purrbrews-init.sh` for real on sieve/silo/cellar.

### 3. Network layout — routers and switches assigned

| Device | IP |
|---|---|
| Router 1/2/3 | 192.168.0.1 / .2 / .3 |
| Switch 1/2 | 192.168.0.4 / .5 |

`GATEWAY=192.168.0.1` in `purrbrews-init.sh` already matched Router 1. Added a comment block in the script's config section reserving `.1`–`.5` for this infra layer (not managed by the script, just documented) so future fleet-node IP assignments don't collide with it — sieve/percolator/silo/cellar at `.10`–`.13` are already clear of this range.

---

## 2026-08-27 (cont.) — `scripts/purrbrews-commit.{sh,ps1}`: AI-assisted commit + runbook automation

New tool, delivered in both a bash (`scripts/purrbrews-commit.sh`) and PowerShell (`scripts/purrbrews-commit.ps1`) version — this is the first thing tracked under a `scripts/` folder in the repo itself, resolving the loose end noted back in the git-remote-setup entry ("worth revisiting if you want the init script itself under version control long-term").

**What it does:** stages everything (`git add -A`), sends the staged diff to a locally-running AI model, gets back a Conventional-Commits-style commit message and a plain-language summary, appends the summary as a new dated `## YYYY-MM-DD (auto)` entry to `runbook.md`, previews both for you, then (after a y/N confirmation, or unattended with `--yes`/`-Yes`) commits everything — code changes plus the runbook entry — as one commit and pushes.

**Decisions made, and why:**

- **AI backend: a local Ollama model, not a hosted API.** Diffs never leave the machine — no `ANTHROPIC_API_KEY`/`OPENAI_API_KEY` to manage, no third-party call for what could be sensitive-ish project detail, consistent with the exposed/unexposed convention this project already runs on. Default model `llama3.1`; override with `--model`/`-Model` since it depends on what's actually pulled locally (`ollama pull ...`). Requires `ollama serve` running and reachable at `localhost:11434` (overridable too).
- **Both shells, not one.** Dev happens on roastery/americano; this covers PowerShell (native Windows) and bash (Git Bash/WSL) so it works whichever you reach for.
- **"Fully automatic" runbook update, but NOT a silent commit by default.** The runbook entry itself is fully AI-generated with no pause — that was the explicit ask. But the script still shows the generated commit message + runbook entry and asks for a y/N before actually committing/pushing, matching the confirm-before-risky-action pattern already used in `purrbrews-init.sh` (e.g. the static-IP step). `--yes`/`-Yes` skips that prompt for scheduled/unattended use once you trust the output.
- **`--dry-run`/`-DryRun`** exists specifically so the AI's output can be sanity-checked before it's ever trusted to run unattended — added to the backlog as a to-do before relying on this for real.
- **No `git init` fallback / no new scanning logic:** staging relies entirely on the existing `.gitignore` (same guardrail that already keeps `claude/`, `*.env.local`, `*.key` out of a plain `git add .`) — this tool doesn't add or need its own secret-detection layer on top of that.

**Not yet done:** actually pulling a model and confirming Ollama's reachable on whichever machine runs this; a first dry run to validate the model's output quality for this repo's diffs (small local models can be inconsistent — the script strips stray code-fence wrappers defensively, but hasn't been tested against a real diff yet).

---

## 2026-08-27 (cont.) — First real run of `purrbrews-commit`: caught and fixed a silent-failure bug

First live use (against `gemma4:26b`) staged real repo content correctly — a 10-file, ~76KB diff, truncated to 12,000 chars for the model as designed — but failed with `ERROR: Model returned an empty commit message`, no further detail.

**Root cause:** `ollama_ask`/`Invoke-Ollama` called Ollama with `curl -fsS` (bash) / a bare `Invoke-RestMethod` (PowerShell). Ollama returns useful JSON error bodies on failure — e.g. `{"error": "model 'x' not found, try pulling it first"}` — but `-f` makes curl discard the response body on any non-2xx status, and the PowerShell call wasn't inspecting the thrown exception's body either. Either way, the actual reason never reached the terminal; the script just saw an empty string and reported the generic "empty commit message" message.

**Fixed in both scripts:**

- The Ollama call no longer discards error bodies — it parses the JSON response itself, checks for a top-level `.error` field, and dies with that exact message if present.
- If there's neither `.error` nor `.response`, it now prints the raw reply (truncated) instead of silently treating it as empty — covers whatever unanticipated shape a future Ollama version might return.
- Added a lightweight preflight: right after confirming Ollama is reachable, both scripts fetch `/api/tags` and warn up front if the requested model isn't in the pulled-models list, naming what *is* available — catches a typo'd or unpulled model name before spending time building the diff/prompt.

This was exactly the kind of thing the "dry-run before trusting it unattended" backlog item was for — worth repeating the dry run once a model is confirmed reachable, to see the improved error output (or a clean success) instead of the original opaque failure.

---

## 2026-08-27 (cont.) — Second real run: found the actual cause (context window, not a real Ollama error)

The improved error handling above worked exactly as intended — it surfaced the raw Ollama reply instead of just "empty," and that raw reply was the actual diagnostic: `gemma4:26b` returned `"response": ""`, `"done_reason": "length"`, `"prompt_eval_count": 3737`, `"eval_count": 357`. No `.error` field at all — this was never a "model not found" problem.

**Diagnosis:** 3737 + 357 ≈ 4094 — right at the edge of a default 4096-token context window. Our own diff-truncation cap (`MAX_DIFF_CHARS=12000`, ≈3700 tokens) was, by itself, already eating nearly the entire default context before the model got to say anything. `done_reason: length` confirms the model hit that ceiling mid-generation — it spent all 357 tokens it had room for (likely internal reasoning, since `gemma4:26b` returned zero of it as final `.response` text) and got cut off before ever reaching an answer. Not a broken model, not a wrong model name — just too little room left after the prompt.

**Fixed in both scripts:** the Ollama request now explicitly sets `options.num_ctx` (new config: `OLLAMA_NUM_CTX` / `-NumCtx`, default **8192** — override with `--num-ctx`/`-NumCtx`), instead of leaving it to Ollama's default. Also added a *specific* diagnosis for this exact failure shape — when `.response` is empty and `done_reason` is `"length"`, the warning now names the token counts and points at `--num-ctx`/`MAX_DIFF_CHARS` directly, instead of falling through to the generic "here's the raw JSON, good luck" path.

**Still to confirm:** whether 8192 is enough headroom for `gemma4:26b` specifically once run again — if it still hits `length` (this time with a much bigger token count in the log), that's a genuinely long-winded/heavy-reasoning response and either `--num-ctx` needs to go higher still or `MAX_DIFF_CHARS` needs to come down. Worth a `--dry-run` retry as the next step either way.

---

## 2026-08-27 (cont.) — Speed: merged the two AI calls into one; naming the actual latency floor

Raised directly: if generating a commit message takes this long, automating it isn't worth it. Fair — the earlier run's own numbers back that up: `total_duration` 61.5s, of which `load_duration` was 26.9s (model load), `prompt_eval_duration` 23.5s (processing the diff), `eval_duration` 10.8s (generating, and that attempt still failed empty). And the script was making that same diff get processed **twice** — once for the commit message prompt, once for the runbook summary prompt — paying the ~23.5s prompt-eval cost a second time for no reason.

**Fixed (real, unconditional win, no tradeoff):** both scripts now send ONE combined prompt asking for both the commit message and the runbook summary in a single structured reply (`COMMIT MESSAGE:` / `RUNBOOK SUMMARY:` sections, parsed out afterward — falls back to treating the whole reply as the commit message if the model doesn't follow the format). This roughly halves the prompt-processing cost per run. Also added `keep_alive: "10m"` to the request so the model doesn't get unloaded from memory while sitting at the confirmation prompt or between quick successive runs — avoids repaying the ~27s load cost unnecessarily (doesn't help a genuinely cold first run).

**What this doesn't fix — the honest part:** prompt-eval time (processing the diff) and generation time are both a function of model size and hardware, not pipeline design. A 26B-parameter model doing single-request local inference is going to take real seconds-to-tens-of-seconds no matter how the calls are batched. Merging the two calls cuts the *avoidable* overhead; it doesn't change the floor set by running `gemma4:26b` itself. Rough expectation post-fix, warm model: ~24s prompt-eval + however long generation actually takes now that it can finish (previously cut off before finishing, so real generation time for a *complete* answer is still unmeasured) — likely still 30-45s+ per commit, not "instant."

**The actual lever for "fast," if that's the priority:** a much smaller model (e.g. a 3B–8B class model) for this specific task. Writing a commit message and a two-sentence summary doesn't need 26B-parameter-level reasoning — a small model should turn this into single-digit seconds. Trade-off is output quality/nuance, which may or may not matter for what's essentially throwaway boilerplate text. This is a call only User Penguin can make (depends on what's already pulled, hardware, and patience) — flagged as a backlog decision rather than changed unilaterally.

**Decided:** switch to a small/fast model. Default model in both scripts changed from `gemma4:26b` to **`llama3.2:3b`** — should turn ~30-45s/commit into single-digit seconds once pulled. If the output quality disappoints (commit messages too generic, runbook summaries missing the point), the documented fallback is `--model qwen2.5:7b`/`-Model qwen2.5:7b` — still far faster than the 26B model, more capable than the 3B one, a middle ground before reaching for anything large again. `gemma4:26b` isn't removed from anywhere — still usable via `--model gemma4:26b` if quality ever matters more than speed for a given commit.

**Not yet done:** actually pulling `llama3.2:3b` and re-running to confirm both the speed improvement and that a small model's commit messages/summaries are acceptable — added to backlog above.

---

## 2026-08-27 (cont.) — Split runbook-entry generation out of `purrbrews-commit`: separate nightly job, not this script

Decided: `scripts/purrbrews-commit.{sh,ps1}` no longer touches `runbook.md` at all. Removed the combined `COMMIT MESSAGE:`/`RUNBOOK SUMMARY:` prompt from the entry above and reverted to a single, simple commit-message-only prompt — no more response parsing, no `Add-Content`/append-to-`runbook.md` step, no `$RunbookFile`/`RUNBOOK_FILE` config at all.

**Why:** the runbook entry is going to become a separate **nightly job**, run once a day against a *stronger* model with *more context* — the day's commits as a whole, not one diff in isolation. That's a fundamentally different job than "write a fast commit message per commit": different cadence (nightly vs. every commit), different model (quality-over-speed vs. speed-over-quality — the exact opposite tradeoff just made above for `purrbrews-commit`), and different input shape (a day's history vs. a single staged diff). Trying to make one script do both was why it needed the 26B model and the merged-prompt workaround in the first place — splitting them means `purrbrews-commit` gets to stay small-model-fast permanently, and the runbook job gets to use as large a model and as much context as it needs without slowing down every single commit.

**Net effect:** `purrbrews-commit.{sh,ps1}` now does exactly one thing — stage, get a commit message, commit, push. Nothing in this repo currently auto-generates runbook entries; that gap is intentional until the nightly job exists. Runbook entries stay manual (as this whole file already has been) until that job is built.

**Not yet done — new backlog item:** design and build the nightly job itself (added above). Open questions for that, not yet decided: which model, where it runs (americano/roastery vs. a fleet node once one exists), what "the day's commits" means as input (a `git log` range, one prompt per repo per night?), and whether it appends automatically or drafts an entry for review first.

---

## 2026-08-28 — `purrbrews-init.sh` widened to cover percolator and mochaPot

**What changed:** `SUPPORTED_NODES`/`NODE_IP` already listed `percolator` and `mochaPot`, but the header docstring, usage line, and a comment right above `SUPPORTED_NODES` all said this script was sieve/silo/cellar-only ("percolator/mochaPot get their own base-OS step later — not this script") — so the guard would have silently let you run it against percolator/mochaPot anyway, contradicting the stated intent. Reviewed whether the script is actually hardware-generic enough to own base-OS provisioning for all five nodes, concluded yes, and updated the script to match: header/usage now list all five nodes, and the stale comment is fixed.

**New step — lid-switch handling:** the one real hardware-specific gap found during the review. mochaPot is an HP X360 Pavilion running as an unattended touchscreen kiosk — without intervention, systemd-logind suspends the machine the instant the lid closes, taking every container down with it. Added `step_lid_switch()` (sets `HandleLidSwitch`/`HandleLidSwitchExternalPower`/`HandleLidSwitchDocked=ignore` in `/etc/systemd/logind.conf`, idempotent, backs up the original file first restart-time). Applied to all five nodes rather than gated per-node — it's a no-op on sieve/silo/cellar (no lid) and on percolator (bare laptop board, no lid hardware), so a uniform step is simpler than a conditional one.

**Not yet done:** actually running the widened script on percolator/mochaPot (still queued behind sieve → silo → cellar in deploy order per the runbook backlog and README). No other hardware-specific gaps were identified for percolator/mochaPot during this pass, but neither has been provisioned yet to confirm that in practice.

---

## 2026-08-28 (cont.) — Morning `git pull` cron on every node

**Decided:** every fleet node keeps its local `purrbrews-infra` checkout fresh on its own, every morning, via a plain `git pull --ff-only` — no push, no merge/rebase fallback. This is deliberately narrow in scope: it is *not* the AI-assisted nightly runbook job from the 2026-08-27 backlog item (that's still undesigned/unbuilt — different job, different cadence, different purpose). This is just "don't let a node's checkout silently drift stale."

**What was built:**

- `scripts/purrbrews-pull.sh` — the actual pull. Never prompts (`GIT_TERMINAL_PROMPT=0` — a hung cron job is worse than a failed one), `--ff-only` (refuses to auto-merge a diverged tree, logs a failure instead), logs every run (timestamped, OK/FAILED) to `/var/log/purrbrews/pull.log`.
- `step_cron_pull()` in `purrbrews-init.sh` — installs that script into `$OPS_USER`'s (`barista`'s) crontab, daily at `$CRON_PULL_HOUR:$CRON_PULL_MINUTE` (default `06:15`, both configurable in the script's config block; `ENABLE_CRON_PULL="false"` skips the step entirely). Re-running the init script updates the schedule in place (strips the old managed line by its comment marker, re-adds it) rather than stacking duplicate crontab entries — same idempotency pattern as the rest of the script. Added `cron` to the base `apt-get install` list since it isn't guaranteed present on a minimal Debian image. Wired into the main sequence right after `step_directories` (needs `$PROJECT_DIR` and the cloned `scripts/` to already exist).
- Invoked as `bash <path>`, not by executing the file directly — so it doesn't depend on the executable bit surviving `git clone`/`pull`.

**Known gap, called out loudly in both files:** the configured remote is an HTTPS GitHub URL to a *private* repo. `git pull` with no stored credential will fail every single run (by design — it fails fast rather than hanging on a password prompt), it just won't silently succeed either. Non-interactive auth (credential-helper store after one manual authenticated pull with a PAT, or an SSH remote + read-only deploy key) still needs to be set up per node before this cron actually does anything — added to the backlog above. Also added a backlog item to confirm each node's timezone once provisioned, since `06:15` is node-local time and "morning" only means that if the clock agrees.

---

## 2026-08-28 (cont.) — sieve's app stack: WBS 18.2 (Pi-hole → lldap → Authelia → Traefik → Headscale → Cloudflare Tunnel)

**Status going in:** User Penguin reported all five fleet nodes (sieve, silo, cellar, percolator, mochaPot) now provisioned via `purrbrews-init.sh`, and the age keypair generated on sieve — both taken on report, not independently verified from this session (no SSH access to the fleet). Moved on to building sieve's actual application stack per WBS 18.2, which until now was six empty placeholder directories under `stacks/sieve/`.

**Three decisions made before writing any config**, via direct question to User Penguin (the initiation doc specifies the architecture but not these specifics):

1. **Domain:** a real one exists, but stays out of every tracked file — referenced only via `${DOMAIN}` from a gitignored `stacks/sieve/.env.local`. This matters more than usual here because the plan (Section 3 of this runbook) is for GitHub to eventually flip from private canonical remote to a *public* sanitized mirror — a hardcoded domain in a compose file would be a problem at that point, not just today.
2. **Split-horizon DNS:** same public domain both ways (not a separate `*.internal` suffix) — LAN clients resolve `authelia.${DOMAIN}` etc. straight to the LAN IP of whichever node actually hosts it, external clients hit the same hostname via Cloudflare Tunnel. Matches what the initiation doc already called out as the intended architecture (Section 0.3).
3. **Secrets:** *not* SOPS+age, despite Section 19.3 and the age key existing on sieve already. Decided instead: generate secrets locally on the node at setup time, keep them as plain gitignored files (covered by the repo's existing `*.env.local` rule), never commit anything — encrypted or not. **This decision is scoped to sieve's stack only** — added a backlog item above to decide whether it extends to silo/cellar/percolator/mochaPot too, or whether those go the originally-planned SOPS route instead. Also asked for, and applied throughout: one `docker-compose.yml` per app, not one big combined file per node — matches the six-folder layout the initiation doc's own Section 19.1 already specified.

**What was built**, under `stacks/sieve/`:

- One `docker-compose.yml` per app — `pihole/`, `lldap/`, `authelia/` (bundles its own Redis as a second service in the same file — Redis here is purely Authelia's session store with no independent lifecycle, and the initiation doc's own file-layout list never gave it a separate folder), `traefik/`, `headscale/`, `cloudflared/`.
- `bootstrap-network.sh` — creates one shared external docker network (`sieve_proxy`) that traefik/authelia/redis/lldap/cloudflared all join, so they can reach each other by container name. Pi-hole runs on `network_mode: host` instead (needs real LAN visibility for DNS/DHCP), so it's not on this network.
- `generate-secrets.sh` — idempotent (only fills in a key that doesn't already exist), generates every secret it *can* generate (`openssl rand`) straight into each app's `secrets.env.local`. Mirrors lldap's generated admin password into Authelia's LDAP bind password rather than generating two inconsistent ones. Two values it can't generate — because they only exist inside a Cloudflare account (`CF_DNS_API_TOKEN` for Traefik's DNS-01 ACME challenge, `TUNNEL_TOKEN` for cloudflared) — get a loud `REPLACE_ME` placeholder instead of a silent gap.
- `render-configs.sh` — every config that needs `${DOMAIN}` (Traefik's static/dynamic config, Authelia's config, Headscale's config, Pi-hole's split-horizon DNS entries) is authored as a tracked `*.template` file and rendered via `envsubst` into a gitignored real file. Keeps the domain out of git without needing a templating step per app. Added `gettext-base` (provides `envsubst`) to `purrbrews-init.sh`'s base package list for this.
- `compose.sh` — thin wrapper (`./compose.sh <app> up -d`) that supplies the right `--env-file` flags (`.env.local` + that app's `secrets.env.local`) so nobody has to remember them by hand.
- `README.md` — deploy order, first-time setup commands, where the two manual Cloudflare values come from, and a "known gaps" section (see below).

**Architecture calls made without asking, documented in the README for correction:**

- **Traefik gets a real cert via DNS-01 ACME** (Cloudflare DNS challenge), not a self-signed one — so LAN split-horizon access doesn't throw browser warnings. This is what `CF_DNS_API_TOKEN` is for.
- **Cloudflare Tunnel is token-based and remotely-managed** — no local `config.yml`/`credentials.json` on sieve at all; hostname → origin routing is configured once in the Cloudflare Zero Trust dashboard instead, pointing at `http://traefik:80` (reached by container name over `sieve_proxy`, no host port needed for this). Simpler than the alternative and one fewer local secret file.
- **Headscale's coordination endpoint is deliberately NOT behind Authelia's forward-auth** — tailscale clients register/sync against it directly and can't complete an interactive browser login; headscale's own pre-auth-key/invite flow is the access control there, not SSO.
- **Authelia's `access_control` defaults to `one_factor` everywhere** for first bring-up (no TOTP enrollment required to get in the door), and uses the filesystem notifier (no SMTP dependency yet). Both flagged in the README as things to tighten once the basics are confirmed working.
- **lldap's admin UI (port 17170) is directly host-published for now**, not yet routed through Traefik/Authelia — added to the backlog above as a follow-up.

**Verified before delivery:** every shell script passes `bash -n`; every compose/template YAML parses; ran `generate-secrets.sh` → `render-configs.sh` end-to-end in an isolated copy (using a stand-in `envsubst`, since this session's sandbox couldn't reach its package mirror to install the real one) and confirmed the rendered output — domain substitution, and the lldap→Authelia password mirroring — came out correct; confirmed `generate-secrets.sh` is idempotent on a second run (no values changed).

**Image tags** were pinned to what looked current as of 2026-08-28 (checked via web search this session): `pihole/pihole:2026.07.2`, `lldap/lldap:v0.6.3`, `authelia/authelia:4.39.20`, `traefik:v3.6`, `headscale/headscale:0.27.1`, `cloudflare/cloudflared:2026.1.2`. Flagged in the README and the backlog above to double-check before actually deploying, since real deploy time may be well after this date.

**Not yet done:** all of it, actually — this is the code, not the deployment. Filling in `.env.local`/the two Cloudflare secrets and bringing the six apps up on sieve in order is the next real step (see backlog above and `stacks/sieve/README.md`).

---

## 2026-08-29 — `generate-secrets.sh`: interactive prompting for the three manual values

**What changed:** the three values `generate-secrets.sh` can't generate itself (`DOMAIN`, `CF_DNS_API_TOKEN`, `TUNNEL_TOKEN`) used to get a `REPLACE_ME` placeholder that you then had to go hand-edit into each file. Replaced with a `prompt_if_placeholder()` helper: prompts for each one interactively (tokens use `read -s` — silent, nothing echoed or left in shell history) only when it's still missing or a placeholder; leaves a real value already in place completely alone. Leaving a prompt blank keeps the placeholder rather than writing an empty string, so the next run asks again instead of silently staying blank. If stdin isn't an actual terminal (piped input, run unattended/via cron), prompting is skipped and placeholders are written instead — never hangs waiting on input that can't arrive.

**Bug caught during testing, fixed before delivery:** `get_value()`'s original `grep | tail | cut` pipeline exits nonzero when the key doesn't exist yet (the normal case for a first run) — under this script's `set -euo pipefail`, that silently killed the whole script partway through `.env.local`, before it ever reached the DOMAIN prompt, with no error message. Rewrote `get_value()` to absorb a non-matching grep instead of letting it propagate. Caught by an actual non-TTY run (`./generate-secrets.sh < /dev/null`) during verification, not by inspection — worth remembering as a `set -e`/`pipefail` gotcha for any future script here that greps a file for a key that might not exist yet.

**Verified before delivery, using a `pty`-backed test harness (real `grep`/`tail`/`cut`/`read -s` behavior, not a dry-run stub) against an isolated copy:** non-TTY fallback writes placeholders and exits 0; interactive run with blank input at each prompt keeps the placeholder and prints the "left blank" note; interactive run with real values writes them correctly (and confirmed secret prompts don't echo the typed value to the terminal, unlike the plain `DOMAIN` prompt); a clean idempotent re-run with everything already real prompts for nothing and changes no file.

## 2026-08-29 (cont.) — Pi-hole vs. Traefik port collision, caught during first bring-up

**How this surfaced:** `docker ps` showed `pihole` running, but `192.168.0.10:80` gave no response. Debugging in order — `docker logs pihole` (clean, FTL started fine, webserver bound `0.0.0.0:80`/`:443` successfully) → `sudo ufw status verbose` (default-deny incoming, only `22/tcp` allowed — the actual cause of that specific symptom). While working through the fix, caught a second, more serious problem that hadn't manifested yet: Pi-hole's `network_mode: host` binds port 80/443 directly on sieve, and Traefik's `docker-compose.yml` also publishes host ports 80/443 for LAN-facing routing (necessary — LAN clients hit sieve's real IP directly via split-horizon DNS, not through the `sieve_proxy` docker network). Those two would collide the moment Traefik came up, later in the deploy order — missed this when the stack was originally built.

**Decision: route Pi-hole's admin UI through Traefik instead of leaving it on a direct host port.**

- Pi-hole's webserver moved to port 8080 (`FTLCONF_webserver_port` — Pi-hole v6's current env-var convention; the compose file's old `WEBPASSWORD`/pre-v6-style var is gone from this file too, replaced with `FTLCONF_` equivalents, since the FTLCONF_ vars *force* the setting every startup rather than only seeding it once — matters because sieve's Pi-hole had already done its first-run init, so a plain re-seed wouldn't have taken effect).
- `traefik/config/dynamic.yml.template` gained a `pihole` router (`pihole.${DOMAIN}` → `http://host.docker.internal:8080`), same file-provider pattern as the existing Traefik-dashboard route (host-networked/no-container-to-label-off-of, in both cases).
- `traefik/docker-compose.yml` gained `extra_hosts: host.docker.internal:host-gateway` — Docker's built-in way for a container to reach a service bound directly on the host, needed because Pi-hole (host networking) isn't part of `sieve_proxy` and can't be reached by container name.

**Follow-up decision, asked directly:** should `pihole.${DOMAIN}` sit behind Authelia's forward-auth *in addition to* Pi-hole's own password, or should Authelia *replace* it entirely? User Penguin wanted the latter — asked whether Authelia could "override" Pi-hole's password. Answered honestly: forward-auth can't inject credentials into or bypass Pi-hole's own login (Pi-hole has no OIDC/header-trust support, it's a fully independent password check) — the only way to get a true single-login experience is to disable Pi-hole's own password (`FTLCONF_webserver_api_password: ""`) and let Authelia's forward-auth middleware be the *sole* gate. Flagged the real consequence before building it: that only stays safe if port 8080 is unreachable by anything except Traefik. **Confirmed: this is the chosen design.**

**Concrete, not-yet-verified-from-this-session action required on sieve** — this is the actual security boundary now, not optional hardening:

```sh
docker network inspect sieve_proxy --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
sudo ufw allow from <that subnet> to any port 8080 proto tcp comment 'traefik -> pihole webui'
```

Also still outstanding from the original troubleshooting: the DNS-port ufw rules (`53/tcp`, `53/udp`, scoped to the LAN subnet) suggested during the port-80 investigation — not yet confirmed applied as of this entry.

**Verified this session:** all three edited files (`pihole/docker-compose.yml`, `traefik/docker-compose.yml`, `traefik/config/dynamic.yml.template`) parse as valid YAML, including the rendered form of the `.template` (substituted with dummy `DOMAIN`/`SIEVE_LAN_IP` values to confirm the file-provider router/service block is structured correctly). Not yet verified: the actual `FTLCONF_webserver_port`/`FTLCONF_webserver_api_password` env var names against Pi-hole v6's real behavior — confirm from `docker logs pihole` after recreating the container, same way the original port-80 binding was confirmed, and adjust if the logged config doesn't match what was intended.

**Backlog item added, per explicit request:** check Pi-hole's own documentation — and whether a community fork exists — for a real reverse-proxy auth-trust mechanism (header-based or OIDC) instead of disabling the password outright. Disabling the password is a working, common pattern, but it makes one firewall rule the entire security boundary for an admin panel; a proper trust handshake between Traefik/Authelia and Pi-hole would be more robust if one exists.

## 2026-08-30 — Pi-hole DNS actually working: root cause was a missing NET_ADMIN capability

**Root cause of the "DNS server failure" dashboard warning** (and the timeout on `dig google.com @127.0.0.1`, tested directly to bypass the dashboard entirely): `docker logs pihole` showed `CRIT: Error in dnsmasq configuration: process is missing required capability NET_ADMIN`. FTL reporting "listening on 0.0.0.0 port 53" is misleading here — binding the socket only needs `NET_BIND_SERVICE`, which Docker grants by default; dnsmasq itself never finished initializing without `NET_ADMIN`, so nothing was actually there to answer once a query arrived. This has been present since the very first bring-up (2026-08-29), not something introduced by the port-8080/Traefik-routing changes — it just never surfaced until DNS was tested directly with `dig` instead of only checking web-UI/port reachability.

**Fix:** added `cap_add: [NET_ADMIN]` to `pihole/docker-compose.yml` — a standard, documented requirement for this image that was simply missed when the stack was first built. Confirmed after recreating the container: the CRIT line is gone, and `dig @127.0.0.1` returns a real answer.

**Also confirmed working as a side effect:** the `FTLCONF_dns_upstreams` (Cloudflare) change from earlier the same day did land correctly — logs showed `[✓] FTLCONF_dns_upstreams is used`. And gravity (the block-list database) turned out to already be up to date — Pi-hole's own internal cron ran `pihole updateGravity` successfully overnight, unrelated to the NET_ADMIN bug, since gravity's list downloads go over HTTPS using the host's normal resolver, not through FTL's own (at-the-time-broken) dnsmasq.

**DHCP handoff started:** with DNS confirmed live, User Penguin disabled the home router's own DHCP server and enabled Pi-hole's, letting existing leases expire naturally rather than force-migrating every device at once — the safer of the two approaches, avoiding a window where no DHCP server is answering at all. DHCP settings (range/router/lease time) currently exist only in `pihole.toml` on the persisted data volume, not in any tracked file — deliberately **not** baked into `FTLCONF_dhcp_*` env vars yet, since getting that wrong would take down DHCP for the entire house, not just a container. Backlog item added above to do that once real devices have proven they're picking up leases cleanly over the next few days.

**Also researched this session (2026-08-30):** whether Pi-hole supports OIDC or reverse-proxy header-trust auth, as a more robust alternative to the blank-password approach from 2026-08-29. Checked Pi-hole's official docs and GitHub, and Pi-hole's own Discourse forum: no native support exists, two separate community feature requests for exactly this ([SSO/OIDC](https://discourse.pi-hole.net/t/sso-oidc-integration/85056), [reverse-proxy auth](https://discourse.pi-hole.net/t/support-reverse-proxy-authentication/85780)) went unanswered by maintainers, and no maintained fork adds it either. Conclusion: the current setup (blank `FTLCONF_webserver_api_password`, Authelia's forward-auth as the sole gate, `sieve_proxy`'s subnet as the only thing allowed to reach port 8080) is the recognized workaround for this, not a stopgap standing in for something better — backlog item above updated to reflect this rather than left open indefinitely.

## 2026-08-30 (cont.) — lldap identity model: four accounts, three roles

**lldap is up and confirmed healthy** — logged into its admin UI at `:17170` with the `admin` account seeded by `LLDAP_ADMIN_PASSWORD`, confirmed the base directory structure and the three built-in permission groups (`lldap_admin`, `lldap_password_manager`, `lldap_strict_readonly` — lldap's own internal admin-permission groups, unrelated to Authelia's access control).

**Decided the account/permission model for everything that will sit behind Authelia**, working through it directly rather than defaulting to a flat "any authenticated user gets everything" setup:

- **`admin`** (pre-existing, seeded on first boot) — lldap's own directory administrator. Manages users/groups/schema inside lldap itself. Never used for day-to-day SSO login.
- **`barista`** (new) — the infra-operator identity, deliberately mirroring its existing role at the Linux/SSH layer (sudo, docker access on each node) rather than introducing a second unrelated admin persona. Sole member of a new `purrbrews_infra_admins` lldap group. Gets its own password, separate from `barista`'s Linux/SSH credential — different systems, shouldn't share a secret.
- **`penguin`** and **`bubbles`** (new) — the two personal, day-to-day accounts (User Penguin's own, and a second household user's). Deliberately kept out of every lldap permission group. Explicit decision: **both** get least-required access, not just the second one — there's no default "the primary user gets broad access, the second user is restricted" tiering here.

**What this means for Authelia's `access_control`, to be written when Authelia itself is built next:** replace the flat `domain: '*.${DOMAIN}', policy: one_factor` rule with explicit per-domain rules for `pihole.${DOMAIN}` and `traefik.${DOMAIN}` requiring `subject: group:purrbrews_infra_admins` — i.e., only `barista`. With `default_policy: deny` already set, `penguin`/`bubbles` are denied from both by default rather than falling through to open access. Neither of the two current Authelia-guarded surfaces (Pi-hole admin, Traefik dashboard) is really a household-facing app, so this is the correct default — any narrower access for `penguin`/`bubbles` (e.g. read-only Pi-hole stats) is a deliberate future addition, not an oversight.

**Not yet done:** actually creating the three new lldap accounts + the `purrbrews_infra_admins` group (User Penguin doing this by hand in the lldap UI, matching the hands-on approach for this whole build). Authelia itself hasn't been brought up yet either — next in the deploy order.

## 2026-08-30 (cont.) — Authelia `access_control` written for the barista/purrbrews_infra_admins model

`authelia/config/configuration.yml.template`'s `access_control` block rewritten per the identity model decided above: explicit `pihole.${DOMAIN}` and `traefik.${DOMAIN}` rules requiring `subject: ['group:purrbrews_infra_admins']`, placed above a `*.${DOMAIN}` catch-all (still `one_factor`, no group restriction) for everything else — Authelia matches rules top-to-bottom and stops at the first hit, so ordering here isn't cosmetic. Verified the rendered form parses as valid YAML (dummy-substituted `DOMAIN`/secret values, same method used for `dynamic.yml.template` earlier). Not yet brought up or tested against real lldap groups — needs the `purrbrews_infra_admins` group and `barista`'s membership in it to actually exist first, or the group check has nothing to match and `barista` gets denied same as anyone else.

## 2026-08-30 (cont.) — DHCP outage: root cause was a missing `67/udp` ufw rule

**Incident:** house-wide DHCP stopped working some hours after the router's own DHCP server was disabled (see the NET_ADMIN entry above) to let Pi-hole take over as leases expired. Immediate mitigation: re-enabled the router's DHCP server to restore connectivity while root-causing.

**Root cause:** never a Pi-hole problem. `docker exec pihole cat /etc/pihole/pihole.toml` confirmed DHCP was correctly `active = true` with the intended pool (`start = "192.168.0.50"`), and `docker exec pihole ss -lntup | grep :67` confirmed FTL had the socket genuinely bound and listening on `0.0.0.0:67`. The gap was `ufw`: no rule had ever been added for DHCP specifically — only `8080/tcp` (Traefik → Pi-hole webui) and `53/tcp`+`53/udp` (DNS) exist from the port-80 troubleshooting session, and DHCP was never part of that. Default-deny-incoming meant every `DHCPDISCOVER` broadcast was silently dropped before reaching FTL's listener — a fully healthy, correctly-configured service that nothing could reach. Framed usefully by User Penguin: this is `ufw` working exactly as intended (fail-closed), not a bug — it just happened to catch a port that genuinely needed opening and hadn't been yet.

**Fix:**

```sh
sudo ufw allow proto udp to any port 67 comment 'pihole dhcp'
```

Scoped to "any" source deliberately, not the LAN subnet — a client's very first `DHCPDISCOVER` is sent from source `0.0.0.0` (it has no IP yet), so subnet-scoping this rule the way DNS's was scoped would have silently failed the same way all over again.

**Lesson for the DHCP-bake-in backlog item:** this ufw rule is a separate piece of state from `pihole.toml`'s `[dhcp]` block and from any future `FTLCONF_dhcp_*` env vars — baking DHCP into the compose file doesn't help if the port is still firewalled. Backlog item above updated to call this out explicitly as part of "proven stable" before that migration happens.

## 2026-08-30 (cont.) — Authelia crash-loop on first bring-up: two missing config options

First `./compose.sh authelia up -d` on sieve crash-looped — `docker logs authelia` showed two `level=fatal` config errors, distinct from the LDAP/Redis connectivity worries the pre-bring-up walkthrough was actually watching for:

- `authentication_backend: ldap: option 'users_filter' is required` / `'groups_filter' is required` — Authelia's LDAP backend defaults to a fully generic mode with no filters assumed. Fixed by adding `implementation: 'lldap'` under `authentication_backend.ldap` in `configuration.yml.template` — a first-class preset Authelia ships specifically for this project, which supplies the matching filters/attribute mappings instead of requiring them spelled out by hand.
- `identity_validation: reset_password: option 'jwt_secret' is required when the reset password functionality isn't disabled` — a newer Authelia config path (moved under `identity_validation.reset_password` from an older top-level `jwt_secret`). Fixed by adding a `identity_validation.reset_password.jwt_secret` block and a new generated secret, `AUTHELIA_RESET_PASSWORD_JWT_SECRET`, wired into `generate-secrets.sh` the same way `AUTHELIA_SESSION_SECRET` already was.

(The repeating `chown: /config/configuration.yml: Read-only file system` line in those same logs is harmless — Authelia's entrypoint trying to `chown` a file deliberately bind-mounted `:ro`. Not related to the fatal errors.)

## 2026-08-30 (cont.) — De-hardcoded the lldap group name; added `lldap-bootstrap.sh`

User Penguin caught that `access_control`'s `group:purrbrews_infra_admins` was a literal string in the template rather than a variable, unlike `${DOMAIN}`. Fixed: new `LLDAP_INFRA_ADMIN_GROUP` var in `.env.local` (default `purrbrews_infra_admins`, seeded by `generate-secrets.sh`), referenced in `configuration.yml.template` as `${LLDAP_INFRA_ADMIN_GROUP}` — `render-configs.sh` needed no changes, since it already passes every `.env.local` var through to `envsubst`.

That surfaced a second, deeper gap: templating the variable only gives Authelia one place to read the expected group name from — it does nothing to make lldap itself aware that name exists, since lldap's groups are directory data (created via its own UI/API), not compose-time config the way `LLDAP_ADMIN_PASSWORD` is. Closed with a new script, `lldap-bootstrap.sh` — logs into lldap's REST auth endpoint as `admin`, then uses its GraphQL API (same one the admin UI calls) to create `LLDAP_INFRA_ADMIN_GROUP` if missing and add `barista` to it if not already a member. Idempotent, run after `./compose.sh lldap up -d` and before Authelia. Deliberately does **not** create the `barista` account itself — that stays a manual step in the UI, since its SSO password is meant to be typed in and known by the user, not auto-generated into a secrets file the way service-to-service credentials are.

**Not yet verified against a real lldap instance** — this is the first script in the stack to call lldap's GraphQL API rather than just generate config for it, and the field/mutation names (`createGroup`, `addUserToGroup`, `user { groups { id displayName } }`, etc.) are reconstructed from lldap's documented schema, not exercised live (no network path from this session to sieve's LAN). Written to fail loudly and print lldap's own GraphQL error text on a mismatch rather than fail silently — first real run is the actual test.
