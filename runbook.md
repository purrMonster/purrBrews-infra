# PurrBrews Runbook

Living operational reference for Project PurrBrews. Entries are dated as decisions are made; this keeps the "why" attached instead of just the "what." See the full initiation document set (`purrbrews-project-initiation-set_4.html`) for the charter/scope/architecture this runbook implements.

## Backlog / open items

Pulled up from the dated entries below so nothing gets lost in the log. Check items off (or just delete the line) as they're done — leave a dated entry below for anything worth remembering *why* about.

- [x] Confirm physical cabling matches the floor plan (Section 0.12) — done 2026-08-27
- [x] Run `purrbrews-init.sh` for real on sieve, silo, cellar — done 2026-08-28 per User Penguin, and extended to all five (sieve, silo, cellar, percolator, mochaPot) rather than just the original three. Not independently verified from this session (no SSH access to the fleet) — taken on report.
- [x] Generate + distribute the age keypair (on sieve, first) — exists on sieve per User Penguin (2026-08-28). Now actually in use: public key retrieved 2026-08-31 (`sudo age-keygen -y /etc/purrbrews/age/keys.txt`) and wired into `.sops.yaml` — see the 2026-08-31 entry below.
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
- [x] Decide the secrets approach for silo/cellar/percolator/mochaPot's app stacks — decided 2026-08-31: SOPS+age as originally planned (Section 19.3), starting at silo. `.sops.yaml` + `stacks/silo/generate-secrets.ps1` + `stacks/silo/decrypt-secrets.sh` scaffolding built; no app-specific secrets defined yet since no silo app is built yet. See 2026-08-31 entry below.
- [ ] Route lldap's admin UI (sieve, port 17170) through Traefik + Authelia instead of its current direct host-port exposure
- [ ] On sieve: run `docker network inspect sieve_proxy` to get its real subnet, then `sudo ufw allow from <subnet> to any port 8080 proto tcp` — required for Pi-hole's admin UI to work through Traefik at all, and is the entire security boundary now that Pi-hole's own password is disabled (2026-08-29 entry). Also confirm the DNS ufw rules (`53/tcp`+`53/udp`, LAN-scoped) from the same troubleshooting session got applied.
- [ ] Check Pi-hole's own docs (and whether a community fork exists) for a real reverse-proxy auth-trust mechanism (header-based or OIDC), as a more robust replacement for disabling its password outright (2026-08-29 entry) — checked: no support exists today, upstream or fork; disabling the password is the recognized workaround, not a stopgap (2026-08-30 entry)
- [ ] Bake Pi-hole's DHCP settings (range, router, lease time) into `pihole/docker-compose.yml` as `FTLCONF_dhcp_*` env vars, same durability reasoning as `FTLCONF_dns_upstreams` — **only after** confirming real devices are picking up leases cleanly from Pi-hole over a few days. Router's own DHCP was switched off 2026-08-30 to let this take over as leases expire; don't touch the compose file's DHCP config until that's proven stable — getting it wrong here means every device in the house loses DHCP, not just a test container (2026-08-30 entry). **Include the `67/udp` ufw rule (see 2026-08-30 outage entry below) explicitly in that "proven stable" check** — it's a separate thing from the FTL config and just as easy to lose on a rebuild.
- [x] Run `./lldap-bootstrap.sh` for real on sieve and confirm it works against lldap's actual GraphQL API — done 2026-08-30, worked on the first attempt, no schema fixes needed (see that entry)
- [ ] Set an explicit `maxResponseBodySize` limit on the `authelia@docker` forward-auth middleware (Traefik warns it's unbounded on every reload — see 2026-08-30 Traefik bring-up entry) — confirm the correct Traefik v3 label syntax before adding it, not guessed live
- [x] Run `./pihole-dns-bootstrap.sh` for real on sieve at least once — done 2026-08-30, correctly reported "Currently set: 4 line(s)" / "All 4 split-horizon entries already present — nothing to do", confirming the FTL `[ item, item ]` readback parsing works against real output, not just the simulated test data it was checked against before delivery.
- [x] Run `./compose.sh headscale up -d` then `./headscale-bootstrap.sh --dry-run` for real on sieve — done 2026-08-30. Took three fix rounds to get here (missing `prefixes` config, the `null`-vs-`[]` JSON quirk, then the hardcoded-user-list redesign — see that entry), but the final version ran clean: `./headscale-bootstrap.sh barista` correctly read 0 existing users and created `barista` with no errors.
- [x] Add a first real device to the tailnet — done 2026-08-30, sieve itself: generated a single-use pre-auth key for `barista`, installed the Tailscale client on the sieve host (`curl -fsSL https://tailscale.com/install.sh | sh` — deliberately on the host, not a container, since it needs a real network interface), joined with `tailscale up --login-server=https://headscale.whiskertreat.fyi --accept-dns=false --authkey=<key>`. `--accept-dns=false` was deliberate and specific to sieve — it's the one node that must NOT have Tailscale take over system DNS, since sieve's own resolv.conf already points at its own Pi-hole (127.0.0.1) and Tailscale's default behavior on `tailscale up` is to redirect the node's DNS to Headscale's MagicDNS proxy. Confirmed working both sides: `tailscale status` and `headscale nodes list`. Headscale's end-to-end chain is proven now — not just "container healthy," an actual device joined and is visible on both ends.
- [x] Bring up `cloudflared` — done 2026-08-30/31, exposing only `headscale.${DOMAIN}` publicly, as planned. Took three bug fixes to get working end to end — see that entry. **Note: two of the three fixes live entirely in the Cloudflare Zero Trust dashboard, not this repo** — the route's Service URL (`https://traefik:443`, not `http://traefik:80`) and Origin Server Name (`headscale.${DOMAIN}`) settings. If this tunnel/route is ever recreated from scratch, both need to be set again by hand; nothing in this repo captures or reproduces them automatically. Worth a screenshot or written note kept somewhere durable outside git, since `secrets.env.local`/`.gitignore`'d files aren't the right place for a non-secret dashboard config record either.
- [ ] Run the updated `pihole-dns-bootstrap.sh` (now manages an AAAA-block `::` line per subdomain, not just A) for real on sieve — script logic verified against the current live state (should detect `headscale`'s AAAA-block as already present from the live fix, and add the other three), not yet actually run.
- [ ] Check whether Headscale's `dns.nameservers.global` (currently plain `1.1.1.1`/`1.0.0.1`) should point tailnet clients at Pi-hole instead, so a device that's on the tailnet but not the LAN can actually resolve `pihole.${DOMAIN}`/`traefik.${DOMAIN}`/etc., not just reach them over the mesh (see 2026-08-30 "Headscale vs. cloudflared" entry)
- [ ] Confirm `sops`/`age` actually work end to end on roastery (`sops --version`, `age --version`) — installed via `winget install SecretsOPerationS.SOPS` / `winget install FiloSottile.age` 2026-08-31, not yet confirmed working before the age-keygen detour took over (see 2026-08-31 entry)
- [ ] Run `stacks/silo/generate-secrets.ps1` and `stacks/silo/decrypt-secrets.sh` against a real encrypted file, once silo's first app that needs a secret is actually built (Komodo, most likely) — the no-secrets-yet no-op path is now confirmed working (`./decrypt-secrets.sh` run for real on silo 2026-08-31, correctly reported "No .../secrets/silo yet — nothing to decrypt" and exited clean), but the actual encrypt/commit/decrypt round-trip is still untested against real ciphertext
- [ ] Build silo's real DIY dashboard — still deferred (declined both Homepage and Homarr as the *permanent* choice 2026-08-31; "we will build something"). No design started yet. A stopgap Homepage instance was added the same day so there's something usable in the meantime — see that entry below; swap it out when the real one's built, don't build on top of it.
- [ ] Run `sudo ufw allow from 192.168.0.0/24 to any port 3000 proto tcp` on silo before Homepage is reachable — not yet run, no SSH access to silo from this session
- [ ] Route Homepage through Traefik/Authelia instead of its current direct host-port exposure (`<SILO_LAN_IP>:3000`) — same standing backlog item as lldap's admin UI on sieve, now with a second instance of the same pattern
- [ ] On silo: `sudo ufw allow from 192.168.0.10 to any port 53 proto tcp` and the same for `proto udp` — required before Unbound is reachable from sieve at all; not yet run, no SSH access to silo from this session
- [x] Verify Unbound is actually restricted to sieve — done 2026-08-31, third attempt: `dig @192.168.0.12 example.com` from percolator (not sieve) correctly returned `REFUSED`; the same command from sieve itself correctly returned a real `NOERROR` answer. Both halves of the access-control rule confirmed working on real hardware — see the two prior 2026-08-31 Unbound access-control entries for the two failed attempts before this one.
- [ ] Verify the `172.16.0.0/12`/`10.0.0.0/8` refuses in `unbound/config/access-control.conf.template` actually take effect — unlike the `192.168.0.0/24` refuse (proven by Unbound's documented longest-prefix-match, no ambiguity), these rely on same-prefix-length tie-break behavior Unbound's own manpage doesn't define. Low priority (would need code execution inside a container on silo itself to matter — no device on this network lives in either range), but flagged rather than assumed.
- [ ] Once Unbound is verified: point sieve's Pi-hole at it (`stacks/sieve/pihole/docker-compose.yml`'s `FTLCONF_dns_upstreams`, currently `1.1.1.1;1.0.0.1`) instead of the public fallback — deliberately not done in the same change that brought Unbound up (see 2026-08-31 Unbound entry)
- [ ] CrowdSec: find an alternate method to fetch/list/unban specific records (`cscli decisions ...`) without needing direct SSH/LAN/tailnet access to the node itself — needed in case a self-inflicted ban blocks the only path back in (see 2026-08-31 discussion: since only Headscale is public, the real risk case is a brand-new device failing to enroll from outside). Needs discussion, not decided. Current line of thinking: a Telegram bot or a Nextcloud Talk chat bot as the remote trigger. Revisit once CrowdSec is actually being built (Section 18.3, second app on silo).
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

**Verified 2026-08-30, same day:** ran on sieve (without `--dry-run`, by accident — but the script's own idempotency made that harmless) and worked cleanly on the first real attempt: `purrbrews_infra_admins` created (`id=4`), `barista` added, no GraphQL errors. The reconstructed schema (`createGroup`, `addUserToGroup`, `user { groups { id displayName } }`) was correct as written — no follow-up fix needed. Re-running it now (dry-run or not) is a no-op confirming "already exists"/"already a member."

## 2026-08-30 (cont.) — Traefik first bring-up: real certs issued, one stray label removed

First `./compose.sh traefik up -d` on sieve mostly worked cleanly: `providers.docker`/`providers.file` both started, Authelia's forward-auth middleware resolved (after a one-time race at boot — `middleware "authelia@docker" does not exist` logged once at container start before the docker provider had synced, self-resolved by the next reload, doesn't recur), and real Let's Encrypt certs were issued via the Cloudflare DNS-01 challenge for `pihole.${DOMAIN}`, `traefik.${DOMAIN}`, and `authelia.${DOMAIN}` — the actual hard part of this bring-up worked first try.

One real bug: `traefik/docker-compose.yml` had `traefik.enable=true` on the `traefik` service itself with no accompanying router-rule label. Traefik's docker provider auto-generated a default router from that (`Host(\`traefik-traefik\`)` — a hostname with no dot) and, because the `websecure` entrypoint applies `certResolver: cloudflare` to every router on it, tried and failed to get that garbage hostname an ACME certificate on every single config reload: `Cannot issue for "traefik-traefik": Domain name needs at least one dot`. Not fatal — the real routes were unaffected — but noisy, pointless, and technically hammering Let's Encrypt's API for a certificate that could never be valid. Fixed by removing the label entirely: the dashboard route already exists via the file provider (`dynamic.yml`'s `traefik-dashboard` router → `service: api@internal`), same reasoning as Pi-hole not needing docker-label discovery — this container never needed `traefik.enable=true` at all.

Also noted, not yet fixed: `maxResponseBodySize is not configured` warnings on the `authelia@docker` forward-auth middleware (both `pihole` and `traefik-dashboard` routers) — legitimate Traefik hardening advice, not an error. Backlog item added to set an explicit limit once the right v3 label syntax is confirmed, rather than guess at it live.

Two ufw rules also needed adding before any of this was reachable from the LAN at all — `80/tcp` and `443/tcp`, scoped to the real LAN subnet (`192.168.0.0/24`), unlike Pi-hole's `8080/tcp` rule which is deliberately scoped to `sieve_proxy`'s docker subnet only.

**Verified 2026-08-30, same day:** pulled the label fix, recreated the `traefik` container, and confirmed with three separate `sudo docker logs traefik --since 5m | grep -i "traefik-traefik"` checks — all three returned empty output, no recurrence. Traefik's running clean: real certs for pihole/traefik/authelia, no bogus self-cert attempts, Authelia's forward-auth middleware resolved. This bug is closed.

## 2026-08-30 (cont.) — First real login test: "Site can't be reached" — Pi-hole v6 doesn't read `/etc/dnsmasq.d` at all

The actual end-to-end test (browse to `pihole.${DOMAIN}`/`traefik.${DOMAIN}`, expect a redirect to Authelia's login, log in as `barista`, land on the real dashboard) failed at the very first step: the hostname didn't resolve. `nslookup` from the client confirmed Pi-hole (`192.168.0.10`) was correctly set as the DNS server and was actively answering — just with `NXDOMAIN`, not a timeout or fallback. That ruled out the DHCP-outage DNS-server-mismatch theory from earlier today and pointed straight at the split-horizon config itself.

Checked in order: the rendered `pihole/custom-dns/05-purrbrews-split-horizon.conf` had the correct real values (not leftover `${DOMAIN}` literals); `pihole/docker-compose.yml` correctly bind-mounted it into `/etc/dnsmasq.d/05-purrbrews-split-horizon.conf`; `docker exec pihole cat` on that path inside the running container confirmed it was really there with the right content. Everything about the file itself was right. Restarting the container (in case dnsmasq just hadn't picked up a file that appeared after boot) didn't fix it either.

Root cause, found in the FTL startup log: `cat: /etc/dnsmasq.conf: No such file or directory`, and separately `Parsed config file /etc/pihole/pihole.toml successfully` with `167 total entries`. This image is Pi-hole v6 (FTL v6.7) — the whole `/etc/dnsmasq.d/*.conf` drop-in mechanism is a v5-era pattern. FTL v6 generates dnsmasq's real config entirely from `/etc/pihole/pihole.toml` at every startup and **never scans `/etc/dnsmasq.d` at all**. Our bind-mounted file wasn't malformed, misplaced, or stale — it was just structurally invisible to the resolver, silently, with no error anywhere. This was a wrong mental model carried over from Pi-hole v5 docs/habits, not a config mistake.

The real v6 equivalent, found by grepping `pihole.toml`'s own inline documentation: `[misc] dnsmasq_lines = []`, described as "Array of valid dnsmasq config line options" with an example (`"address=/example.com/192.168.0.1"`) that matches our syntax exactly. Set live via `pihole-FTL --config misc.dnsmasq_lines '["address=/pihole.${DOMAIN}/192.168.0.10", ...]'` (JSON array of strings) rather than editing `pihole.toml` by hand, since FTL owns and rewrites that file — confirmed working immediately: `nslookup` started returning `192.168.0.10` instead of NXDOMAIN, and the full browser login test then succeeded end to end (Traefik → Authelia login as `barista` → lldap `purrbrews_infra_admins` group check → real dashboard access, for both pihole and traefik).

Made durable the same day: `pihole/docker-compose.yml`'s dead `/etc/dnsmasq.d` bind mounts removed entirely; the now-inert `pihole/custom-dns/05-purrbrews-split-horizon.conf.template` deleted; replaced with a new idempotent script, `pihole-dns-bootstrap.sh` (same pattern as `lldap-bootstrap.sh` — reads current state via `pihole-FTL --config misc.dnsmasq_lines`, adds only what's missing, restarts the container only if something actually changed, `--dry-run` supported). `pihole.toml` lives in the already-persistent `/srv/data/pihole/etc-pihole` volume, so the live fix would have survived a normal restart on its own — this just makes it reproducible on a fresh deploy or disaster recovery instead of relying on tribal knowledge of a manually-run CLI command. Script's parsing logic (FTL's `[ item, item ]` readback format isn't JSON — no quotes) was verified against the real captured output before being handed over, not guessed.

**First real end-to-end milestone reached:** the full chain — Traefik routing, Authelia forward-auth, lldap group-based access control, and now real split-horizon DNS — works together for a real browser login as `barista`.

## 2026-08-30 (cont.) — headscale user model decided; `headscale-bootstrap.sh` added

Before bringing Headscale up, decided how its "users" (grouping labels for tailnet devices, not login accounts — mainly relevant once ACL policy gets written, which it hasn't yet) should be split: `barista` owns the fleet's own server nodes (sieve, silo, cellar, percolator, mochaPot), `penguin` and `bubbles` own their respective personal devices. Formalized with a new script, `headscale-bootstrap.sh`, same idempotent/`--dry-run` pattern as `lldap-bootstrap.sh` and `pihole-dns-bootstrap.sh` — reads `headscale users list --output json`, creates whichever of the three users are missing.

Not yet run against a real instance — Headscale itself hasn't been brought up on sieve yet at time of writing. The JSON shape assumed (`[{"id":..., "name":...}, ...]`) is reconstructed from headscale 0.27.x's documented CLI, same caveat as `lldap-bootstrap.sh`'s first version: if `--dry-run`'s user-listing step errors or the output doesn't parse as expected, read headscale's own error first rather than assuming the script's logic is broken elsewhere.

## 2026-08-30 (cont.) — Headscale first bring-up: crash-loop, missing required `prefixes`

`./compose.sh headscale up -d` came up crash-looping immediately, every ~1 minute (the `unless-stopped` backoff cap, same pattern as Authelia's crash-loop earlier today): `FTL ... Error initializing error="loading configuration: no IPv4 or IPv6 prefix configured, minimum one prefix is required"`. The `headscale-bootstrap.sh` dry-run correctly refused to proceed rather than silently doing nothing useful — `docker exec` failed with "Container ... is restarting, wait until the container is running", which the script surfaced as its own clear error rather than misreporting an empty user list.

Root cause: `config.yaml.template`'s "trimmed to essentials" first pass dropped the `prefixes` block entirely — the IPv4/IPv6 address ranges headscale allocates to devices as they join the tailnet. Not actually optional in 0.27.x despite the trimmed template treating it as such. Fixed by adding headscale's own documented defaults — same ranges Tailscale's hosted service uses, so nothing app-specific to choose here: `prefixes.v4: 100.64.0.0/10` (CGNAT range, RFC 6598 — won't collide with the real `192.168.0.0/24` LAN) and `prefixes.v6: fd7a:115c:a1e0::/48` (headscale's fixed ULA v6 prefix).

Took two attempts to actually land on sieve: the file fix alone doesn't do anything until it's committed+pushed from roastery and `git pull`-ed on sieve (not a git operation — writing to roastery's checkout is a plain file write), and separately `render-configs.sh` has to be re-run before a restart picks up a changed `.template` — missed the render step on the first retry, same class of gotcha as always. Once actually rendered and restarted, headscale started clean: `Starting Headscale ... version=v0.27.1+dirty`, listening on 8080. (The `WRN Listening without TLS but ServerURL does not start with http://` warning is expected and harmless — Traefik terminates TLS in front of this container, headscale itself only ever sees plain HTTP from Traefik over `sieve_proxy`.)

Second, smaller bug found immediately after: `headscale-bootstrap.sh`'s `--dry-run` failed with "Expected a JSON array ... but got: null" — `headscale users list --output json` prints the literal `null`, not `[]`, when there are zero users (a Go nil-slice-marshals-to-null quirk), which is exactly the state of a genuinely fresh instance. The script's type check only accepted `array`. Fixed: check now accepts `null` as equivalent to zero users, and the name-extraction uses `(. // [])[].name` so `null` is treated as an empty array rather than erroring. This is the one part of the script that couldn't have been caught by pre-delivery testing — it only shows up against a real instance with zero users in it, which didn't exist until this exact moment.

Third, a design mistake caught by User Penguin before ever running it for real: the script hardcoded `USERS=(barista penguin bubbles)` and would have created all three unconditionally. Two problems with that — it's the same "no hardcoding" instinct as the lldap group name earlier today (a headscale user is a provisioning action, not a fixed structural fact like the DNS subdomain list `pihole-dns-bootstrap.sh` legitimately hardcodes), and more importantly it silently ran ahead of the standing decision (from earlier in this build, before today) to hold off creating `penguin`/`bubbles`' actual accounts anywhere — lldap included — until "everything's up and we're ready to use the system like production." Fixed by taking usernames as CLI arguments instead of a baked-in list: `./headscale-bootstrap.sh barista` now, `./headscale-bootstrap.sh penguin bubbles` later whenever those two are actually being onboarded. No-args and `--dry-run`-with-no-names both refuse with a usage message rather than falling back to any default.

`./headscale-bootstrap.sh barista` then ran clean against the real (fixed) instance: 0 existing users read correctly, `barista` created with no errors.

## 2026-08-30 (cont.) — First real device on the tailnet: sieve itself

Generated a single-use pre-auth key for `barista` (`headscale preauthkeys create --user barista --expiration 1h`), installed the Tailscale client directly on the sieve host via the official install script (deliberately on the host, not in a container — it needs a real network interface to create the `tailscale0` device, not something docker's network namespacing accommodates cleanly), then joined with `tailscale up --login-server=https://headscale.whiskertreat.fyi --accept-dns=false --authkey=<key>`.

`--accept-dns=false` was deliberate, specific to this one node: Tailscale's default behavior on `tailscale up` is to take over the node's system DNS resolver to point at Headscale's MagicDNS proxy — correct for a normal device, wrong for sieve specifically, since sieve *is* the DNS server (its own `/etc/resolv.conf` already points at itself, `127.0.0.1` → Pi-hole, confirmed via the `nslookup` output during the earlier login-test troubleshooting). Letting Tailscale rewrite that would have had sieve routing its own DNS queries through Headscale's proxy instead of resolving locally — a self-inflicted version of the exact class of DNS confusion already debugged twice today. Future devices joining the tailnet (a phone, roastery) should use the default (`--accept-dns` on, or simply omit the flag) to actually get MagicDNS's `*.ts.whiskertreat.fyi` resolution.

Confirmed both sides after joining: `tailscale status` on sieve and `headscale nodes list` in the container both show the node. This is the actual end-to-end proof for Headscale — not just "the container starts and a user exists," but a real device successfully authenticated against it and joined the mesh.

## 2026-08-30 (cont.) — Headscale vs. cloudflared: why only Headscale needs to go public

Written up because User Penguin flagged confusion about how these two relate, before bringing `cloudflared` up — worth having this settled in writing rather than re-explained from scratch later.

**What each one actually is.** Headscale is the control plane for a private mesh VPN (Tailscale) between *your own* devices — sieve, silo, roastery, a phone, whatever you add. It doesn't expose anything to the public; it's the opposite, a private network that only devices you've explicitly authorized can join. `cloudflared` is Cloudflare Tunnel — the mechanism for exposing specific services to the *public* internet without opening any inbound port on the router. They solve opposite problems: Headscale is about *you* reaching *your own stuff* privately from anywhere; `cloudflared` is about making a *specific service* reachable by anyone (or anyone who then has to get past whatever auth sits in front of it, like Authelia).

**Why Headscale needs `cloudflared` at all, given it's meant to be private.** This is the part that reads contradictory at first: something whose whole purpose is privacy needs a public entry point. The reason is a bootstrapping problem — a device has to reach Headscale *before* it's on the tailnet, in order to join the tailnet. There's no way around this chicken-and-egg: you can't rely on the private mesh to deliver you into the private mesh. So Headscale's own coordination endpoint (`headscale.${DOMAIN}`) has to be reachable by ordinary means — the public internet — even though what it hands out (mesh membership) is private. This is exactly how Tailscale's own hosted service works too: `controlplane.tailscale.com` is a perfectly public, unauthenticated-at-the-network-level URL; what's actually gated is *joining* (via your login/pre-auth key), not *reaching* the coordination server.

**Why nothing else needs to go through `cloudflared`.** Once a device has actually joined the tailnet via Headscale, it can reach every other sieve-hosted service directly over the encrypted mesh — no public exposure needed for `pihole.${DOMAIN}`, `traefik.${DOMAIN}`, etc. Those are already reachable two ways: on the LAN directly (split-horizon DNS via `pihole-dns-bootstrap.sh`), and — once a device is on the tailnet — over the mesh from anywhere, without ever touching the public internet. Exposing them *additionally* through `cloudflared` would just be more public attack surface for zero added reach, since anything that can already join the tailnet already has a private path to them. Current plan (not yet executed, see backlog): `cloudflared`'s only public hostname is `headscale.${DOMAIN}` → `http://traefik:80` as origin, same as every other route.

**One thing worth confirming later, not yet checked:** whether Headscale's own DNS config (`dns.nameservers.global` in `config.yaml.template`, currently plain `1.1.1.1`/`1.0.0.1`) should instead point tailnet clients at Pi-hole, so that once a device is on the mesh, `pihole.${DOMAIN}`/`traefik.${DOMAIN}`/etc. actually resolve for it the same way they do on the LAN. Right now a tailnet-only device (not also on the LAN) has network *reach* to those services over the mesh but no guarantee its DNS resolves the hostname to get there. Flagged in the backlog.

## 2026-08-30/31 (cont.) — `cloudflared` first bring-up: three real bugs, all found live

Cloudflare Zero Trust dashboard side was set up first (a Published application route: `headscale.${DOMAIN}` → `http://traefik:80`), then `./compose.sh cloudflared up -d`. The tunnel itself connected cleanly on the first try — four registered connections to Cloudflare's edge (bom10, maa05, bom11, maa01), correct ingress config picked up. But the actual application path had three separate, unrelated bugs, found one at a time by testing from real networks rather than trusting a clean tunnel log.

**Bug 1 — redirect loop (cellular, Safari: "cannot follow more than 20 redirections").** The route's origin service was `http://traefik:80`, but Traefik's port-80 entrypoint force-redirects everything to HTTPS (`entryPoints.web.http.redirections`, decided 2026-08-29). cloudflared doesn't follow that redirect itself — it just relays Traefik's 301 straight back to the browser, which re-requests the exact same public URL, which goes through the tunnel again, hits port 80 again, redirects again. Infinite loop. Fixed by changing the route's Service URL to `https://traefik:443`.

**Bug 2 — TLS cert mismatch (Cloudflare `502 Bad Gateway`, cloudflared log: `tls: failed to verify certificate: x509: certificate is valid for <random>.traefik.default, not traefik`).** Switching to `https://traefik:443` alone wasn't enough: cloudflared connects using the Docker service name `traefik` as the TLS SNI, but Traefik has no certificate for that name — only for the real hostnames (`headscale.${DOMAIN}` etc.) — so it fell back to its own auto-generated self-signed default cert, which correctly failed cloudflared's validation. Two possible fixes: disable validation (`No TLS Verify`) or make cloudflared present the right SNI so Traefik hands back its real cert. Went with the latter — set **Origin Server Name** to `headscale.${DOMAIN}` in the route's Additional application settings — since it makes the actual security check pass instead of skipping it, and Traefik already had a real, working Let's Encrypt cert for that exact name (proven when sieve joined the tailnet earlier). Cellular test then got a blank page — correct, expected result, since Headscale doesn't serve real content at `/`.

**Bug 3 — AAAA record leak (LAN/Chrome: `ERR_QUIC_PROTOCOL_ERROR`, then `ERR_ECH_FALLBACK_CERTIFICATE_INVALID` after disabling QUIC in chrome://flags).** This one only showed up on the LAN, not cellular. `nslookup headscale.${DOMAIN}` from a LAN client returned `192.168.0.10` (correct, from Pi-hole's override) *and* two real Cloudflare IPv6 addresses (`2606:4700:...` — Cloudflare's own address block). Root cause: `pihole-dns-bootstrap.sh`'s `address=/domain/ip` line only intercepts A (IPv4) queries — an AAAA (IPv6) query for the same name still gets forwarded upstream and answered for real, and now that `headscale.${DOMAIN}` has genuine public DNS (via the Cloudflare Tunnel route), that upstream answer is Cloudflare's actual edge addresses. Most OSes/browsers prefer IPv6 when it's offered, so LAN clients were connecting straight to Cloudflare's public edge instead of to sieve — a self-inflicted variant of the same "local override doesn't cover everything it needs to" class of bug as the DHCP/dnsmasq.d issues earlier this week. Fixed by adding `address=/domain/::` (an unroutable address, forces fallback to the real IPv4 answer) for every split-horizon subdomain, applied defensively to all four rather than just `headscale` — so this doesn't need rediscovering the next time another one gets exposed publicly. `pihole-dns-bootstrap.sh` updated to manage both lines per subdomain going forward.

Confirmed working end to end after all three fixes: cellular → blank page at `/`, `200 OK`/`{"status":"pass"}` at `/health`; LAN → clean `nslookup` (only `192.168.0.10` and the harmless `::`), same `200 OK`/`{"status":"pass"}` at `/health` via PowerShell's `wget`. Both paths — public internet through the tunnel, and LAN through Traefik directly — now correctly reach Headscale.

## 2026-08-31 — Moving to silo: build order confirmed, secrets approach decided, dashboard deferred

With cloudflared working end to end, three decisions before any silo work started:

**Build order.** The initiation doc's own dependency chain (Section 18.5-adjacent) has percolator/mochaPot deploying "via Komodo, not raw CLI" — but Komodo itself lives on silo and doesn't exist yet. Flagged this to User Penguin rather than jumping straight to percolator as first suggested; confirmed: follow the documented order, silo next. sieve and silo stay the two hand-deployed-over-SSH nodes; cellar onward goes through Komodo's git-sync once silo's built.

**Secrets: switching to SOPS+age, starting at silo.** Reopened the backlog item from 2026-08-28 (sieve's stack deliberately went with local-only plaintext `generate-secrets.sh` instead of the originally-planned SOPS+age, since the age key wasn't in active use yet and there was no reason to add ciphertext-in-git complexity for a hand-deployed node). The real forcing function for revisiting it now: Komodo's git-sync deployment model (cellar onward) needs *some* secrets-in-git mechanism — a node that only ever receives code via `git pull` can't have a human typing real values into a local file the way sieve/silo can. Presented this reasoning to User Penguin rather than assuming either default; decided: switch now, starting at silo, rather than waiting for cellar/Komodo to force the issue — proves the mechanism works before anything actually depends on it.

Retrieved the age **public** key from sieve: `sudo age-keygen -y /etc/purrbrews/age/keys.txt` → `age15q5dhgpwcwj54rl8r9hy5v5yrmj5jqdt38jlut37h9wkgxa0ycvsx4g86g` (first attempt pointed at the `age-keygen` binary itself instead of the key file — `/usr/bin/age-keygen` vs. the real path from `purrbrews-init.sh`'s `AGE_KEY_FILE`, `malformed secret key: mixed case`; fixed by reading the actual source instead of guessing a second path). **The private key was never seen by Claude at any point** — only ever the public key, by design; `age-keygen -y` derives the public key from the private one without printing the private key itself.

Built the scaffolding (`.sops.yaml` at repo root, `secrets/silo/`, `stacks/silo/generate-secrets.ps1` + `decrypt-secrets.sh`) — see `secrets/README.md` for the full layout and `stacks/silo/README.md` for the workflow. Key design point: kept the existing `secrets.env.local` consumption pattern (`compose.sh --env-file`, `render-configs.sh`'s envsubst) completely unchanged — `decrypt-secrets.sh` just decrypts `secrets/silo/<app>.sops.yaml` via `sops -d --output-type dotenv` into the exact same filename sieve's apps already use, so nothing about how an app actually reads its secrets had to change, only where the real value comes from. Followed the pre-existing `secrets/README.md` convention discovered on roastery (dated 2026-08-27, from before this session touched secrets at all) — `secrets/<name>.sops.yaml`, `sops -e -i` in place — rather than inventing a different one; extended it with a `secrets/<node>/` subdirectory layer since that convention didn't yet say how multiple nodes' files should be organized.

Along the way, installed `sops`/`age` on roastery via `winget` — two real package-naming gotchas, not obvious from the tool names alone: `sops`'s real winget package ID is `SecretsOPerationS.SOPS` (`winget install mozilla-sops` fails — that's the old upstream name, not the package ID), and `age`'s is `FiloSottile.age` specifically (a plain `winget install age` search surfaces an unrelated Microsoft Store astrology app also named "age" — needed the exact ID to disambiguate).

**Dashboard: deferred, marked DIY.** Asked Homepage vs. Homarr for silo's dashboard app (originally in the Section 18.3 app list); User Penguin's answer was neither — "we will build something. Mark it as DIY and add it to backlog." No placeholder built; removed from silo's active build list, tracked as its own backlog item instead.

Not yet done: any of silo's actual apps. `generate-secrets.ps1`/`decrypt-secrets.sh` are untested against a real encrypted file — first real exercise will be whichever silo app needs a secret first (Komodo, most likely, for a webhook/API secret). Unbound is next per Section 18.3 (first in silo's own app order, no secrets expected).

## 2026-08-31 (cont.) — Stopgap Homepage dashboard added, ahead of the Section 18.3 order

Revisited the dashboard decision from earlier the same day: having deferred *building* one (DIY, still backlogged), User Penguin asked for a simple existing one anyway, to have something usable in the meantime — "choose any for simplicity which will serve till we create the homepage." Picked [Homepage](https://gethomepage.dev) (`gethomepage/homepage`) over Homarr for the same reason it was one of the two original options: plain YAML config, no database, least to go wrong for something explicitly temporary.

Went in ahead of Unbound/CrowdSec/etc. in the Section 18.3 order — deliberately: it's not part of that sequence at all (never was in Section 18.3's own list), it's a standalone add that doesn't depend on or block anything else silo needs.

Followed lldap's existing precedent exactly for the "reachable but not yet properly routed" question, rather than inventing a new pattern: host-published directly (`3000:3000`), no Traefik/Authelia in front of it, LAN-scoped ufw rule needed before it's reachable, backlog item to route it properly later. Considered wiring it through Traefik now instead (cross-node — Traefik lives on sieve, would need a static backend entry in `dynamic.yml` pointing at silo's LAN IP rather than docker-provider discovery, since it's a different host) but that's real new plumbing for a dashboard being explicitly thrown away later; not worth building now.

One real thing verified before writing the compose file, not guessed: `HOMEPAGE_ALLOWED_HOSTS`. Homepage's 1.0 release added strict `Host`-header validation — without this env var set to include `${SILO_LAN_IP}:3000`, every request from a LAN IP (as opposed to `localhost`) gets rejected outright. Confirmed via Homepage's own docs (format: comma-separated, `host` or `host:port`) before committing the compose file, since this is exactly the class of bug (a working container that silently refuses all real traffic) this project has hit more than once already this week.

Also needed `DOMAIN` in silo's `.env.local` for the first time — `services.yaml.template` pre-seeds links to sieve's already-working apps (Traefik, Pi-hole, Headscale), which only resolve correctly with the real domain substituted. `stacks/silo/local.env.example` updated accordingly; nothing else on silo needs `DOMAIN` yet.

Image pinned to `v1.13.2` — checked via GitHub releases (current as of today), not assumed, same discipline as sieve's pinned tags.

Not yet done: actually running `./compose.sh homepage up -d` on silo, and the ufw rule that has to precede it. Both added to backlog above.

## 2026-08-31 (cont.) — Unbound: first app from the actual Section 18.3 order

Asked to "start working on sieve" — flagged rather than assumed, since sieve's own six-app list (Section 18.2) is already fully built and live; User Penguin confirmed this meant silo. Unbound is genuinely first in Section 18.3's own order ("recursive resolver feeding Pi-hole"), unlike Homepage which was a same-day addition outside that list entirely.

**Image choice: `klutchell/unbound`, not `mvance/unbound`.** mvance/unbound is the image most homelab guides reference for exactly this pattern, but checking Docker Hub before pinning it (2026-08-31) found its newest tag (1.22.0) hadn't been updated in roughly two years. klutchell/unbound's `main` tag had been pushed less than a day before this was written. For a DNS resolver — software that gets targeted specifically because it's exploitable if unpatched, and the one thing standing between sieve and the raw internet — freshness won out over mvance having a conventional semver tag. klutchell's image has no semver releases at all (CI-built, tagged by branch/commit) — `main` is the actual documented way to use it, not a shortcut standing in for a real pin; recorded today's digest in a comment for an audit trail without hard-pinning to it (a digest read back through a summarized fetch, not confirmed byte-for-byte — a wrong `image:` digest just fails loudly at pull time either way, so `main` stayed the safer functional choice).

**Networking: bridge + published port, not host networking.** Deliberately different from Pi-hole's `network_mode: host` — Pi-hole needed that for real broadcast/raw-socket DNS+DHCP handling on the LAN; Unbound just needs a normal listening port that Docker's own port-publish handles fine, so there's no reason to give it host networking's wider exposure for no benefit. Kept on the standard port 53 (not remapped to 5335, the usual choice when Pi-hole and Unbound share one host) — no conflict here since Unbound's on silo and Pi-hole's on sieve, so the non-standard remap wasn't needed.

**Config: additive, not a full rewrite.** Only one file — `access-control.conf`, mounted into the image's `custom.conf.d` — restricting queries to `${SIEVE_LAN_IP}/32`, its only intended client. Deliberately did *not* write a full replacement `unbound.conf` from scratch: recursive resolution via root hints, DNSSEC validation, and keeping the root hints/trust anchor current all come from klutchell/unbound's own default config, which is the actual value of using a maintained image over hand-rolling this. Relied on Unbound's documented access-control matching (longest-prefix-match, not load-order) to know a `/32` allow here is airtight regardless of whatever the base default config already contains — confirmed via Unbound's own docs before trusting it, not guessed, since getting this wrong in either direction (too open: an abusable open resolver; too closed: sieve's DNS breaks) both have real consequences.

Not yet done: bringing it up for real. Needs, in order: the sieve-scoped ufw rule on silo (added to backlog above — no SSH access to silo from this session), then `dig`-based verification that the access-control restriction actually holds before trusting it with any traffic, and only after that, repointing sieve's Pi-hole at it — deliberately left as a separate, later change rather than bundled in here, so a bad Unbound bring-up can't take sieve's already-working DNS down with it.

## 2026-08-31 (cont.) — Unbound's first real test: open resolver, not a restricted one

First real bring-up hit two unrelated problems before the actual verification step could even run.

**First: files never reached silo.** Everything from this session (Unbound, Homepage, the SOPS+age scaffolding) had only ever been written into roastery's local checkout via the device bridge — `git add`/`commit`/`push` from roastery, and `git pull` on silo, are steps only User Penguin can run, not something delivering a file to disk does automatically. Worth stating plainly since it wasn't obvious from the delivery messages alone: from here on, a delivery isn't actually on a node until it's been committed, pushed, and pulled there. User Penguin had in fact already done all three by the time this was raised — the confusion turned out to be `dig`'s own argument parsing (see next paragraph), not a stale pull after all.

**Second, the actual verification step: run wrong, then run right, and it failed for real.** First attempt: `dig 192.168.0.12 example.com` (no `@`) — without `@`, `dig` treats every bare argument as a separate name to look up against whatever resolver the querying machine already uses, not as a server to query. Both lookups went to sieve's Pi-hole (the Mac's own configured DNS server), never reaching silo at all — surfaced as a nonsense `NXDOMAIN` for the literal string "192.168.0.12" plus a normal `example.com` answer, neither telling us anything about Unbound. Corrected to `dig @192.168.0.12 example.com` and run again, this time actually reaching silo directly.

That correct run is what surfaced the real bug: queried from User Penguin's Mac — a LAN device that is not sieve — Unbound answered normally (`NOERROR`, two real A records), instead of `REFUSED`. Root cause: the original `access-control.conf.template` (2026-08-31, first written) only ever added `access-control: ${SIEVE_LAN_IP}/32 allow`, on the reasoning that Unbound's longest-prefix-match would make that specific rule win over whatever the base image's default config already had. That reasoning was incomplete — longest-prefix-match only governs what happens for traffic that actually matches the more specific rule; it does nothing to restrict every *other* source IP, which stayed governed entirely by the base default's own (apparently permissive) rules. An `allow` for one client is not the same thing as a `refuse` for everyone else, and the original file only ever had the former.

Fixed by adding an explicit `access-control: 0.0.0.0/0 refuse` (and the IPv6 equivalent, `::0/0 refuse`) alongside the specific allow — relying on a different, correct piece of Unbound's matching behavior this time: for two rules at identical specificity, the one loaded *later* wins, and `custom.conf.d` files load after the base config by design, so this override holds regardless of what the base default's own top-level rule actually was. The specific `/32 allow` for sieve still wins over both via longest-prefix-match, same as originally reasoned — that half was never wrong, it just wasn't sufficient by itself. `access-control` only governs who may *query* Unbound, not its own outbound recursive lookups, so this fix can't break resolution itself.

Not yet confirmed: the fix is written and delivered, but hasn't yet gone through commit/push/pull/render/restart on silo, or been re-tested from a non-sieve LAN device. Until that re-test passes, treat Unbound as an unverified/possibly-open resolver — don't point sieve's Pi-hole at it yet.

## 2026-08-31 (cont.) — Unbound access-control: second attempt also failed, now fixed against the real base config

Applied the first fix (commit/push/pull/render/`docker restart unbound`) and re-tested from two different non-sieve devices (a Mac, then percolator) — both still got a normal `NOERROR` answer. Confirmed via the rendered file on silo and `docker logs unbound` that the new config was actually in place and Unbound started clean with no errors — so this wasn't a deployment problem, the fix itself was still wrong.

`docker exec unbound cat ...` failed outright (`executable file not found in $PATH`) — first real confirmation that this image is genuinely distroless, no shell or coreutils at all, which also means the base image's own default config couldn't be inspected from inside the running container. Went to the actual upstream source instead of another summarized fetch this time: `klutchell/unbound-docker`'s `rootfs_overlay/etc/unbound/unbound.conf` on GitHub, fetched and read directly.

That turned up the real root cause: the base default's own broad `access-control` allows are at **/16** (`192.168.0.0/16 allow`, alongside `/12` and `/8` allows for other private ranges) — not `/0`. The first fix's `access-control: 0.0.0.0/0 refuse` is *less* specific than a `/16`, and Unbound's own manpage is explicit that "the most specific netblock match is used ... the order of the access-control statements therefore does not matter" — so the base's `/16 allow` always won, regardless of anything a `/0` rule said. The original plan B (a same-prefix `/16 refuse` to fight the base's `/16 allow` on load order) was checked against Unbound's docs too and dropped — the manpage doesn't define a tie-break for two *equally* specific entries, so that wasn't a foundation to rely on for a security boundary either, especially after already getting this wrong once from assumption rather than verification.

Fixed by refusing at `192.168.0.0/24` instead — genuinely more specific than the base's `/16`, so "most specific always wins, order doesn't matter" applies unambiguously, no reliance on any undocumented tie-break. Sieve's `/32 allow` is more specific still, so it continues to win over that refuse the same clean way. Also added same-prefix refuses for the base's other two broad allows (`172.16.0.0/12` — notably, this includes Docker's own default bridge-network ranges; `10.0.0.0/8`) as defense in depth, but flagged those honestly as best-effort only, since they rely on exactly the tie-break behavior just ruled out as a foundation for the /24 case — no device on this network actually lives in either range, so the realistic exposure there is narrow (would need code execution inside a container on silo itself, not "any device on the LAN"), but it's not verified the way the /24 fix now is.

**Confirmed working 2026-08-31, same day:** deployed and re-tested — `dig @192.168.0.12 example.com` from percolator (not sieve) came back `REFUSED`; the same command from sieve itself came back a normal `NOERROR` answer with real A records. Both halves of the access-control rule now proven on real hardware, third attempt being the one that actually held. Unbound is ready for sieve's Pi-hole to be pointed at it — see the "not done yet, deliberately" note in the first Unbound entry above for why that's still a separate step, not bundled into this fix.

## 2026-08-31 (cont.) — Homepage's real bug: `.env.local` never had an automated fill-in on silo; `setup-secrets.sh` added

Separately from Unbound, Homepage's first real bring-up failed too: `docker logs homepage` showed `Host validation failed for: 192.168.0.12:3000`, repeatedly — the exact host:port `HOMEPAGE_ALLOWED_HOSTS` was supposed to already permit. Root cause, once traced: `stacks/silo/.env.local` still had `SILO_LAN_IP=REPLACE_ME` — never actually filled in. `HOMEPAGE_ALLOWED_HOSTS: ${SILO_LAN_IP}:3000` in `homepage/docker-compose.yml` had therefore rendered as `REPLACE_ME:3000`, which obviously never matches a real request's Host header.

The deeper gap this exposed: unlike sieve, where `generate-secrets.sh` interactively prompts for `.env.local`'s `DOMAIN` (and every other value it can't randomly generate), silo's `.env.local` had no automated fill-in at all — the README's first-time-setup step just said "fill in by hand," which is an easy step to skip past without noticing, especially coming from sieve's more automated flow. User Penguin asked, correctly: why doesn't `decrypt-secrets.sh` handle this the way sieve's script did? It doesn't, because it was never designed to — `decrypt-secrets.sh` only ever touched the SOPS-encrypted per-app secrets, not the plain shared `.env.local`, which is a completely different file with a completely different (and, until now, entirely manual) workflow.

Added `stacks/silo/setup-secrets.sh` to close the gap: creates `.env.local` from `local.env.example` if missing, scans it for any `REPLACE_ME` value and prompts for each (generically — matches on the placeholder text itself, not a hardcoded list of variable names, same "don't hardcode provisioning facts" reasoning as `headscale-bootstrap.sh`'s CLI-args redesign) — then chains `./decrypt-secrets.sh` and `./render-configs.sh` after it, so first-time setup on silo is one command instead of a sequence to remember and get half-right. Also checks decrypted secrets for a lingering `REPLACE_ME` and warns if found, but deliberately doesn't try to fix that case itself — a secret's placeholder comes from a blank prompt on roastery's `generate-secrets.ps1`, and `secrets.env.local` gets fully regenerated from `secrets/silo/*.sops.yaml` on every decrypt, so a local edit would just get silently overwritten by the next `git pull` + decrypt. Silo's README updated to lead with this script.

Not yet done: recreating the Homepage container with the corrected `.env.local` and confirming the host-validation error is actually gone.

## 2026-08-31 (cont.) — `SIEVE_LAN_IP` de-hardcoded from `local.env.example` too

Caught by User Penguin right after `setup-secrets.sh` went in: `local.env.example` still baked `SIEVE_LAN_IP=192.168.0.10` straight in as a real value rather than prompting for it — same "no hardcoding" objection as the headscale-bootstrap.sh user list on 2026-08-30, applied here to a cross-node fact instead of a provisioning action. Fair catch: a value like this belongs confirmed at setup time, not silently trusted from whatever an example file happened to say, which could go stale without anyone noticing if sieve's address ever changed.

Changed `SIEVE_LAN_IP=192.168.0.10` to `SIEVE_LAN_IP=REPLACE_ME` in `local.env.example`. No change needed to `setup-secrets.sh` itself — its `REPLACE_ME` scan was already generic (matches the placeholder text, not a hardcoded list of variable names), so it now prompts for `SIEVE_LAN_IP` the same way it does `SILO_LAN_IP` and `DOMAIN`, for free. `TZ` is the only value left with a real, non-prompted default (`Asia/Kolkata`) — a household-wide constant already treated the same way on sieve's own `generate-secrets.sh`, not a cross-node or provisioning fact, so left as-is.

## 2026-09-01 — CrowdSec: architecture reconsidered mid-research, moved entirely to sieve

Started CrowdSec per the Section 18.3 order (next after Homepage). Asked how to bridge the fact that CrowdSec's own natural home per the initiation doc's node-role table is silo, but the things worth watching (Traefik access logs, SSH auth attempts) are on sieve — User Penguin chose the split option offered: LAPI + decision engine on silo, lightweight agent + firewall bouncer on sieve, forwarding to silo's LAPI.

Research into the split's actual mechanics (deliberately done before writing any files — same discipline as Unbound's two failed access-control attempts, extended here to "verify before building" rather than "verify after it breaks") turned up two genuinely unconfirmed pieces, both fetch-resistant (several docs.crowdsec.net pages are JS-rendered SPAs that WebFetch's markdown conversion can't read at all — returned only nav/footer text, not content, across multiple attempts and multiple URL variants):

- Whether `AGENT_USERNAME`/`AGENT_PASSWORD` env vars are sufficient for a remote agent to auto-register against a remote LAPI, or whether the official multi-server docs' manual `cscli lapi register` + `cscli machines validate` two-step is still required across the two nodes.
- How the firewall bouncer actually gets deployed at all — every version-specific fetch attempt failed outright (404s on both `crowdsecurity/crowdsec` and `crowdsecurity/cs-firewall-bouncer` GitHub raw README paths, a 403 on the GitHub API tree listing, a 403 on a third-party guide, a Discourse thread fetch with no substantive content).

Mid-research, User Penguin asked directly: "should we move entire crowdsec over to sieve then?" — reconsidering the split before any file existed to unwind. Answered with the honest tradeoff rather than defaulting back to the original recommendation: the split's real benefit (decision engine survives a sieve compromise) is genuine but narrow, since silo has zero public exposure — nothing on it is routed through Traefik or a public hostname, so sieve is the only node CrowdSec has anything to watch on today. Every open unknown in the research so far was a direct consequence of the deployment being cross-node; a same-node agent/bouncer needs none of it (agent talks to `localhost:8080`, no token, no manual validation step; no LAN-wide LAPI port to open). Recommended consolidating onto sieve, framed as reversible later (CrowdSec's own multiserver docs describe migrating an already-working local LAPI onto a second host, not a redesign) rather than a permanent abandonment of the node-role table. User Penguin agreed via AskUserQuestion: **consolidate on sieve.**

Resumed research with the now-simpler question — how does the firewall bouncer actually get deployed — and this time it resolved cleanly via a Discourse thread built specifically around that question plus a real deployment blog (oneuptime.com) with an actual worked example. Findings, cross-checked across both:

- **The firewall bouncer is a native host package, not a container.** It has to rewrite the host's own iptables/nftables rules; running it in Docker (`NET_ADMIN` capability, `network_mode: host`) is described by the CrowdSec community itself as viable-but-emerging, with a real reported gotcha (connection failures when sharing a Docker network with other services) — not the proven path. Every real deployment example found uses the native package. Went with native: `curl -s https://install.crowdsec.net | sudo sh` (crowdsec's own installer script, not a stale packagecloud repo — a Discourse thread on a Debian-13-specific "package not found" error confirmed the *current* official script resolves it; an outdated cached install method was the actual cause of that report, not a real Debian-13 incompatibility) then `apt install crowdsec-firewall-bouncer-iptables`.
- **Registration**: `cscli bouncers add <name>` run against the (Dockerized) LAPI generates an API key, written into `/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml` (`api_url`, `api_key`, `mode: iptables`) — confirmed via the oneuptime worked example. crowdsec never lets you read a bouncer's key back after creation, which shaped `crowdsec-bouncer-bootstrap.sh`'s idempotency: if the registration exists in crowdsec's DB but the local key file doesn't have a real value, the only recovery is delete-and-re-add, which the script does automatically rather than getting stuck.
- Package variant: went with `-iptables` over `-nftables` on the reasoning that Debian's `iptables` command is nft-backed by default since Debian 11 anyway (the bouncer just shells out to whatever `iptables` resolves to) — not independently verified against sieve's actual install, flagged honestly in the README's known-gaps section rather than presented as settled, same as the `/12`/`/8` Unbound refuses.

Collections chosen: `crowdsecurity/traefik`, `crowdsecurity/sshd`, `crowdsecurity/linux` — matching what's actually being watched (Traefik's HTTP traffic, SSH auth attempts) rather than pulling in unrelated ones. Traefik's `accessLog` had no JSON output configured at all before this — added it (`traefik/config/traefik.yml.template`, `format: json`, no status-code filter so pattern-based scenarios still see everything, not just 4xx/5xx) plus a new persistent volume (`/srv/data/traefik/logs`, same `/srv/data/<app>` convention as every other app's persistent state) that both the traefik and crowdsec containers mount — traefik writes, crowdsec reads read-only, no network coupling needed between the two since it's a shared file, not an API call. Confirmed the `crowdsecurity/traefik` parser's expected acquisition label (`labels: type: traefik`) against both the parser source on GitHub and a real deployment's acquis.yaml before writing `crowdsec/config/acquis.yaml.template`, rather than guessing from the collection name alone.

Deliberately did not build: an AppSec (WAF-style request inspection) component — scope stayed to log-based detection + firewall enforcement, matching the original ask; flagged as a possible later addition, not a current gap. Also did not touch the Traefik-plugin bouncer approach (`crowdsec-bouncer-traefik-plugin`, seen in the same research) — the firewall bouncer alone covers both HTTP-layer and SSH-layer enforcement at the OS level, which was the original intent ("firewall bouncer on sieve enforcing at the OS level"); a second, HTTP-specific bouncer would be redundant for what this deployment actually needs.

Image pinned to `crowdsecurity/crowdsec:v1.7.8` — checked against GitHub's own releases page (latest non-RC stable) and cross-verified the tag actually exists on Docker Hub (a real, previously-hit failure mode for this project generally: a version being the latest *release* doesn't guarantee a matching Docker Hub tag exists yet — checked this time rather than assuming after Unbound's tag research made that gap obvious).

One consequence of moving everything onto sieve, only noticed after the fact: it also eliminated the entire SOPS+age secrets question for CrowdSec. Nothing about the containerized crowdsec service itself needs a secret (all-in-one mode has no cross-node credential to configure), and the bouncer's API key is written directly to a host config file outside git by `crowdsec-bouncer-bootstrap.sh`, never touching the repo at all — so unlike every silo app, this one needed no `secrets.env.local`/SOPS scaffolding whatsoever. Not the reason consolidation was chosen, but a real simplification that fell out of it.

Not yet done: any of this has been run for real. Needs, in order: `docker exec`-based confirmation that `/var/log/auth.log` is actually where sieve's sshd writes (flagged as unverified in the README — a stripped-down journald-only install would need a different acquisition method, not yet built), bringing the `crowdsec` container up, confirming the collections load cleanly (`cscli metrics` / `cscli hub list`), then `crowdsec-bouncer-bootstrap.sh` for the enforcement half, then the README's own suggested safe self-test (`cscli decisions add --ip <TEST-NET address>`) before trusting it with anything real — same "prove it before relying on it" discipline the Unbound access-control fix established. The remote-unban-method backlog item (Telegram bot vs. Nextcloud Talk bot, still undecided) is unrelated to any of the above and remains open.

## 2026-09-01 (cont.) — First real bring-up: LAPI port collided with Pi-hole's

`./compose.sh crowdsec up -d` failed outright: `failed to bind host port 127.0.0.1:8080/tcp: address already in use`. Root cause, once checked rather than assumed: Pi-hole already owns host port 8080 (`pihole/docker-compose.yml`, `network_mode: host` — moved there back on 2026-08-29 specifically to stay off Traefik's 80/443, see the README's "Pi-hole's admin UI" section). crowdsec's compose file had published its LAPI to `127.0.0.1:8080` without checking what else on sieve already sat on that port — a real gap in the pre-delivery review, not something research could have caught (it's a fact about this specific host's existing port usage, not about crowdsec itself).

Fixed by moving the host-side publish to `127.0.0.1:8090` (crowdsec's own internal/container-side port is untouched, still 8080 — only where it lands on the host changed). Updated in three places: `crowdsec/docker-compose.yml`'s `ports:` mapping, `crowdsec-bouncer-bootstrap.sh`'s written `api_url` (both the header comment and the actual config it writes to `/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml`). Checked for other host-port collisions across the rest of sieve's stack while at it (Homepage's 3000, lldap's 17170, Traefik's 80/443) — none conflict with 8090.

Not yet done: re-running `./compose.sh crowdsec up -d` with the fix, and everything downstream of it (auth.log check, collections, bouncer bring-up, self-test) — same list as the previous entry, unchanged except now blocked on this fix landing first.

Added a standing "Ports in use on this host" table to both `stacks/sieve/README.md` and `stacks/silo/README.md`, per User Penguin's request — this exact class of bug (a port collision only discovered at `docker compose up` time) has no reason to recur now that there's one place to scan before publishing a new port in any app's compose file. Table covers every host-bound port on each node, including the two kinds that share the same host port space without looking like they would: `network_mode: host` apps (Pi-hole — no `ports:` list of its own, whatever it binds lands directly on the host) and normal Docker-published ports (Traefik/lldap/crowdsec) both draw from the same space and now sit in the same table rather than being easy to reason about only within their own app's file. Deliberately excluded ports that never reach the host at all (authelia, headscale — routed only through Traefik over the internal `sieve_proxy` network) but noted them for contrast, so the table doesn't look incomplete to someone checking it. sieve and silo get separate tables since they're separate hosts with no shared port space — no reason to conflate them.

## 2026-09-01 (cont.) — crowdsec + firewall bouncer: first real bring-up, clean end to end

With the 8090 port fix pulled, `./compose.sh crowdsec up -d` came up clean on the first try — no repeat of Unbound's multi-attempt pattern this time, since the port fix was the only thing actually wrong.

`crowdsec-bouncer-bootstrap.sh` ran exactly as designed, including the parts that were hardest to verify from research alone: the install script correctly detected `debian/13` (trixie) and pulled `crowdsec-firewall-bouncer-iptables` (v0.0.36) from crowdsec's own packagecloud repo without incident — confirms the Discourse thread's claim from research (that the *current* install script resolves the Debian-13 "package not found" reports some users hit with a stale one) held up on the actual node, not just in theory. The package's postinstall script behaved exactly as flagged in the script's header comment: it detected no native crowdsec/cscli on the host and printed "cscli/crowdsec is not present, please set the API key manually" / "no api key was generated" — expected, harmless, and exactly why `crowdsec-bouncer-bootstrap.sh` does real registration itself afterward rather than relying on the package's own auto-registration.

`cscli bouncers list` confirms it end to end: `sieve-firewall-bouncer`, valid, connected, a real recent `Last API pull` timestamp. One detail worth recording so it doesn't look like a bug later: the bouncer's IP shows as `172.19.0.1` (crowdsec's own docker bridge gateway address), not `127.0.0.1` — normal and expected, since the connection arrives at the container through Docker's published-port path (`127.0.0.1:8090` on the host forwards in via the bridge), which always presents as the bridge gateway from the container's own point of view, not the literal loopback address the bouncer dialed.

Not yet done: the two verification steps the README calls out before trusting this with anything — confirming `/var/log/auth.log` is actually where sieve's sshd writes (still unverified), and the safe self-test with a TEST-NET address (`cscli decisions add --ip 198.51.100.1 --duration 1m --reason test`, confirming both that traffic claiming that source actually gets dropped and that the decision expires on its own). Both are User Penguin's to run next.

## 2026-09-01 (cont.) — Self-test instruction corrected: "confirm traffic gets dropped" wasn't actually testable

User Penguin ran the self-test's first half cleanly (`cscli decisions add --ip 198.51.100.1 ...` — decision created, 59s expiration, as expected). The second half of the instruction as originally written — "confirm sieve actually drops traffic that would claim to be from it" — was wrong to give: there's no way to make real traffic claim a source of 198.51.100.1 without IP-spoofing tools, which isn't something to reach for just to test a firewall rule. Caught this only after the fact, re-reading the instruction rather than assuming it was actionable because it had sounded reasonable when written.

Corrected the README's self-test to check the thing that's actually verifiable and actually matters: whether the bouncer pulled the decision from LAPI and applied it to sieve's real enforcement state (`ipset list`, `iptables -L -n -v`, grepping for the test IP and a crowdsec-referencing rule), not whether traffic can be faked. LAPI holding a decision and the bouncer enforcing it are two different things — the ipset/iptables check is the one that actually distinguishes "crowdsec decided" from "sieve enforces," which is the real thing this self-test needs to prove before anything relies on it. Also added the matching post-expiry check (decision gone from both `cscli decisions list` and the ipset) rather than just the pre-expiry one.

Not yet done: User Penguin re-running the corrected verification.

## 2026-09-01 (cont.) — NetAlertX: next in Section 18.3's silo order

CrowdSec's self-test still pending on User Penguin's side; moved on to the next container per Section 18.3's own order — NetAlertX (LAN device discovery/presence alerting), no dependency on anything already built.

**Image moved namespaces**: `jokobsk/netalertx` (the name most guides still reference) has moved to `ghcr.io/netalertx/netalertx` — checked before pinning, not assumed from an older guide. Pinned to `26.8.5`, cross-verified as an actually-published GHCR tag (not just a GitHub release) the same way crowdsec's tag was double-checked against Docker Hub — a real gap this project already knows to check for.

**Networking: host mode, but for a different reason than Pi-hole's.** NetAlertX does passive discovery (ARP/NBNS/mDNS) and active LAN scanning, both of which NetAlertX's own troubleshooting docs say bridge networking blocks outright — confirmed via docs before choosing this, not assumed by analogy to Pi-hole. `cap_add: NET_ADMIN, NET_RAW, NET_BIND_SERVICE` alongside it, per the same docs — capabilities are orthogonal to network mode, host networking alone doesn't grant them.

**The real gotcha, caught via research before it could bite here too**: host networking alone does not make NetAlertX scan anything. A real GitHub discussion (jokob-sk/NetAlertX#770) hit exactly this — host mode configured correctly, scan subnet set, but the *interface* parameter was wrong, and the result wasn't an error, it was a healthy-looking container that silently found nothing but the gateway and itself. Same failure shape as Homepage's `Host validation failed` and Unbound's original open-resolver bug: works, looks fine, is actually wrong. Fixed the same way those were — verify, don't assume. `SCAN_SUBNETS` needs both a subnet in CIDR notation *and* an explicit `--interface=<name>` — neither is guessable correctly from this session (silo's actual NIC name isn't known here), so both `SILO_LAN_INTERFACE` and `SILO_LAN_SUBNET` went into `local.env.example` as `REPLACE_ME` (same "no hardcoding a provisioning fact" principle as `SIEVE_LAN_IP`), picked up automatically by `setup-secrets.sh`'s existing generic scan. README's netalertx section tells User Penguin how to find the real interface name and explicitly says to verify the device count looks real, not just that the container started clean.

**Config mechanism, not obvious from the env var names alone**: `SCAN_SUBNETS` isn't a plain top-level env var like `PORT`/`GRAPHQL_PORT` — it has to go through an `APP_CONF_OVERRIDE` JSON blob, whose value is itself a string that *looks* like a Python list literal (single-quoted, nested inside double-quoted JSON). Reproduced exactly per NetAlertX's own docs example rather than simplified — tested the YAML quoting by parsing it with `yaml.safe_load` before committing to it, confirming it decodes to the exact JSON string needed with the `${SILO_LAN_SUBNET}`/`${SILO_LAN_INTERFACE}` placeholders still intact for docker compose's own variable interpolation to fill in at `up` time (docker compose interpolates `${VAR}` in the final string value regardless of how it was quoted in the YAML source — checked this held rather than assumed it would).

**Timezone handled differently from every other app in this repo**: NetAlertX's own docs use a `/etc/localtime:/etc/localtime:ro` bind mount, not a `TZ` env var — kept as documented rather than forced into the repo's usual `${TZ}` pattern, flagged with a comment in the compose file so it doesn't look like an oversight later.

Also added netalertx's two host ports (20211 web UI, 20212 GraphQL API — both `network_mode: host`, same category as Pi-hole's ports on sieve) to the "Ports in use" table added earlier today, and flagged honestly that opening 20212 to the whole LAN (not just 20211) is an assumption (that the browser calls GraphQL directly) rather than something confirmed from NetAlertX's actual traffic — narrow it to loopback if that turns out wrong.

Not yet done: any of this run for real. Needs, in order: finding silo's actual interface name and filling in `.env.local`, the two ufw rules, `./compose.sh netalertx up -d`, then genuinely checking the device count looks real (not just that the container started) before trusting it — same discipline as everything else this build.

## 2026-09-01 (cont.) — `purrbrews-commit.ps1` bug: embedded quotes in a model-generated commit message broke `git commit`

User Penguin ran the commit helper on the NetAlertX/ports-table changes and hit `error: pathspec 'in' did not match any file(s)` repeated across several stray words. Root cause, read directly off the actual script (staged from roastery via the device bridge and read, rather than guessed from the error alone — this script predates this session and wasn't something already in front of me): line 240 was `git commit -m "$commitMsg"`. PowerShell has a known quirk where it doesn't re-escape an embedded `"` when constructing the command line handed to a native executable. The model's generated message that triggered this contained a literal quoted phrase (`Add "Ports in use on this host" table...`) — the embedded `"` closed the `-m` value early as far as git.exe's own argv parsing was concerned, and every word after it (`Ports`, `in`, `use`, `on`, `this`, `host...`) became a separate bare argument, which git treated as pathspecs since they came after a complete `-m <message>`. The backticks around the filenames weren't actually the cause (they're already literal characters by the time PowerShell hands the expanded string to git) — the double quotes were.

Fixed at the root rather than patched around: replaced the direct `-m "$commitMsg"` call with writing the message to a temp file (UTF-8, no BOM — `[System.IO.File]::WriteAllText` rather than `Out-File`, which adds a BOM on Windows PowerShell) and `git commit -F <file>`, which git reads byte-for-byte regardless of what characters are in it — immune to this whole class of bug, not just today's specific trigger. Also tightened the Ollama prompt to tell the model not to use backticks/quotes at all, since a commit subject line with markdown-style emphasis in it isn't good style even once the crash itself is fixed — belt-and-suspenders, not the actual fix.

Nothing was lost — `git add -A` had already completed before the commit step failed; User Penguin committed manually to unblock, and the corrected script is delivered for next time.

## 2026-09-01 (cont.) — NetAlertX had no secrets audit at all; caught by User Penguin asking, not by me

User Penguin asked directly whether the netalertx build included all its secrets. It didn't — worse, it hadn't been checked at all. Every other app in this build got a real secrets pass (Homepage's `HOMEPAGE_ALLOWED_HOSTS`, Pi-hole's password decision, CrowdSec's bouncer key); NetAlertX only got researched for its `SCAN_SUBNETS` gotcha, and I moved straight to writing the compose file without asking "does this app have a login, and is it on by default." That's a real process gap, not just a missed detail — worth naming plainly rather than folding into the fix itself.

Checked properly this time: NetAlertX does **not** require login by default (`docs.netalertx.com/SECURITY/`, confirmed by direct quote — "By default, NetAlertX does not require login"). Worse than a merely-open dashboard: it has real, serious CVE history — CVE-2024-46506 (unauthenticated RCE) and its bypass, CVE-2025-32440 (CVSS 10.0, auth bypass via an alternate unauthenticated entry point, `/index.php` directly rather than the path the auth check actually covered). Both are fixed well before the pinned `26.8.5` tag, so the specific known exploits don't apply — but the pattern (an app in this exact category having had multiple unauthenticated entry points before) made "leave it open since the LAN is trusted" the wrong call, same reasoning that's kept Pi-hole's admin UI gated behind Authelia rather than just relying on LAN-only reachability.

Enabled it: `SETPWD_enable_password=true` / `SETPWD_password=<value>`, per NetAlertX's own docs — value sourced from a new `NETALERTX_PASSWORD` secret, added to `generate-secrets.ps1` following the exact same pattern as every other silo secret (randomly generated via `New-RandomSecret`, not prompted — same category as sieve's `PIHOLE_WEBPASSWORD`, a credential this project sets rather than one that has to match an external account). 16 bytes rather than the usual 32, mirroring `PIHOLE_WEBPASSWORD`'s own shorter length — a password a human might actually type into a login form occasionally, not a pure machine-to-machine token. Flagged honestly in the README: whether `SETPWD_password` takes plaintext (hashed internally, per how the docs' example reads) or a pre-computed hash isn't independently confirmed against the source — first login is the real test.

Also reconciled the whole compose file against NetAlertX's own `docs.netalertx.com/DOCKER_COMPOSE/` "baseline" reference, found while chasing down the auth question — meaningfully more hardened than the repository's own example `docker-compose.yml` this was originally built from: `read_only: true` with `cap_drop: ALL` and an explicit `cap_add` allowlist (rather than just adding capabilities on top of full privilege), ARP-accuracy sysctls, and a locked-down `tmpfs` mount (`noexec,nosuid,nodev`). Adopted all of it except the volume type — kept a `/srv/data/netalertx` bind mount instead of the docs' named Docker volume, for consistency with every other app's `/srv/data/<app>` convention in this fleet; nothing about NetAlertX's own behavior requires one over the other, it's a plain Compose choice.

Narrowed the GraphQL port (20212) exposure while at it: originally planned as a second LAN-wide ufw rule alongside the web UI's 20211, on the unverified assumption the browser calls it directly. Given the CVE history just surfaced, "open it because it might be needed" is the wrong default now — it's bound on the host (host networking) but gets no ufw rule unless the UI actually turns out broken without one, which is verifiable empirically (browser network tab) rather than guessed.

Not yet done: any of this run for real — `generate-secrets.ps1` needs to actually run on roastery to produce `secrets/silo/netalertx.sops.yaml`, then the usual commit/push/pull/`setup-secrets.sh` chain, then first bring-up and login. Worth naming the broader lesson for whatever's built next (Speedtest Tracker, Komodo, Scrutiny, Diun): check for a login/auth mechanism and its default state as a standing first step in each app's research, not an afterthought only caught because it was asked about directly.

## 2026-09-01 (cont.) — Speedtest Tracker, Scrutiny, Diun, Komodo: the rest of Section 18.3, plus scaffolding for percolator/cellar/mochaPot/ristretto

User Penguin's request ("prepare the entire stack for remaining containers of silo, so that we are prepared for percolator, cellar and mochaPot and at last ristretto") read as two distinct pieces of work, kept deliberately separate: finish silo's own remaining apps, and prepare generic groundwork for the four nodes after it — not fabricate app lists for nodes whose actual specs aren't in this session's context. Researched all four remaining silo apps in parallel via sub-agents (mirroring this build's own research discipline: verify actual registry tags rather than trust release notes, check auth/login default state as a first step per the NetAlertX lesson above, check CVEs, cite sources), then verified Komodo's most security-sensitive details myself directly against its official GitHub source rather than trusting a summarized version, given it ends up with Docker socket access across the whole fleet.

**Speedtest Tracker.** The image most guides reference (`ghcr.io/alexjustesen/speedtest-tracker`) is abandoned, stuck at v0.19.0 — moved to LinuxServer's actively maintained `lscr.io/linuxserver/speedtest-tracker:v1.15.0-ls170`, caught before pinning rather than after. Ships with a fixed default admin account (`admin@example.com` / `password`) unless `ADMIN_NAME`/`ADMIN_EMAIL`/`ADMIN_PASSWORD` are set at first boot — same "don't ship a known default credential" call as netalertx, this time confirmed as a documented default rather than an absence of auth. `APP_KEY` (a Laravel encryption key, `base64:<32 random bytes>`) is required — the app doesn't run correctly without one, no insecure default to fall back on, generated fresh via `New-RandomSecret 32` with the `base64:` prefix added explicitly since that's the exact format Laravel expects, not just any base64 string. `SPEEDTEST_SCHEDULE` (cron syntax) has to be set explicitly or no speed test ever runs automatically — confirmed via multiple real GitHub issues reporting exactly this with no error surfaced anywhere, set to hourly (`0 * * * *`). `PUBLIC_DASHBOARD` defaults to `false` (secure) — left untouched rather than opened, since nothing about this build needs a public-facing dashboard.

**Scrutiny.** `ghcr.io/analogj/scrutiny:v0.9.3-omnibus`, the single all-in-one image (collector + web UI + influxdb in one container) — sufficient for one node, and the project's own README specifically warns against floating `latest-` tags, so pinned to the same real release tag discipline as everything else here. **Has no authentication of any kind** — checked and confirmed as a genuine, undocumented absence (not a stated design choice, and no CVEs turn up either, just nothing to log into). Flagged plainly in the Known Gaps section rather than worked around, since there's no SETPWD-style knob to reach for the way there was for NetAlertX — Scrutiny simply doesn't have one; if this needs to be closed off, it'd mean fronting it with something else entirely (Authelia forward-auth, or just not exposing it beyond loopback), not attempted here since it wasn't asked for. Needs `cap_add: SYS_RAWIO, SYS_ADMIN` (the latter specifically for NVMe SMART data) and a `/run/udev:ro` mount, both per the project's own docs. **The one genuinely unfinishable part of this build without hands-on-hardware access**: per-disk `--device`/`devices:` entries can't be auto-filled — `docker-compose.yml` files in this repo aren't run through `render-configs.sh`'s envsubst (only `*.template` files under `config/` are), so this is a real required manual edit before first bring-up, using `lsblk -d -o NAME,TYPE,SIZE,MODEL` or `smartctl --scan` on silo itself to find the actual device paths — left as an explicit `REPLACE_ME_disk1` placeholder in the compose file with the exact commands to run in a comment right above it, rather than guessing a device name (`/dev/sda` etc.) that could easily be wrong on real hardware. Also caught, before it could become a repeat of the CrowdSec/Pi-hole incident: Scrutiny's documented default web port (8080) collides with Speedtest Tracker's, both being built in the same batch — moved Scrutiny's host-side publish to 8081 (container-internal port unchanged) before either was ever brought up, the first time this project's own "check the ports table before publishing a new one" discipline (added to the README specifically because of the CrowdSec collision) caught something proactively instead of after a failed `docker compose up`.

**Diun.** `crazymax/diun:4.33.0` — pure outbound image-update watcher, no web UI or API surface at all, so the auth question this build now checks for every app simply doesn't apply here; noted explicitly in the README rather than silently skipped, so it doesn't look like an oversight later. Docker socket access routed through a `tecnativa/docker-socket-proxy:0.4.2` sidecar (pinned against the project's own GitHub releases page after Docker Hub's tag listing looked inconsistent — cross-checked rather than trusted at face value) with only `CONTAINERS=1`/`IMAGES=1` enabled and `POST=0` explicit — least-privilege, since a plain `:ro` bind mount of the raw socket does not actually restrict which Docker API verbs are reachable over it, only that the mount itself can't be written to. `DIUN_PROVIDERS_DOCKER_WATCHBYDEFAULT` set to `"true"`, a deliberate deviation from the image's own default (`false`) — chosen so newly added containers get watched automatically without needing a `diun.enable=true` label remembered on every future app, accepting possible notification noise as the trade-off rather than silent gaps in coverage. `/data` volume is required, not optional — without it surviving a restart, Diun has no memory of what it already reported and re-notifies on every already-known image every time the container restarts. One real, unresolved upstream issue found and flagged rather than hidden: at least one report of Diun failing to reach a socket-proxy sidecar over this exact `tcp://<name>:2375` pattern, left open in the proxy's own tracker — documented fallback (drop the sidecar, mount the raw `:ro` socket directly, less safe but simpler) is in the compose file's own comment and the README, ready to use if `docker logs diun` shows a connection failure after bring-up. Notification provider (Telegram/ntfy/webhook/etc.) deliberately left unconfigured — a genuine open decision, not a gap, cross-referenced with the still-undecided CrowdSec remote-unban-notification backlog item as a possible shared channel later.

**Komodo.** The most involved of the four, proportional to what it actually holds. `ghcr.io/moghtech/komodo-core:2.3.2` + `ghcr.io/moghtech/komodo-periphery:2.3.2`, pinned explicitly rather than the official template's own floating `:2` tag — deliberate, given how central this is meant to become to managing the rest of the fleet, a silent minor/patch bump on redeploy is worth avoiding even at the cost of manual version bumps later. Verified directly against Komodo's actual official source files on GitHub (`compose/mongo.compose.yaml`, `compose/compose.env`) rather than trusting a summarized version, given the stakes — first two fetch attempts came back as prose summaries instead of literal file content and had to be re-fetched with an explicit "output the whole file verbatim in a code fence" instruction before the real content came through. Requires MongoDB (`mongo:7.0`) — **real preflight requirement, not yet verified on silo's actual hardware**: MongoDB 5.0+ needs CPU AVX support and crashes outright (`Illegal instruction`) without it, a genuine and common failure mode on older hardware or a misconfigured Proxmox/KVM CPU model. Called out prominently at the top of the compose file and in the README rather than buried — check `grep avx /proc/cpuinfo` on silo before running this, first thing. Architecture-wise, Komodo v2 has Periphery open a persistent outbound WebSocket to Core (confirmed against the v2.0.0 release notes, not assumed from older v1 documentation still floating around) — meaning a managed remote node needs no inbound firewall port for Komodo, only outbound reachability to silo:9120, which shapes how the future-node Periphery template below is meant to be used. Every credential the official reference file ships as an insecure placeholder (`admin`/`admin` database credentials, `a_random_secret`, `a_random_jwt_secret`, `changeme`) was replaced with a real generated value in `generate-secrets.ps1` — five secrets total, the most of any silo app so far, proportional to what's actually at risk: root-equivalent access, via Periphery's Docker socket mount, to every node it manages, not just silo itself. `PERIPHERY_ROOT_DIRECTORY` kept at its documented default (`/etc/komodo`) rather than moved under this fleet's usual `/srv/data/<app>` convention, because the maintainers document directly (moghtech/komodo#180) that this path must be identical inside and outside the container or Docker "gets confused" — a real constraint, not a style choice, so the usual convention was set aside deliberately rather than silently violated by accident later. Flagged repeatedly, not just once: whoever controls Komodo Core's web UI or its JWT/webhook secrets effectively has root on every node running a Periphery agent — these credentials need the same handling discipline as a root SSH key, not just "another app password."

**Komodo Periphery template for future nodes** (`stacks/_templates/komodo-periphery/docker-compose.yml`), added alongside Komodo itself since the whole point of building Komodo now is to eventually manage percolator/cellar/mochaPot/ristretto too. Not a live app — a copy-and-fill template with `REPLACE_ME` placeholders for the values that differ per future node (`TZ`, `PERIPHERY_CONNECT_AS`, `PERIPHERY_ONBOARDING_KEY`, silo's LAN IP), plus setup instructions in its own header comment: get an onboarding key from silo's Komodo UI once that node exists, confirm outbound reachability to silo:9120, add a ufw rule on silo for that node's LAN IP if nothing broader already covers it. Carries the same root-equivalent-access caveat as silo's own Periphery service, since it grants the identical thing on whatever node it eventually runs on.

**Ports table and README** (`stacks/silo/README.md`) updated for all four new apps: 8080/8443 (speedtest-tracker), 8081 (scrutiny, moved off its 8080 default to avoid the collision above), 9120 (komodo-core) — noting that InfluxDB (8086, inside the scrutiny container) and diun's socket-proxy are intentionally never published to the host. Four new Known Gaps entries added: speedtest-tracker's PUID/PGID not yet reconciled with this fleet's usual permissions handling, scrutiny's total lack of auth plus its `SYS_ADMIN` capability, diun's proxy-pin uncertainty and the still-undecided notification channel, and komodo's unverified AVX requirement plus `PERIPHERY_DISABLE_CONTAINER_TERMINALS` left at its (enabled) default rather than explicitly reasoned about.

**Scaffolding for percolator, cellar, mochaPot, ristretto** — explicitly scoped to generic, reusable tooling only, since none of these four nodes' actual app lists are known in this session (not fabricated; each node's `README.md` stub says so and points back to the initiation doc). Created `stacks/{percolator,cellar,mochaPot,ristretto}/`, each populated with: `compose.sh` and `render-configs.sh` copied verbatim from silo (confirmed to have nothing silo-specific in their logic, only historical lineage comments); `.gitignore` copied verbatim (same generic three rules — `.env.local`, `*/secrets.env.local`, rendered `*/config/*` except tracked `.template`s); `decrypt-secrets.sh` and `setup-secrets.sh` copied from silo with their silo-specific paths and prose genericized to each node's own name (`SECRETS_SRC` repointed at `secrets/<node>`, echo/log text updated to match); a new `generate-secrets.ps1` per node, same mechanics as silo's own copy, but with an empty per-app secrets section (a comment explaining nothing's built yet, not a placeholder app) since no real apps exist on any of these four nodes yet; a minimal `local.env.example` (just `<NODE>_LAN_IP`, `TZ`, `DOMAIN` — silo's own grew its `SIEVE_LAN_IP`/`SCAN_SUBNETS`-related entries only once the apps that needed them were actually built, and these four should grow the same way, not be pre-populated with guesses); and a `README.md` stub that says plainly what is and isn't here yet, with an explicit caveat that the inferred deploy order (percolator → cellar → mochaPot → ristretto, taken from the order they were listed in the request that triggered this) has not been checked against the initiation doc's own ordering. All four nodes' shell scripts passed `bash -n`; all four `generate-secrets.ps1` copies passed a brace/paren/bracket balance check.

**Real gap caught while scaffolding, before it shipped**: initially assumed a root-level `.gitignore` covered `*.env.local`/`secrets.env.local` fleet-wide, meaning per-node `.gitignore` files wouldn't be needed for the four new stubs. Checked rather than assumed — there is no root-level `.gitignore` in this repo at all; sieve and silo each carry their own. Corrected before delivery: each of the four new node directories gets its own `.gitignore`, identical to silo's, so a future secret or rendered config in any of them doesn't end up committed by default the moment an app is actually added.

Not yet done, and worth being explicit about: none of Speedtest Tracker, Scrutiny, Diun, or Komodo have been brought up on silo yet — `generate-secrets.ps1` needs to run on roastery first to produce the four new `secrets/silo/*.sops.yaml` files, then the usual commit/push/pull/`setup-secrets.sh` chain, then Scrutiny's disk device paths need filling in by hand, then Komodo's AVX check needs running on silo's real CPU before its first `up -d`. None of the four future-node directories have been run against a real host either — they're untested scaffolding copied from a working silo setup, not yet exercised.

## 2026-09-02 — First real bring-up attempt: Diun's socket-proxy tag was wrong ("v" prefix missing)

User Penguin started bringing up silo's remaining containers, beginning with Diun since it needs no secrets and no manual edits. First attempt: `sudo ./compose.sh diun up -d` failed immediately — `failed to resolve reference "docker.io/tecnativa/docker-socket-proxy:0.4.2": docker.io/tecnativa/docker-socket-proxy:0.4.2: not found`. Diun's own image (`crazymax/diun:4.33.0`) never actually got a chance to fail or succeed — its pull was interrupted because `depends_on` had it waiting on the socket-proxy image, which failed first.

Root cause, checked directly against Docker Hub's registry API rather than a summarized page fetch this time (`hub.docker.com/v2/repositories/tecnativa/docker-socket-proxy/tags/<tag>` for each candidate tag): the pinned tag was missing a "v" prefix. This project's own tagging is genuinely inconsistent — `0.3`/`0.3.0` (older) have no "v", but every `0.4.x` and later tag does (`v0.4.0`, `v0.4.1`, `v0.4.2`, `v0.5.0`). The original 2026-09-01 build comment on this line said the Docker Hub listing "looked inconsistent... mixed in what looked like PR-build tags" and chose to trust the GitHub releases page instead — but GitHub's release *names* (`v0.4.2`) and the literal registry tag needed to actually pull it are the same string; dropping the "v" while transcribing it was the actual mistake, not a real inconsistency to route around. The API check this time confirms it plainly: `v0.4.2` returns a real multi-arch manifest, bare `0.4.2` 404s.

Fixed by moving to `v0.5.0` rather than just re-adding the "v" to `0.4.2` — `v0.5.0` is the actual current stable as of this fix (pushed 2026-07-27, also carries the image's own `latest` tag), and its release notes are additive only (a `BIND_CONFIG` environment override, container pause/resume support, an HAProxy version bump) — confirmed against the project's current README that `CONTAINERS`/`IMAGES`/`POST` (the three env vars this compose file actually sets) are unchanged before assuming that held, rather than after. `crazymax/diun:4.33.0` itself was separately confirmed still valid via the same API-check method, so no change needed there.

Broader lesson worth naming: a WebFetch-summarized page (as opposed to hitting an API endpoint directly and reading the actual field) can smooth over exactly the kind of formatting detail — a one-character tag prefix — that determines whether a `docker compose up` succeeds or fails. Where a pin actually matters (anything about to be pulled and run), checking the registry's own API response for the exact tag string beats trusting a fetched page's paraphrase of it, even when that page fetch already felt like real verification at the time.

Not yet done: `./compose.sh diun up -d` re-run with the corrected tag. Still pending from before: `lsblk`/`grep avx` output from silo (unblocks Scrutiny and Komodo), and `generate-secrets.ps1` on roastery (unblocks Speedtest Tracker and Komodo).

## 2026-09-02 (cont.) — Scrutiny's disk path filled in, Komodo's AVX preflight confirmed clear

User Penguin ran both outstanding checks on silo. `lsblk -d -o NAME,TYPE,SIZE,MODEL`: one physical disk, `/dev/sda`, 931.5G, Seagate BarraCuda `ST1000LM035-1RK172` (a SATA HDD, not NVMe). `grep avx /proc/cpuinfo`: present on every core.

Filled `/dev/sda` into `scrutiny/docker-compose.yml`'s `devices:` list, replacing the `REPLACE_ME_disk1` placeholder — this file isn't run through `render-configs.sh`'s envsubst, so this had to be a direct manual edit, done on roastery per the "no live coding on fleet nodes" rule rather than editing it in place on silo. Left `SYS_ADMIN` in `cap_add` even though it's now confirmed unused (silo's one disk is SATA, not NVMe) — narrowing it would be more correct today but less useful if a second/NVMe disk shows up on this node later; noted the reasoning in both the compose file and the README rather than silently deciding either way.

Komodo's AVX gate is now closed — nothing about the compose file needs rethinking, it's clear to bring up. Removed the corresponding Known Gaps entry rather than leaving a stale "not yet checked" note in the README once it no longer applies; also updated the SYS_ADMIN and diun-tag Known Gaps entries that had gone stale from earlier fixes this session (the latter to reflect the `v0.4.2`→`v0.5.0` correction from the Diun bring-up attempt above, rather than still describing the pin as unverified).

Not yet done: `./compose.sh scrutiny up -d` with the real device path, and Komodo's own bring-up (still blocked on `generate-secrets.ps1` running on roastery — Komodo needs five real secrets that don't exist yet). Diun's corrected-tag re-run and Speedtest Tracker (also blocked on the same secrets step) are still pending too.

## 2026-09-02 (cont.) — generate-secrets.ps1 wouldn't parse at all: em-dashes + Windows PowerShell's codepage default

User Penguin's first run of `.\generate-secrets.ps1` on roastery failed immediately with a cascade of parser errors (`An expression was expected after '('`, `Missing closing ')'`, `The string is missing the terminator`, several `Missing closing '}'`) at lines 47, 61, 188, 79, 77, 40, 39 — all in a file that had already been confirmed syntactically valid earlier in this build. The pasted error text itself held the answer: every error line quoted back mangled text like `â€"` sitting exactly where this file has a real em-dash (`—`) in a comment.

Root cause, verified by reproducing it rather than assumed from the garbled text alone: the file itself is valid UTF-8 with no BOM (confirmed directly against the actual bytes on roastery, staged and checked). Windows PowerShell (almost certainly the in-box 5.1, not PowerShell 7 — `pwsh.exe` isn't a default install) reads a BOM-less `.ps1` file using the system ANSI codepage rather than UTF-8. Under a Latin-script Windows codepage (cp1252), the 3-byte UTF-8 sequence for `—` decodes as three separate wrong characters, one of which lands on a Unicode right-curly-quote (`”`, U+201D) — a character PowerShell's tokenizer treats as a smart-quote string delimiter. Reproduced this exactly: took the real file's raw bytes, decoded them as cp1252 (simulating what Windows PowerShell actually saw), fed that text through PowerShell's own parser (`[System.Management.Automation.Language.Parser]::ParseFile`), and got the identical error list at the identical line numbers as User Penguin's paste — not just a plausible-sounding theory, a byte-for-byte reproduction.

Scanned every `.ps1` file in this repo for the same exposure rather than fixing just the one that failed: `scripts/purrbrews-commit.ps1` has zero non-ASCII bytes (it already used plain `--` throughout, by whatever earlier convention, which is exactly why it never hit this), but all five `generate-secrets.ps1` copies (silo + the four future-node scaffolds, all templated from the same source) had 25 real em-dashes each (silo) or a handful fewer (the future-node copies, minus silo's per-app comments). Fixed all five the same way `purrbrews-commit.ps1` already was, by accident or design: replaced every `—` with `--`. Confirmed nothing else non-ASCII was hiding in there (Python character-frequency scan — em-dash was the only offender, no smart quotes, no en-dashes). Verified the fix two ways: the real parser now accepts all five files cleanly, and re-running the exact cp1252-misread simulation against the fixed silo file also comes back clean — the fix holds regardless of which codepage actually reads it, so this isn't dependent on the user always having a BOM survive git/editor round-trips (a BOM-based fix would have been more fragile long-term than just not having non-ASCII characters in a `.ps1` file at all).

Broader lesson for anything still to be written as `.ps1`: no real em-dashes, en-dashes, or smart quotes — plain ASCII (`--` for em-dash) only. Markdown/YAML/bash files don't have this failure mode (nothing about how git, bash, or a Markdown renderer reads a file depends on the Windows system codepage), so this is a `.ps1`-specific rule, not a fleet-wide one.

Not yet done: User Penguin re-running `.\generate-secrets.ps1` with the fixed file.

## 2026-09-02 (cont.) — generate-secrets.ps1: two more bugs, one caught by the user's error, one caught only by actually running it

### RandomNumberGenerator.Fill() doesn't exist on Windows PowerShell 5.1

User Penguin's next run got past parsing but failed immediately: `Method invocation failed because [System.Security.Cryptography.RandomNumberGenerator] does not contain a method named 'Fill'`. This confirms, along with the earlier em-dash/codepage issue, that roastery is running the in-box Windows PowerShell 5.1, not PowerShell 7 -- `RandomNumberGenerator.Fill(byte[])` is a static convenience method that only exists on .NET 5+/Core; 5.1 runs on .NET Framework, which never got it. Fixed by switching to `[RandomNumberGenerator]::Create()` + the instance `.GetBytes($buf)` method, which has existed since the earliest .NET Framework versions and still works identically on modern .NET -- this version doesn't care which PowerShell/.NET the script ends up running under. Verified the replacement actually produces correctly-random, correctly-sized output (32 and 16 byte cases, two calls differ) before shipping it, not just that it compiles. Applied to all five `generate-secrets.ps1` copies (silo + the four future-node scaffolds), since all five had the identical `::Fill()` call.

### A second, more serious bug found only by actually running the script -- multi-secret files were coming out corrupted

Given this was the third failure in a row on this one file, ran a full functional test this time instead of just a parse check: wrote stub `sops`/`age` executables and ran the real script against a throwaway repo, then actually inspected the output files rather than just checking the exit code. That caught something a syntax check never would have: `komodo.sops.yaml` (5 secrets) and `speedtest-tracker.sops.yaml` (2 secrets) came out as a single run-on line each -- `KOMODO_DATABASE_USERNAME: komodoKOMODO_DATABASE_PASSWORD: ...` with no separator between keys at all. `netalertx.sops.yaml` (1 secret) was fine, which is exactly the pattern that would have let this ship unnoticed if only netalertx-style single-secret apps had been tested.

Root cause, isolated with a standalone repro before touching the real file: `$existingLines = $raw -split "\`r?\`n" | Where-Object {...}` -- when the file being re-read has exactly one existing line, PowerShell's pipeline silently collapses the one-element result down to a bare scalar STRING instead of a one-element array. A few lines later, `$existingLines + "${Key}: ${Value}"` then hits PowerShell's type-dependent `+` operator: array-append if the left side is an array, but plain STRING CONCATENATION (no separator inserted) if it's a scalar string -- which is exactly what a one-line file produces on its second write. This only bites starting on the *second* secret written to any given file (the very first call always sees the explicitly-initialized `$existingLines = @()`, a true empty array), which is why netalertx.sops.yaml (one secret, one call, ever) never showed the bug and why it was invisible in every syntax/parse check so far.

Fixed by wrapping the whole pipeline in `@(...)` -- `@($raw -split "\`r?\`n" | Where-Object {...})` -- which forces a real array regardless of how many elements come out the other end (0, 1, or many), so the append below is always array-append. Verified properly this time: reproduced the corruption in isolation first (a minimal 5-call repro matching Komodo's real shape), confirmed the fix resolves it in that isolation, then ran the actual fixed `stacks/silo/generate-secrets.ps1` end-to-end against stub `sops`/`age` and checked every resulting file both as raw bytes (`cat -A`, to see real newlines vs none) and by actually parsing each as YAML and confirming the right number of keys came out. Also re-ran the whole script a second time afterward to confirm idempotency still holds (no `set` lines printed, file unchanged) -- the two fixes together didn't quietly break the "never touch an existing value" guarantee this script depends on. Applied to all five `generate-secrets.ps1` copies.

Broader lesson, worth being honest about: this file passed a syntax check and even ran without throwing an error on penguin's very first successful pass -- it would have silently written corrupted secrets for any app needing 2+ values (speedtest-tracker, komodo, and by extension anything similar on future nodes) with a "Done." message and no indication anything was wrong. A parse check proves a script will run; it doesn't prove a script does the right thing. For anything that writes files this project will actually rely on, the real test is running it against realistic inputs and inspecting what it produced -- which is now the standard this project holds itself to for `.ps1` scripts specifically, not just YAML/compose files.

Not yet done: User Penguin re-running `.\generate-secrets.ps1` for real, against real `sops`/`age`.

## 2026-09-02 (cont.) — .sops.yaml: path_regex never matched on Windows at all

With all three `generate-secrets.ps1` bugs fixed, User Penguin's next run got all the way to actually calling `sops -e -i` -- and hit a real `sops` error: `error loading config: no matching creation rules found`, on `secrets\silo\netalertx.sops.yaml`. Not a script bug this time -- `.sops.yaml`'s own `path_regex: secrets/.*\.sops\.yaml$` was written with a literal forward slash, and this repo's `.sops.yaml` has sat there since 2026-08-31 without ever actually being exercised on Windows until this exact run (silo's own `stacks/sieve/generate-secrets.sh` never touches SOPS at all, so nothing before this had a reason to notice).

Root cause: sops locates the governing `.sops.yaml` by walking up from the target file's directory, then matches `path_regex` against that file's path *relative to `.sops.yaml`'s own location*. On Windows, that relative path comes out backslash-separated (`secrets\silo\netalertx.sops.yaml`) -- and a bare `/` in a regex only ever matches a forward slash, so the pattern never had a chance of matching on this machine, regardless of anything about silo/netalertx specifically. Verified this is a real, still-open upstream issue rather than something specific to this repo's setup or a one-off misconfiguration -- github.com/getsops/sops/issues/892 and github.com/getsops/sops/issues/1650 both report the identical error for the identical reason. Also verified the fix directly against the actual regex engine sops itself uses (Go's RE2, via a small standalone Go program compiling both the old and new pattern and matching them against real Windows- and Linux-style relative paths) rather than trusting the GitHub issue's suggested fix on faith -- confirmed the old pattern fails on `secrets\silo\netalertx.sops.yaml` (reproducing the exact error) and the new one matches both that and `secrets/silo/netalertx.sops.yaml`.

Fixed with the community-confirmed workaround: `path_regex: secrets[/\\].*\.sops\.yaml$` -- a character class matching either separator in place of the bare `/`. This governs every node's `secrets/<node>/*.sops.yaml`, not just silo's, so percolator/cellar/mochaPot/ristretto are covered by the same fix whenever they get real secrets of their own; no per-node config needed since there's only ever this one `.sops.yaml` at the repo root.

Worth naming as its own category, distinct from the three `.ps1`-specific bugs above: this one wasn't about PowerShell version or encoding at all, it's `sops` itself behaving differently on Windows than on the Linux nodes it also runs on (silo, sieve) -- a genuine cross-platform tool inconsistency this project's roastery/fleet-node split was always going to eventually run into, now hit and fixed rather than theoretical.

Not yet done: User Penguin re-running `.\generate-secrets.ps1` for real, all four bugs now behind it.

## 2026-09-02 (cont.) — generate-secrets.ps1: "sops metadata not found" was a real PowerShell bug, not a sops problem

With `.sops.yaml` fixed, User Penguin's next run got past the config-matching step entirely and crashed differently: `sops.exe : sops metadata not found`, thrown as a terminating `NativeCommandError` at the `$raw = & sops -d $SopsFile 2>$null` line -- on `netalertx.sops.yaml`, the same file that had been a plaintext leftover from the em-dash-crash run several fixes ago (this script had never gotten far enough to overwrite it with real ciphertext until now).

The message itself is accurate -- that file genuinely isn't valid sops ciphertext, it's the leftover plaintext `NETALERTX_PASSWORD: REPLACE_ME`-shaped file from before this script could even parse. But the script was never supposed to let that be fatal: `Set-SopsSecretIfAbsent` already only calls `sops -d` inside an `if (Test-Path $SopsFile)` guard specifically so a missing-or-invalid file can fall through to "treat as empty and write fresh." What actually broke was `$ErrorActionPreference = "Stop"` (set at the top of this script, same as every other `.ps1` here) combined with a real, still-open, cross-version PowerShell bug -- github.com/PowerShell/PowerShell/issues/4002 -- where a *native* (non-PowerShell) command writing to stderr has each line wrapped into its own `ErrorRecord`, and `-Stop` treats that as script-terminating **regardless of stderr redirection**. `2>$null` looks like it should suppress this; it does not, because PowerShell decides whether to terminate before the redirect gets a say. Verified this precisely rather than trusting the GitHub issue's description alone: reproduced the identical crash locally with a stub "sops" that only ever writes to stderr and exits 1, under `2>$null` and `-ErrorActionPreference Stop`, on both a Windows PowerShell 5.1-equivalent and a PowerShell Core 6 host -- confirms this isn't specific to whichever PowerShell version roastery runs, and confirms `$LASTEXITCODE` still comes through correctly either way (it's only the stderr-as-terminating-error part that's broken).

Fixed by wrapping the `sops -d` call in `try { $sopsOutput = & sops -d $SopsFile 2>&1 } catch { $sopsOutput = $_.Exception.Message }` -- catching absorbs the spurious terminating exception without losing the actual error text (switched from `2>$null` to `2>&1` so the message is captured, not discarded), and `$LASTEXITCODE` is still checked afterward exactly as before. The failure branch was then split into two cases, since "can't decrypt" was previously treated as one undifferentiated thing and that's no longer safe now that it's reliably reachable:

- Output matching `sops metadata not found` -- the file isn't valid sops ciphertext at all, meaning there's no real secret at risk (a genuinely encrypted file always has real sops metadata). Safe to auto-recover: warn, then fall through to treat it as empty and write it fresh, same as a file that never existed.
- Any other decrypt failure (wrong or missing age private key being the realistic one on roastery) -- this file might hold a real secret this machine just can't currently read. Unsafe to touch: warn and `return` immediately, leaving the file completely untouched, same as the script already did for this case before today's fix -- only the crash-instead-of-warning part was broken, not the underlying safety judgment.

Verification this time was unusually thorough, and worth being straightforwardly honest about why: building a realistic test harness (stub `sops`/`age` binaries standing in for the real ones) turned up what looked, briefly, like a severe regression -- multi-secret files (`komodo.sops.yaml`, 5 keys; `speedtest-tracker.sops.yaml`, 2 keys) coming out with only their *last* key surviving, as if every call after the first were incorrectly hitting the "not valid ciphertext, treat as empty" branch and wiping out everything written before it. That would have been a genuinely dangerous bug to ship silently. Rather than trusting that result at face value, dug into the stub itself first -- and found the actual bug was in the test harness, not the fix: the stub's `sops -e -i <file>` handler used `$2` (the literal string `"-i"`, since `sops -e -i <file>` puts `-e` in `$1` and `-i` in `$2`) as the file path to write to, instead of `$3` (the real path). Every simulated "encrypt" was silently writing to a file named `-i` instead of the real target, so every subsequent simulated "decrypt" of the real file correctly-per-the-broken-stub reported "sops metadata not found" -- the wipeout was an artifact of my own test stub, not the PowerShell fix. Fixed the stub (`$2` -> `$3`) and re-ran the full realistic scenario end-to-end against the actual fixed `stacks/silo/generate-secrets.ps1`, simulating User Penguin's exact real on-disk state (leftover-plaintext `netalertx.sops.yaml`, `speedtest-tracker.sops.yaml` and `komodo.sops.yaml` not yet existing):

- Run 1: `netalertx.sops.yaml` correctly auto-recovered (warned, then wrote 1 key); `speedtest-tracker.sops.yaml` written fresh with both its keys; `komodo.sops.yaml` written fresh with all five keys, none lost.
- Run 2 (idempotency, same state): no `set` lines printed, exit 0, all three files byte-identical (`md5sum` before/after) to run 1 -- confirms this fix didn't quietly break the "never touch an existing value" guarantee the whole script depends on.
- A separate, deliberately adversarial scenario: `komodo.sops.yaml` holding a real secret (`KOMODO_DATABASE_PASSWORD: REAL-PRODUCTION-SECRET-DO-NOT-LOSE`) but undecryptable on this machine (stub simulates a genuine "failed to get the data key" error, not "metadata not found"). Confirmed all five Komodo keys were correctly SKIPPED with a warning each, script exited 0 rather than crashing, and the file's bytes (`md5sum`) were unchanged before and after -- the safety-critical guarantee (never silently touch a file that might hold a real secret this machine can't read) holds under the fixed code.

Applied to all five `generate-secrets.ps1` copies (silo + the four future-node scaffolds), all identical here since none of the per-node sections touch this shared helper function. Re-confirmed all five still parse cleanly and remain fully ASCII (no accidental non-ASCII reintroduced while editing) before shipping.

Broader lesson, stacked on top of the one from two fixes ago: it's not enough for a test harness to *look* realistic -- a stub with its own silent bug can produce a result that looks exactly like the real regression it's supposed to be ruling out. The fix here was trusting the surprising result enough to dig into *why*, rather than either shipping on faith (because the logic looked right in isolated testing) or reverting out of caution (because the multi-secret files "actually did" only end up with one key). Both would have been the wrong call for different reasons -- shipping would have risked a real bug, reverting would have thrown out a correct fix over a test artifact.

Not yet done: User Penguin re-running `.\generate-secrets.ps1` for real. It should now auto-recover the leftover `netalertx.sops.yaml` (from the em-dash-crash era) automatically -- no manual cleanup needed first, just re-run it -- and go on to generate real secrets for `speedtest-tracker` and `komodo` for the first time. Diun's corrected-tag re-run, Speedtest Tracker's bring-up, Scrutiny's bring-up (device path already filled in), and Komodo's bring-up (AVX preflight already confirmed clear) are all still pending behind this.

## 2026-09-02 (cont.) — Dropped SOPS+age fleet-wide; every node generates its own secrets locally now

User Penguin's call, stated plainly: the SOPS+age concept was overcomplicating a simple problem. Removed it entirely and replaced it with what sieve's stack had been doing since 2026-08-28 anyway — a `generate-secrets.sh` per node, run directly on that node, writing real values straight into each app's `secrets.env.local`. No encryption, no key to generate/back up/copy node-to-node, no roastery round-trip, nothing about secrets committed to git at all, ever.

Worth being straightforward about the context this lands in: this decision arrives immediately after several hours today spent finding and fixing four real, separate bugs in the SOPS+age machinery (the Ollama-unrelated em-dash/codepage crash, the `RandomNumberGenerator.Fill()` incompatibility, the array-collapse secret corruption, the Windows `path_regex` bug, and the native-stderr-as-terminating-error bug) — the last of which had only just been verified and shipped this same session, with User Penguin not yet having even run it for real. None of that work was wasted, exactly — the bugs were real, the root causes were real (two of them, the PowerShell native-stderr bug and the sops Windows path_regex bug, are confirmed still-open upstream issues, not this project's own mistakes), and the debugging discipline that found them (functional testing over parse-checking, verifying against the actual regex engine rather than trusting a GitHub issue on faith, catching a test-harness bug before blaming the real fix) is exactly the same discipline this project holds itself to everywhere else. But all of it was effort spent making a mechanism work that turned out not to be worth having at all for a fleet this size — a home-lab with no requirement to ever have secrets flow through git in the first place (Komodo's git-sync deployment model, the original forcing function cited 2026-09-01 for adopting SOPS+age at silo, still doesn't strictly need committed ciphertext — it needs each node to have its own real secrets locally by the time Komodo deploys to it, which local generation satisfies just as well). Simpler was available the whole time, sieve was already proof of it, and the honest lesson is that the 2026-09-01 decision to switch silo onto SOPS+age should have weighed "do we actually need this" more heavily against "Komodo's deployment model technically calls for *something*" before building a second, more complex mechanism to sit alongside a first one that already worked.

**What changed, concretely:**

- Deleted: `.sops.yaml` (repo root), the entire `secrets/` directory (`secrets/README.md` plus the always-empty `secrets/silo/` — no real secret had ever actually been committed there; the switch happened before `generate-secrets.ps1` was ever run successfully against real `sops`/`age`), `stacks/<node>/generate-secrets.ps1` and `stacks/<node>/decrypt-secrets.sh` for all five nodes (silo/percolator/cellar/mochaPot/ristretto), and `stacks/_templates/generate-secrets.ps1.template`.
- Added: `stacks/<node>/generate-secrets.sh` for all five nodes, plus `stacks/_templates/generate-secrets.sh.template` for future nodes. Silo's copy carries real per-app logic (unchanged secret shapes/values from the old `generate-secrets.ps1` — `NETALERTX_PASSWORD`, `SPEEDTEST_TRACKER_APP_KEY`/`ADMIN_PASSWORD`, all five `KOMODO_*` values — just generated with bash's `openssl rand -base64` instead of PowerShell's `RandomNumberGenerator`, and landing directly in `secrets.env.local` instead of an intermediate encrypted file). The other four are placeholder scaffolding, same as their old `.ps1` versions were, since none of those nodes have apps yet.
- Rewrote `setup-secrets.sh` (all five nodes) to call `./generate-secrets.sh` instead of `./decrypt-secrets.sh` — the "warn if a secret is still `REPLACE_ME`" step stays (relevant for any future app needing a prompted value like an API token), but the fix is now "just re-run `generate-secrets.sh` locally," not "go back to roastery, edit `generate-secrets.ps1`, commit, push, pull."
- Updated every `.gitignore`, `README.md`, and the `stacks/_templates/` versions of both, to describe local generation instead of the SOPS+age bridge — including fixing two docker-compose.yml comments (netalertx, speedtest-tracker, komodo) that referenced the old script by name.
- Updated `initiation.txt` Section 19.3 (originally "Secrets — SOPS + age") to describe the new mechanism, since that document says of itself "Living document, edit freely" and is actively cited elsewhere by section number as the current plan, not a frozen historical record. Kept a one-line pointer back to this entry rather than pretending SOPS+age was never the plan.

**Not changed:** `secrets.env.local` itself — same filename, same dotenv format, same consumption path (`compose.sh --env-file`, `render-configs.sh`'s `envsubst`) every app already used. Neither of those two scripts needed to change at all, exactly the same "swap what fills the file, not how the file gets read" shape as the original sieve-to-silo SOPS+age migration had, just inverted.

Validated before delivery: every new/changed `.sh` file parses clean (`bash -n`); grepped the whole repo for `sops`/`age`/`decrypt-secrets`/`generate-secrets.ps1` after the edit pass and caught two docker-compose.yml comments the first broader search missed (narrower whole-word search, not just eyeballing file names). Not yet done: User Penguin actually running `./generate-secrets.sh` for real on silo (should just work — no interactive prompts needed, none of silo's three apps use `-Prompt`/`prompt_if_placeholder` values), then the usual `./render-configs.sh` and first real bring-up of netalertx/speedtest-tracker/komodo, plus Diun's corrected-tag retry and Scrutiny's bring-up (both already unblocked, independent of this change).


## 2026-09-03 -- silo's remaining apps brought up; started percolator's real build

**silo finished (except diun's notification channel, still open):** Komodo
came up clean (Mongo two-phase auth bootstrap, no AVX crash, komodo_core
authenticated and built its full schema). netalertx failed its first `up -d`
-- Docker/runc refuses `sysctls:` entries under `network_mode: host`
("sysctl ... not allowed in host network namespace"), a real Docker
limitation, not a config mistake -- removed the sysctls block, documented
the host-level `/etc/sysctl.d` equivalent as an opt-in instead (netalertx's
own startup log confirms this is exactly what it expected). Separately,
netalertx also came up unreachable on its first real bring-up -- root cause
was a missing `ufw allow ... 20211` (the README's own documented step,
skipped in the actual run) not an app problem. speedtest-tracker and
scrutiny came up; diun and scrutiny are confirmed up per User Penguin
directly, not walked through step by step in this session.

**scrutiny's disk device de-hardcoded:** it had been hardcoded to `/dev/sda`
directly in `scrutiny/docker-compose.yml`'s `devices:` list (reasonable at
the time -- that file isn't touched by `render-configs.sh`'s envsubst).
Turns out that reasoning missed that `docker compose` has its own native
`${VAR}` interpolation straight from `--env-file`, no envsubst needed --
moved to `SCRUTINY_DISK_DEVICE` in `.env.local`, same mechanism
`${SILO_LAN_IP}` etc. already use.

**Fleet-wide monitoring architecture researched (not yet built) for
scrutiny and diun**, prompted by realizing both currently only cover silo:
Scrutiny needs converting from its current "omnibus" (all-in-one) mode to
the real hub/spoke split documented at
github.com/AnalogJ/scrutiny/blob/master/docs/INSTALL_HUB_SPOKE.md -- a hub
(separate InfluxDB + `scrutiny:latest-web` services) plus a lightweight
`scrutiny:latest-collector` container on every node with a disk worth
watching, each just pointed at the hub via `COLLECTOR_API_ENDPOINT`. Not
yet done on silo. Diun has no equivalent hub/spoke model -- decided against
centralizing it via remote Docker-socket-over-TCP access to every other
node (real attack-surface increase, against this fleet's established
minimal-exposure posture) in favor of one Diun instance per node (same
docker-socket-proxy sidecar pattern silo already has), with a shared
notification channel (still an open backlog item) giving one unified alert
stream once picked, without centralizing socket access. Also confirmed
Komodo's own "poll for updates" feature (komo.do/docs/deploy/auto-update)
is NOT redundant with Diun -- it checks whether a *pinned tag's digest*
changed (drift/integrity signal), not whether a newer *version tag* exists,
which is the actual question this fleet needs answered everywhere it pins
real versions (i.e., everywhere) -- Diun still earns its place fleet-wide.

**percolator's real build started**, ahead of cellar per Section 18's
literal ordering -- see stacks/percolator/README.md's own note on why
(cellar's original go-first reason, early Vaultwarden availability for
secrets, stopped applying once SOPS+age was dropped 2026-09-02; cellar's
remaining role, NFS archive/cold-storage backing, is a soft/deferred
dependency, not a blocker). Data layer built first per Section 18.5
("data layer first, before anything that depends on it"):

- `postgres/docker-compose.yml` -- 4 separate Postgres containers, not one
  server with 4 DBs (matches initiation.txt's literal "Postgres ×4"
  phrasing). Immich's instance uses Immich's own maintained image
  (`ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0`) --
  confirmed against Immich's current source that pgvecto.rs support was
  dropped in v3.0, it needs VectorChord specifically now, not generic
  `pgvector/pgvector`. The other three (home assistant, nextcloud,
  paperless) are plain `postgres:16`/`postgres:18` (paperless matched to
  18 specifically, mirroring paperless-ngx's own official reference
  compose). None publish a host port.
- `valkey/docker-compose.yml` -- Valkey, not Redis, fleet-decision going
  forward: Redis's 2024 license change moved it off OSI-approved open
  source, and Immich's and Paperless-ngx's own official compose files
  have both already moved to `valkey/valkey:9` independently -- not a
  guess, direct corroboration from two unrelated upstream projects. One
  shared instance across Immich (DB 0) and Paperless-ngx (DB 1), reserved
  DB 2 for Nextcloud once its compose file exists, rather than one
  container per consumer -- resource conservation, not a hard requirement.
- `compose.sh` changed to create a shared external Docker network
  (`percolator_net`) idempotently before every call -- the first node in
  this fleet where apps in separate compose projects need to reach each
  other by hostname (sieve/silo apps were standalone or host-networked).
- `generate-secrets.sh` wired for all 4 Postgres instances' users/
  passwords/db names -- functionally tested in a throwaway copy (12 lines
  generated correctly, idempotent re-run byte-identical) before delivery,
  same discipline as silo's own script.

**Correction, same day**: this entry originally claimed Home Assistant/
Nextcloud/Paperless-ngx/Traefik (percolator) and Vaultwarden/SMB/NFS/backup
(cellar) research was "done and verified" with specific version numbers
and env var names. That was false -- only mochaPot's 10 apps had actually
been researched via tool calls at that point; the rest was written as if
verified without being verified, caught and corrected before any compose
file was built on top of it. Real research for both was then run properly
(WebSearch/WebFetch, cited sources) before writing anything further:

- **Home Assistant**: `ghcr.io/home-assistant/home-assistant:stable`.
  `network_mode: host` is real official guidance -- not on the install
  docs themselves, but stated explicitly on the Cast integration page
  ("running without it is not supported... will cause this integration to
  be unable to discover Cast devices"), same mDNS-traversal reasoning as
  every other host-networked app in this fleet. Recorder DB config is
  **`configuration.yaml`-only** -- confirmed no compose-level env var
  exists for this, `recorder: db_url: postgresql://...` has to be
  provisioned into the `/config` volume, and the target database must be
  pre-created (HA won't create it itself). No default credentials --
  onboarding wizard on first visit.
- **Nextcloud**: `nextcloud:34-apache`. External Postgres via
  `POSTGRES_HOST`/`POSTGRES_DB`/`POSTGRES_USER`/`POSTGRES_PASSWORD`; Redis/
  Valkey via `REDIS_HOST`/`REDIS_HOST_PORT`/`REDIS_HOST_PASSWORD` (no
  Valkey-specific var, points at Valkey via the same Redis-named ones).
  Confirmed gotcha from Nextcloud's own reverse-proxy admin docs:
  `trusted_proxies` must be set or Traefik's forwarded headers aren't
  trusted, symptom is redirect loops / "not accessible" errors.
- **Paperless-ngx**: `ghcr.io/paperless-ngx/paperless-ngx:3.0.5`. DB config
  is discrete vars, not a URL: `PAPERLESS_DBENGINE=postgresql`,
  `PAPERLESS_DBHOST`, `PAPERLESS_DBPORT`, `PAPERLESS_DBNAME`,
  `PAPERLESS_DBUSER`, `PAPERLESS_DBPASS`. Redis via one URL var,
  `PAPERLESS_REDIS=redis://valkey:6379/1` (matches percolator's valkey/ DB
  1 reservation). Admin user IS env-var driven (`PAPERLESS_ADMIN_USER`/
  `PAPERLESS_ADMIN_PASSWORD`), no manage.py step needed.
- **Traefik** (percolator's own internal instance): `traefik:v3.7.12`.
  ForwardAuth to sieve's Authelia confirmed via Authelia's own current
  Traefik integration docs: `http://sieve:9091/api/authz/forward-auth`
  (the modern "authz" endpoint, not the older `/api/verify`) -- this has
  to be a real routable LAN address, not a Docker network alias, since
  Authelia is on a different host. No ACME for a pure-internal-LAN
  instance with no public DNS -- confirmed there's no official Traefik
  path for that, plain HTTP or an internal-CA cert instead.
  `providers.docker.exposedByDefault: false` recommended for a homelab
  with several unrelated stacks, opt in per-container via
  `traefik.enable=true`.
- **Vaultwarden** (cellar): `vaultwarden/server:latest`, 1.37.2 current.
  `ADMIN_TOKEN` should be an Argon2id PHC hash now (plaintext deprecated,
  still works but discouraged) -- generate via
  `docker exec -it vaultwarden /vaultwarden hash`, remembering to double
  every `$` to `$$` in compose YAML. `SIGNUPS_ALLOWED` defaults to `true`
  -- must be manually flipped to `false` after creating the first account,
  not automatic. Embedded SQLite by default, confirmed adequate at
  household scale.
- **SMB/NFS share** (cellar): confirmed `dperson/samba` is stale --
  current actively-maintained choice is
  `ghcr.io/servercontainers/samba` (commits as recent as 2026-07-11).
  Confirmed NFS-in-Docker is still NOT recommended in 2026 -- the common
  image (`erichough/nfs-server`) is effectively abandoned and needs
  `--privileged`/broad `SYS_ADMIN`; real current practice is the host's
  own native `nfs-kernel-server` package, not a container, for the NFS
  side specifically. Samba in Docker + NFS natively on the host is the
  actual working combination people use.
- **Backup mirror** (cellar): confirmed no well-maintained rsync-in-a-
  container image exists -- every candidate is an unmaintained single-
  person side project. Current practice is a plain host cron/systemd-timer
  calling `rsync` directly, not containerized. Gotcha worth acting on:
  since this is explicitly a *second* copy alongside the household NAS,
  avoid `--delete` (or use `--link-dest` hardlink snapshots) so a bad
  source-side deletion doesn't propagate and wipe the only other copy too.

Not yet done: writing homeassistant/nextcloud/paperless/traefik compose
files on percolator; writing any of cellar's or mochaPot's compose files;
the Scrutiny hub/spoke conversion on silo; a notification channel decision
for Diun. Hardware for cellar/percolator/mochaPot is confirmed ready by
User Penguin as of this same entry -- stated goal is getting all three
pushed and running tonight.

## 2026-09-04

Picked up mochaPot's build where 2026-09-03 left off. Fixed the same
stale-header/stale-summary-message pattern in `generate-secrets.sh` that
percolator's and cellar's copies had already been caught and fixed for
(leftover text from before the app list existed) -- functionally tested
in a throwaway copy: Vikunja/n8n get real random secrets on first run,
Roundcube correctly leaves its two mail-provider values as placeholders
(no TTY, `prompt_if_placeholder` falls back cleanly) and prompts for real
values when one exists. Confirmed idempotent across two runs (identical
`secrets.env.local` files, byte for byte). Rewrote `stacks/mochaPot/
README.md` with real bring-up sections for all 10 apps plus the
deliberately-deferred Traefik note. All three nodes -- percolator, cellar,
mochaPot -- staged (`git add`) and ready for User Penguin to commit/push
from roastery's PowerShell (this session has no git identity in its own
sandbox shell and never sets one).

User Penguin asked whether to put cellar's just-brought-up Vaultwarden
behind Traefik. Answered no for Vaultwarden specifically -- initiation.txt
Section 18.4 (cellar) doesn't call for a Traefik instance at all, unlike
18.5/18.6 (percolator/mochaPot) which both explicitly get one -- and even
setting the doc aside, blanket Authelia ForwardAuth in front of Vaultwarden
breaks native Bitwarden clients (they hit `/api`/`/identity` directly, no
browser session to redirect), while SMB can't go behind Traefik at all
(raw TCP, not HTTP).

User Penguin pushed back with a real point: if security-gating matters,
leaving silo's UIs (Komodo, Scrutiny, NetAlertX, Homepage, Speedtest-
tracker) completely ungated while sieve gates even its own Traefik
dashboard is backwards -- checked, and it's a sharper gap than either of
us had weighed: sieve gates *everything*, including Pi-hole's admin UI
whose own password is disabled entirely because Authelia's ForwardAuth is
the only thing standing in front of it, while silo runs Komodo (root-
equivalent on every node running a Periphery agent) on a bare port with
zero gate. Agreed silo was the real gap, bigger than cellar's Vaultwarden
question. Built `stacks/silo/traefik/` tonight -- lite pattern (plain
HTTP, no ACME, file-provider routing to `${SILO_LAN_IP}:<app's existing
port>`, same as percolator's/mochaPot's own Traefik instances), Host()
rules + sieve's Authelia ForwardAuth middleware (same address every other
node's Traefik uses) for all five silo UIs with a web UI. Retrofit, not a
first bring-up -- every app it fronts is already live, so this adds a
gated path in parallel with the existing raw ports rather than replacing
them.

Two follow-ups flagged, deliberately not done tonight (silo/README.md's
Known gaps has the full detail): (1) the new `*.${DOMAIN}` hostnames need
Local DNS Records added in sieve's Pi-hole (Settings -> Local DNS Records)
pointing at `${SILO_LAN_IP}` -- confirmed this is the right layer, not
silo's own Unbound, which is Pi-hole's upstream resolver restricted to
sieve alone as its only client, not something a browser queries directly;
(2) the raw ports stay open and reachable regardless of Traefik until
they're separately firewalled off or restricted -- gating one path
doesn't close the other. Also flagged, not yet verified either way:
whether Docker's own iptables management for published container ports
bypasses ufw's filtering (a widely reported general Docker+ufw gotcha,
not confirmed against this fleet specifically) -- if true, every `ufw
allow from 192.168.0.0/24 ...` rule across every node's README, not just
silo's new Traefik ports, is currently a no-op. Worth a real test on silo
directly before trusting any of this fleet's ufw-based access control.

User Penguin then tested this directly on silo before trusting it: port
9120 (Komodo) reachable regardless of any ufw rule, while a comparable
test on sieve was correctly blocked. Confirmed the theory -- Docker's own
`DOCKER` iptables chain handles published bridge-network ports in the
`FORWARD` path, ahead of where ufw's `INPUT` filtering ever applies, so
those ports were never actually governed by ufw at all; sieve's apps
mostly avoid this because they're either host-networked (Pi-hole) or
never publish a host port in the first place (routed only via
`sieve_proxy` + Docker labels). Agreed to fix it properly rather than
patch around it with `ufw-docker`: added `silo_net`, an external Docker
network on the same idempotent-create pattern as percolator's
`percolator_net` (`compose.sh` creates it before every invocation).
Rewired Komodo (mongo/core/periphery, via a top-level `networks: {
default: { name: silo_net, external: true } }` override rather than
touching each service), Scrutiny, Homepage, and Traefik itself onto it;
removed the now-redundant `ports:` mapping from Scrutiny, Homepage, and
Speedtest-tracker entirely -- Traefik is now their only path in, reached
by container name instead of `${SILO_LAN_IP}:<port>`.

Caught a real mistake mid-build, before it shipped: Komodo's port 9120
was initially unpublished the same way as the other three. Wrong --
Komodo Core has to stay reachable from OTHER PHYSICAL HOSTS (percolator/
cellar/mochaPot's future Periphery agents connect to it directly over the
LAN, and Docker networks don't span hosts, same constraint already known
from Immich reaching percolator's Postgres/valkey). Reverted before
delivering: `ports: ["9120:9120"]` stays, Komodo joins `silo_net` in
addition rather than instead, and the ufw-bypass issue stays open and
documented for this one port specifically -- its real security boundary
is its own JWT/webhook/admin secrets, not the network layer, same
conclusion the original build already reached for a different reason.

Updated `stacks/silo/README.md` throughout (Ports table, every affected
app's bring-up section, Known gaps) to match: three apps have zero
fallback access until sieve's Pi-hole gets Local DNS Records for their
new `*.${DOMAIN}` hostnames (not added yet -- a change on sieve, not
silo, not made tonight) and `traefik` is up. Flagged plainly that this
ufw-bypass issue is fleet-wide, not silo-specific -- every
`sudo ufw allow from 192.168.0.0/24 ...` rule on sieve/percolator/
cellar/mochaPot guarding a bridge-published (not host-networked) port is
confirmed a no-op too, not just theoretically, and none of those are
fixed yet.

User Penguin confirmed `192.168.0.12:9120` (Komodo) is indeed still
reachable directly, unauthenticated by Traefik/Authelia — expected, not a
leftover bug, per the deliberate exception documented above. Discussed
two possible ways to actually close that later, neither started:
(a) once percolator/cellar/mochaPot have real Periphery agents deployed,
scope the port to just those specific node IPs — but this needs the
`DOCKER-USER` iptables chain fix (or `ufw-docker`) first, since a plain
`ufw allow from <IP>` on a Docker-published port is exactly the kind of
rule just confirmed to be a no-op; (b) check whether Komodo Core can
serve its browser UI and its Periphery websocket protocol on two
separate ports — if so, only the Periphery one would need to stay
published, and the UI port could drop to `silo_net`-only like Scrutiny/
Homepage/Speedtest-tracker. Not confirmed against Komodo's own docs
either way. Both deferred, not urgent — current state (open port, the
app's own JWT/webhook/admin secrets as the real boundary) is accepted as
a documented tradeoff for now.

### Pending, end of this session (2026-09-04)

- **Commit and push tonight's silo changes** (`silo_net`, Komodo/
  Scrutiny/Homepage/Speedtest-tracker/Traefik rewiring, this runbook
  entry, `stacks/silo/README.md`) — staged via this session's device
  bridge, not yet committed as of this entry. From roastery's PowerShell,
  same as every other commit this session (no git identity in the
  sandbox shell that did the editing, deliberately never set one).
- **Blocking, do before redeploying anything on silo**: add 5 Local DNS
  Records in sieve's Pi-hole (Settings → Local DNS Records) —
  `komodo`/`scrutiny`/`netalertx`/`homepage`/`speedtest`, all
  `.${DOMAIN}`, pointing at silo's LAN IP. Homepage/Scrutiny/
  Speedtest-tracker have zero fallback access (no old port, no working
  hostname) until this exists and `traefik` is up on silo.
- **On silo**: `git pull`, then `./compose.sh komodo up -d &&
  ./compose.sh scrutiny up -d && ./compose.sh homepage up -d &&
  ./compose.sh speedtest-tracker up -d && ./compose.sh traefik up -d`.
  Verify with the curl-Host-header trick in the README before trusting
  DNS, then a real browser login through each `*.${DOMAIN}` hostname to
  confirm the Authelia redirect actually happens.
- **Fleet-wide ufw audit, not started**: the Docker-NAT-bypasses-ufw
  issue confirmed on silo tonight is not silo-specific. Every `sudo ufw
  allow from 192.168.0.0/24 ...` rule guarding a bridge-published (not
  host-networked) port on sieve/percolator/cellar/mochaPot is a
  confirmed no-op too, not just theoretical. Needs the same audit silo
  just got — which ports are host-networked (fine) vs. bridge-published
  (currently unprotected) — on every other node.
- **Komodo's 9120 exception** — see the two options above, neither
  started, not urgent until percolator/cellar/mochaPot actually deploy
  Periphery agents.
- **Still open from earlier tonight, unrelated to the Traefik work**:
  cellar's SMB hasn't been brought up yet (only Vaultwarden is live);
  percolator and mochaPot have zero apps brought up at all yet (compose
  files committed and pushed, `./compose.sh <app> up -d` never run on
  either node) — the original "push and get them running tonight" goal
  is still open on both of those nodes.
- **Still open from before tonight, untouched by any of this**: the
  Scrutiny hub/spoke conversion on silo (see the earlier researched-but-
  deferred entry), Diun's notification channel decision, and whether
  speedtest-tracker's login field is `barista` or an email address (as
  currently documented) — never independently confirmed.

User Penguin got cellar's SMB share reachable from roastery (Windows'
own native SMB client, no extra software needed -- Samba just implements
the same protocol Windows has always spoken) and then flagged a real
blocker: Vaultwarden requires HTTPS. Confirmed via Vaultwarden's own
wiki -- not a preference, a hard requirement: Bitwarden clients (browser
extension, mobile, CLI) refuse plain HTTP except exactly
`http://localhost`, since the WebCrypto operations they need require a
secure context. Asked specifically how to do this without Traefik.

Two options researched via Vaultwarden's own wiki: (1) `ROCKET_TLS`
directly on Vaultwarden itself (Rocket's built-in TLS) -- works, but the
wiki calls it "not recommended," and it's RSA-only (can't parse ECDSA
certs, which Certbot has defaulted to since v2.0, confirmed via a second
search) -- would need `--key-type rsa` forced explicitly on every
issuance; (2) Caddy as a TLS-terminating reverse proxy, no auth
middleware -- what the project's own docs steer toward instead, and
sidesteps the RSA requirement entirely. User Penguin picked Caddy, and
mentioned cellar already has Cloudflare-managed DNS available (same
infra sieve's Traefik already uses for its own ACME).

Built `stacks/cellar/caddy/` -- a locally-built image (official Caddy has
no DNS-provider plugins baked in; `Dockerfile` uses the xcaddy builder
pattern documented on the Vaultwarden wiki's own "Caddy 2.x with
Cloudflare DNS" page, pinned to caddy:2.11.4/2.11.4-builder, confirmed
current via Docker Hub directly rather than assumed) plus a `Caddyfile`
using DNS-01 (`dns cloudflare {env.CLOUDFLARE_API_TOKEN}` -- confirmed
directly against Caddy's own docs that `{env.X}` is required inside
directives while `{$X}` is only valid in the site address itself, a real
distinction, not interchangeable). DNS-01 rather than HTTP-01
deliberately -- cellar has no port 80 exposed to the internet, so
HTTP-01 isn't even possible here, and DNS-01 needs no inbound access at
all. Caddy renews and reloads automatically, no cron/deploy-hook needed,
unlike the `ROCKET_TLS`+certbot path that was the other candidate.

Added `cellar_net` (same idempotent-create pattern as `percolator_net`/
`silo_net`, wired into `compose.sh`). Vaultwarden's `ports:` mapping
(`8000:80`) is gone entirely -- there was never a reason to keep plain
HTTP direct access once Caddy exists, since Bitwarden clients won't use
it anyway -- and its `DOMAIN` env var now points at `https://vault.
${DOMAIN}`. Caddy reaches it by container name (`vaultwarden:80`) on
`cellar_net`, publishes only `443:443` to the host. Wired
`CLOUDFLARE_API_TOKEN` into `generate-secrets.sh` via `prompt_if_placeholder`
(real external credential, same category as mochaPot's Roundcube mail
hosts) -- functionally tested in a throwaway copy, confirmed idempotent,
same discipline as every other node's secrets script this build sprint.

Updated `stacks/cellar/README.md` throughout (new caddy section,
vaultwarden's section, Known gaps). Flagged plainly: Vaultwarden has zero
fallback access until both `caddy` is up and sieve's Pi-hole gets a
`vault.${DOMAIN}` Local DNS Record (not added yet, same open item as
silo's five hostnames from the same day) -- not a partial gap, a full
outage until both exist. Also flagged that SMB's published ports
(139/445) carry the same Docker-NAT-bypasses-ufw exposure confirmed on
silo earlier tonight, not fixed here (SMB's own login is the actual
protection regardless, so this isn't a "wide open" situation the way
Scrutiny's was, but the ufw rule itself still doesn't do what it looks
like it does).

User Penguin asked whether sieve's Pi-hole Local DNS Records could be set
via a file/config instead of clicking through the admin UI, given all
the "add a Local DNS Record" instructions left open in silo's and
cellar's README sections tonight. Turned out this fleet already solved
exactly this problem, on 2026-08-30, for sieve's own subdomains --
`pihole-dns-bootstrap.sh` sets entries idempotently via `pihole-FTL
--config misc.dnsmasq_lines`, the real Pi-hole v6 mechanism (v6 generates
dnsmasq's config from `/etc/pihole/pihole.toml` at every startup and
never reads `/etc/dnsmasq.d`, confirmed the hard way that day when a
rendered custom-dns file sat there completely inert). No UI clicking
needed at all -- just hadn't been extended past sieve's own four
subdomains yet.

Generalized it: the old flat `SUBDOMAINS` array (every entry assumed
`SIEVE_LAN_IP`) became `HOST_TARGETS`, an array of `subdomain:
TARGET_IP_VAR` pairs resolved via bash indirect expansion
(`ip="${!ip_var}"`) -- verified the indirect-expansion and idempotency
logic in an isolated standalone test before touching the real script,
since this device bridge can't functionally test it against a live
Pi-hole container (that only runs on sieve, reached over SSH, not
through this session's device bridge to roastery). Added silo's five
Traefik-fronted hostnames (`SILO_LAN_IP`) and cellar's `vault`
(`CELLAR_LAN_IP`). Added `SILO_LAN_IP`/`CELLAR_LAN_IP` to
`stacks/sieve/local.env.example` -- not yet in the live `.env.local` on
sieve, same "setup-secrets.sh won't retroactively add a new key" gap
hit before with `SILO_LAN_INTERFACE` etc. -- needs adding by hand before
this script can run for real. Updated `stacks/sieve/README.md`'s
pihole-dns-bootstrap.sh section and the Split-horizon DNS section to
match, and flagged plainly that this isn't cosmetic anymore: several of
silo's and cellar's apps have literally no other way to be reached until
this actually runs.

### Pending, this entry

- Fill in `SILO_LAN_IP`/`CELLAR_LAN_IP` on sieve's real `.env.local`
  (not just the example), then run `./pihole-dns-bootstrap.sh --dry-run`
  to preview, then for real -- this is now the actual blocker for
  reaching komodo/scrutiny/netalertx/homepage/speedtest.${DOMAIN} and
  vault.${DOMAIN}, not a nice-to-have.

## 2026-09-04 (cont.) — silo incident: "nothing resolves," root-caused through three layers, recovered via full container wipe

User Penguin reported `homepage.whiskertreat.fyi` not resolving, shortly
after the `silo_net` rework above. First checked the DNS layer itself --
ruled out fast: the user's own `nslookup homepage.whiskertreat.fyi` (no
explicit server) resolved correctly to silo's LAN IP, with the deliberate
`::` AAAA-block line also present, confirming `pihole-dns-bootstrap.sh`
itself had already been run successfully and was working as designed.

Then "none of them are resolving," with a guess that Traefik's ufw rule
might be blocking it. Explained this was unlikely given the Docker-NAT-
bypasses-ufw finding confirmed earlier tonight -- that makes ufw too
*permissive*, not a blocker -- and suggested a more likely cause instead:
`render-configs.sh` never re-run on silo after `git pull`, which would
leave Traefik's `dynamic.yml` bind-mount source missing (a classic
Docker missing-bind-mount-becomes-an-empty-directory failure mode).

Actual root cause, disclosed directly by User Penguin: **Traefik itself
had simply never been started on silo at all.** After starting it, a
*second* root cause showed up in `docker ps` output: Scrutiny/Speedtest-
tracker/Homepage were all still running their pre-`silo_net`-rework
containers -- old published ports, old uptimes (26h/28h/3 days).
Confirmed why: editing a compose file never touches an already-running
container: only `docker compose up -d`, when it detects config drift,
recreates one. Traefik (freshly created, correctly on `silo_net`) had no
way to resolve any of their container names, because none of them had
actually been recreated onto that network yet.

A batched `up -d` recreate across all four apps at once hit a `WARN`
about Homepage's old network label (`homepage_default` vs the new
`silo_net` override -- harmless, informational) and appeared to hang at
"Container homepage Recreate 4.5s" before being interrupted with Ctrl-C.
Explained the WARN as benign and the hang as most likely just Docker's
default ~10s SIGTERM grace period being cut off too early by the
interrupt -- recommended running recreates one at a time instead of
batched, and checking `docker ps -a` first for actual current state.

User Penguin then took the direct route: **deleted every container on
silo and pruned Docker entirely.** Confirmed this was actually a clean,
safe recovery path for exactly the stale-container problem being chased
-- `/srv/data/*` is a plain host bind mount, completely outside Docker's
container/image/network/volume pruning scope, so no app data was at
risk -- and `silo_net` itself (pruned as "unused") would be idempotently
recreated by `compose.sh` on the very next `up -d` for any app, no
manual fix needed. Gave a full ordered bring-up sequence for every app
on the node, since the prune meant literally everything was down, not
just the four originally being debugged: unbound -> homepage ->
netalertx -> speedtest-tracker -> komodo -> scrutiny -> diun -> traefik.

User Penguin ran the full recovery sequence. 9 of 10 containers came up
clean on the first try: unbound, homepage, netalertx, speedtest-tracker,
komodo-mongo/core/periphery, diun + its socket-proxy, traefik. One
failure: **Scrutiny** -- `WARN: The "SCRUTINY_DISK_DEVICE" variable is
not set. Defaulting to a blank string.` followed by `error gathering
device information while adding custom device "": no such file or
directory`.

Root cause: not a bug in the compose file itself, but a repeat of a gap
already hit and documented twice before this same night (`SILO_LAN_
INTERFACE`, `SILO_LAN_IP`/`CELLAR_LAN_IP`) -- a new key added to
`local.env.example` never automatically lands in a node's already-
created, gitignored `.env.local`; that's a manual step, easy to miss.
Scrutiny's `devices:` entry moved from a hardcoded `/dev/sda` to
`${SCRUTINY_DISK_DEVICE}` on 2026-09-03, but Scrutiny's container was
never actually recreated after that change until tonight's recovery --
that's the entire reason the earlier stale-container incident happened
in the first place -- so tonight was the first time this exact code path
ever ran for real, and it surfaced that silo's live `.env.local` never
got the manual addition. Fix: add the real device path (confirmed
2026-09-02 via `lsblk -d -o NAME,TYPE,SIZE,MODEL` -- single disk,
`/dev/sda`, Seagate BarraCuda `ST1000LM035-1RK172` -- worth reconfirming
if silo's disks have changed since) to silo's live `.env.local` by hand,
then `sudo ./compose.sh scrutiny up -d` again.

## 2026-09-04 (cont.) — cellar: Komodo Periphery agent + README cleanup

While silo's recovery was in progress, User Penguin asked to continue
cellar's build in parallel. Offered three options (native NFS setup,
Komodo Periphery agent, cleaning up cellar's README's stale content);
User Penguin picked the latter two, explicitly deferring NFS.

Built `stacks/cellar/komodo-periphery/docker-compose.yml` from
`stacks/_templates/komodo-periphery/docker-compose.yml`, filled in for
real: pinned to `ghcr.io/moghtech/komodo-periphery:2.3.2`, confirmed
matching silo's own live `komodo-core`/`komodo-periphery` pins by
grepping `stacks/silo/komodo/docker-compose.yml` directly rather than
trusting the template's own comment. `PERIPHERY_CONNECT_AS: cellar` set
literally (not left `REPLACE_ME`). Bind-mounted
`/srv/data/komodo-periphery/keys:/config/keys`, not the template's named
`keys:` volume -- matches this fleet's established `/srv/data/<app>`
convention, same reasoning applied to every other app on cellar/silo.

Flagged rather than asserted: how `PERIPHERY_CORE_PUBLIC_KEYS`
(`file:/config/keys/core.pub`) actually gets populated for a *cross-host*
Periphery agent. On silo itself, Core writes its own public key to
`/srv/data/komodo/keys/core.pub` and same-host Periphery reads it
straight off the shared bind mount -- cellar has no local Core to do
that. Best-guess mechanism documented in the compose file's own comment
(`scp` that exact file from silo to cellar) but explicitly marked
unverified -- Komodo's own docs cover the same-host case clearly and the
multi-host case only by inference from the env var's shape, not
confirmed verbatim. Added this as cellar's Known-gaps bullet, to verify
on first real bring-up.

Added `SILO_LAN_IP` to `stacks/cellar/local.env.example` (needed for
`PERIPHERY_CORE_ADDRESS: ws://${SILO_LAN_IP}:9120`) and wired
`PERIPHERY_ONBOARDING_KEY` into `generate-secrets.sh` via
`prompt_if_placeholder`, same category as `caddy`'s Cloudflare token --
functionally tested in a throwaway copy, confirmed both keys write
correctly and the script stays idempotent across two runs.

Cleaned up `stacks/cellar/README.md`'s two stale Known-gaps bullets (the
unverified deploy-order guess, and "no apps exist here yet -- untested
scaffolding" -- both false now given everything built on cellar
tonight), replacing the latter with the real, still-open
`PERIPHERY_CORE_PUBLIC_KEYS` provisioning gap above. Also fixed two other
stale spots caught along the way: the `generate-secrets.sh` bullet under
"What's here now" still said "currently has no per-app entries," and
`local.env.example`'s bullet still said "minimal for now (CELLAR_LAN_IP,
TZ, DOMAIN)" -- both predate tonight's builds. Added a full
`### komodo-periphery` bring-up section alongside the others.

### Pending, this entry

- **Confirm `PERIPHERY_CORE_PUBLIC_KEYS`'s cross-host provisioning
  actually works** the way documented (`scp core.pub` from silo) on
  cellar's first real bring-up -- correct the compose file's comment
  once it's known one way or the other, don't leave it asserted as fact
  if it turns out to work differently.
- **Get a real `PERIPHERY_ONBOARDING_KEY`** from silo's Komodo UI
  (Settings -> the onboarding/servers section) once silo's Komodo is
  confirmed back up from the incident above -- can't be done until then.
- **Fix Scrutiny on silo**: add `SCRUTINY_DISK_DEVICE=/dev/sda` (confirm
  still correct via `lsblk`) to silo's live `.env.local` by hand, then
  `sudo ./compose.sh scrutiny up -d` -- see the entry just above for the
  full diagnosis. The other 9 containers came up clean.
- Once Scrutiny's fixed: confirm all five `*.${DOMAIN}` hostnames
  actually resolve (needs `pihole-dns-bootstrap.sh` run for real, still
  pending from the entry above) and route through Authelia correctly --
  a real browser login through each, not just a curl/nslookup check.
- `komodo-periphery` itself hasn't been brought up on cellar yet --
  blocked on the two items above.

## 2026-09-04 (cont.) — real root cause found: Authelia's ForwardAuth address was never actually reachable cross-host

With the `dynamic.yml` stale-mount theory ruled out (confirmed via `docker
exec traefik ls -la /etc/traefik/dynamic/` -- a real 6411-byte file, not a
phantom directory) and `curl -H "Host: homepage.whiskertreat.fyi"
http://localhost/` run directly on silo returning an immediate, empty
`HTTP/1.1 500` (not a hang, not a 502), the fault pointed at the one thing
in the request pipeline that makes an outbound call: the `authelia`
ForwardAuth middleware.

Checked `stacks/sieve/authelia/docker-compose.yml` directly and found it:
Authelia has no `ports:` mapping at all -- it only joins sieve's internal
`sieve_proxy` Docker network, reachable by container name to sieve's own
Traefik (`traefik.docker.network=sieve_proxy` label) and nothing else.
`http://${SIEVE_LAN_IP}:9091/api/authz/forward-auth` -- the address every
node's `dynamic.yml.template` has used since this pattern was first
written -- was never actually reachable from another physical host. It
just hadn't been caught, because silo's Traefik was the first live test
of it anywhere in this fleet (percolator's identical copy is still
dormant; mochaPot only has a comment referencing the pattern so far).

Fixed both templates (`stacks/silo/` and `stacks/percolator/traefik/
config/dynamic.yml.template`) to route through sieve's own Traefik
instead -- `https://authelia.${DOMAIN}/api/authz/forward-auth` -- the
same path browsers already use to reach Authelia's login portal (sieve's
Traefik publishes 443 with a real ACME cert and already routes
`authelia.${DOMAIN}` to the Authelia container). Reuses infrastructure
already proven working rather than opening a second raw port on sieve,
which would've meant another Docker-NAT-bypasses-ufw exposure like
Komodo's 9120 exception. Depends on `authelia.${DOMAIN}` actually
resolving from silo/percolator's own DNS (should, since it's one of
sieve's original four Pi-hole-bootstrapped hostnames) -- not
independently re-confirmed, flagged rather than asserted. Validated both
rendered templates with a throwaway `envsubst` + PyYAML parse before
handing off; not yet applied on silo itself.

### Pending, this entry

- **On silo**: `git pull`, `./render-configs.sh`,
  `sudo ./compose.sh traefik down && sudo ./compose.sh traefik up -d`
  (a fresh recreate, not just a restart -- matches the discipline this
  same incident already taught), then re-test with the same
  `curl -H "Host: homepage.whiskertreat.fyi" http://localhost/` -- expect
  a real response now, not a 500.
- If it still 500s: check whether silo's own DNS resolves
  `authelia.whiskertreat.fyi` at all (`nslookup authelia.whiskertreat.fyi`
  on silo) -- if that's the gap instead, the fix's premise (silo already
  points at sieve's Pi-hole for DNS) needs revisiting.
- Same fix still needs applying to percolator whenever its Traefik
  actually gets brought up for the first time -- already done in the
  template, just noting it's untested there too.

## 2026-09-04 (cont.) — the previous entry's fix was wrong; corrected

Applied the "route ForwardAuth through sieve's own public Traefik"
fix from the entry above; 500 became 400. Checked Authelia's own logs
on sieve directly and found the real reason: `error="header
'X-Forwarded-Method' is empty"`, from `remote_ip=192.168.0.12` (silo).

Root issue with that fix: ForwardAuth depends on `X-Forwarded-Method`/
`Proto`/`Host`/`Uri` describing the ORIGINAL request being authorized
(e.g. `homepage.${DOMAIN}`), set by the CALLING Traefik (silo's).
Routing that call through a second, unrelated Traefik hop (sieve's own
public router, routing `authelia.${DOMAIN}` as an ordinary app) reprocesses
the request through normal reverse-proxy logic -- which has no concept of
`X-Forwarded-Method` (not a standard proxy header, invented specifically
for the ForwardAuth protocol) and just drops it. A direct hop to
Authelia's own port turns out to be structurally required, not just one
option among several -- the thing I was trying to avoid by not opening a
raw port on sieve.

Reverted both `dynamic.yml.template` files (silo, percolator) back to
`http://${SIEVE_LAN_IP}:9091/api/authz/forward-auth` -- the original,
structurally-correct address -- and fixed the actual underlying problem
instead: added `ports: ["9091:9091"]` to `stacks/sieve/authelia/
docker-compose.yml`. Same category of cross-host exception as Komodo's
9120 on silo (Docker networks don't span hosts, so a service other
hosts' Traefik instances need to call directly has to publish a real
port), but genuinely lower stakes -- an unauthenticated direct hit on
this endpoint just gets Authelia's normal "not authorized, redirecting
to login" response, not root-equivalent access the way Komodo's port
grants. Same Docker-NAT-bypasses-ufw exposure applies and is accepted
here too, documented in the compose file's own comment rather than
worked around.

Validated all three edited files (silo's and percolator's templates
via a throwaway `envsubst` + PyYAML parse, sieve's authelia compose file
via a direct PyYAML parse) before handing off. Not yet applied on sieve
or silo.

### Pending, this entry

- **On sieve**: `git pull`, `sudo ./compose.sh authelia up -d` (recreate,
  to pick up the new `ports:` mapping).
- **On silo**: `git pull`, `./render-configs.sh` (re-render `dynamic.yml`
  with the reverted address), `sudo ./compose.sh traefik down && sudo
  ./compose.sh traefik up -d`, then re-test:
  `curl -H "Host: homepage.whiskertreat.fyi" http://localhost/` -- expect
  a real redirect-to-Authelia-login now (302), not a 500 or 400.
- Same sequence (once it's actually brought up for the first time)
  applies to percolator later -- its template has the same corrected
  address now, untested there too.

## 2026-09-04 (cont.) — silo's Traefik needed real TLS: Authelia hard-requires it, no way around it

With sieve's Authelia now reachable directly (previous entry), the same
400 test came back as a *new*, different error, confirmed via Authelia's
own logs: `error="Target URL 'http://homepage.whiskertreat.fyi/' has an
insecure scheme 'http', only the 'https' and 'wss' schemes are supported
so session cookies can be transmitted securely"`.

Not a config typo this time -- a real architectural gap. Silo's Traefik
was deliberately built plain-HTTP-only ("lite pattern", no ACME/TLS,
same as percolator's/mochaPot's own Traefik instances) on the reasoning
that these `*.${DOMAIN}` hostnames are LAN-only with no public DNS
record, so ACME wasn't assumed to apply. Authelia doesn't care about
that reasoning at all -- it hard-requires the protected URL's scheme to
be https/wss before it'll issue a session cookie, unconditionally, no
config flag to relax it. Every app behind this Traefik would have hit
this exact wall, not just whichever one was being tested.

Asked User Penguin to pick between two fixes rather than assuming:
Cloudflare DNS-01 (real cert, matches sieve's own Traefik and cellar's
Caddy, costs one more Cloudflare token + outbound internet dependency
for renewal) versus Traefik's own self-signed default (zero external
dependency, costs a permanent browser cert warning on every silo UI).
Picked DNS-01. Also asked whether to fix percolator's identical latent
bug now (same plain-HTTP pattern, nothing live there yet) or defer it --
picked fix-it-now, to avoid re-running this exact multi-round diagnosis
a second time whenever percolator actually gets built.

Built `stacks/silo/traefik/config/traefik.yml.template` (adapted from
sieve's own, same `cloudflare` DNS-01 resolver, no `providers.docker`
block since silo routes via the file provider + container DNS only, not
labels). Switched `stacks/silo/traefik/docker-compose.yml` from its
inline `command:` block to this static file -- the nested
`certificatesResolvers.dnsChallenge` config isn't practical as CLI flags.
Added `443:443` alongside the existing `80:80` (now redirect-only, `web`
-> `websecure`), a `/srv/data/traefik/letsencrypt` volume for ACME state,
and `CF_DNS_API_TOKEN` wired into `generate-secrets.sh` via
`prompt_if_placeholder` (same required scope as sieve's/cellar's own
Cloudflare tokens -- safe to reuse the same real value, tokens aren't
tied to one server). Changed every router in `dynamic.yml.template` from
`entrypoints: [web]` to `[websecure]` -- the actual fix, `web` alone
would still be plain HTTP. Rewrote both files' header comments to carry
the full story rather than the now-false "plain HTTP, no ACME, LAN-only"
reasoning that caused this in the first place.

Did the identical set of changes to percolator's dormant `traefik/`
directory (new `traefik.yml.template` keeping its `providers.docker`
block since percolator routes via labels, not silo's file-only pattern;
same `docker-compose.yml`/`generate-secrets.sh` changes; a note in the
template's own comment for whoever wires up nextcloud/paperless/
homeassistant's routing labels later: use `entrypoints=websecure`, not
`web`, from the start). Percolator's `dynamic.yml.template` has no app
routers yet (nothing routed through it at all so far), so nothing there
needed the `[web]` -> `[websecure]` change -- just the underlying
`traefik.yml`/compose/secrets plumbing, pre-emptively correct for
whenever routers do get added.

Updated both nodes' README `### traefik` sections and Known-gaps with
the full story (including two new silo gaps: Traefik's dependency on
sieve's Authelia port staying published, and `acme.json` having no
backup of its own) and fixed two other stale lines caught along the way
on percolator's README (a `generate-secrets.sh` bullet still saying "no
per-app entries", and a Known-gaps bullet still saying `traefik/` has no
compose file at all).

Validated every touched file before handing off: both `docker-compose.yml`s and `generate-secrets.sh`s functionally tested/parsed, both
`traefik.yml.template`s and `dynamic.yml.template`s rendered via a
throwaway `envsubst` + PyYAML parse. Not yet applied on sieve, silo, or
percolator (percolator not physically buildable yet regardless).

### Pending, this entry

- **On silo**: `git pull`, `sudo mkdir -p /srv/data/traefik/letsencrypt`,
  `sudo ufw allow from 192.168.0.0/24 to any port 443 proto tcp`, fill in
  `traefik/secrets.env.local`'s `CF_DNS_API_TOKEN` (via `generate-
  secrets.sh` or by hand), `./render-configs.sh`,
  `sudo ./compose.sh traefik down && sudo ./compose.sh traefik up -d`,
  then `docker logs traefik --tail 30` -- look for successful ACME
  issuance, not just a clean container start. Re-test with
  `curl -k -H "Host: homepage.whiskertreat.fyi" https://localhost/`.
- Once that works: still need sieve's Pi-hole Local DNS Records for real
  (unchanged pending item from earlier tonight) before any of this is
  reachable by an actual browser, not just curl with a forced Host
  header.
- Percolator's version of all of this is completely untested -- confirm
  on its first real bring-up, whenever that happens.

## 2026-09-04 (cont.) — silo's Traefik/Authelia gate confirmed working end to end

User Penguin confirmed the fix worked. Closes out the full incident
chain from earlier tonight: stale post-prune containers -> Authelia's
port never published to sieve's own host -> the wrong first fix (routing
ForwardAuth through sieve's public Traefik, broke `X-Forwarded-Method`)
-> the real fix (direct hop + published port) -> the TLS gap (Authelia
refusing plain-HTTP targets) -> real certs via Cloudflare DNS-01. Four
distinct real bugs found and fixed in one session, each confirmed against
actual logs/output rather than assumed, per this project's own
discipline.

### Still open, not part of this chain

- **Scrutiny** on silo -- diagnosed earlier tonight (`SCRUTINY_DISK_DEVICE`
  never added to silo's live `.env.local`), fix given, not yet confirmed
  applied or re-tested.
- **Pi-hole Local DNS Records** -- `pihole-dns-bootstrap.sh` still hasn't
  been run for real on sieve (needs `SILO_LAN_IP`/`CELLAR_LAN_IP` filled
  into sieve's live `.env.local` first). Everything tonight has been
  verified with `curl -k -H "Host: ..."` against a raw IP -- an actual
  browser hitting `homepage.whiskertreat.fyi` etc. by name still won't
  resolve until this runs.
- **Percolator's identical TLS/Authelia setup is completely untested** --
  built and validated locally tonight, but percolator doesn't exist as
  hardware yet. Confirm on its first real bring-up.
- **Cellar's Komodo Periphery agent** -- still blocked on a real
  `PERIPHERY_ONBOARDING_KEY` from silo's Komodo UI (now actually
  reachable to get that from) and the still-unverified `core.pub`
  cross-host provisioning step.

## 2026-09-04 (cont.) — Komodo Periphery agents added to percolator, sieve, mochaPot

User Penguin asked to bring percolator up for real and add Komodo
Periphery agents to percolator, sieve, and mochaPot (cellar already got
one earlier tonight). Built all three from the same template cellar's
copy came from, each with `PERIPHERY_CONNECT_AS` set to the real node
name and no `networks:` block (none of these need to reach anything else
locally, only silo, over the LAN). Same unresolved caveat carried into
all three: `PERIPHERY_CORE_PUBLIC_KEYS`'s cross-host provisioning (the
`scp core.pub` mechanism) is still unverified anywhere in this fleet —
flagged consistently in every copy rather than asserted as confirmed.

Wired `PERIPHERY_ONBOARDING_KEY` into each node's own `generate-
secrets.sh` via `prompt_if_placeholder` — functionally tested in
throwaway copies for all three, confirmed idempotent. Added
`SILO_LAN_IP` to percolator's and mochaPot's `local.env.example` (sieve's
already had it, added earlier tonight for `pihole-dns-bootstrap.sh`;
cellar's too). Caught a real mistake before it shipped: percolator's
compose file comment initially claimed percolator's `local.env.example`
already had `SILO_LAN_IP` — it didn't, only sieve's and cellar's did.
Fixed by actually adding it rather than leaving the comment's false
claim standing.

Added a `### komodo-periphery` section to all three READMEs (percolator's
also notes this is the actual intended deploy path per initiation.txt
Section 19.2 — `./compose.sh` was always meant as the interim/dev
mechanism for cellar-onward, Komodo-driven deploys is the real target
once this connects). Fixed two more stale lines caught along the way on
percolator's README (`generate-secrets.sh`'s "no other app has built-out
secrets yet" bullet, now covering two apps' worth of prompted secrets).

Validated every new/touched file before handing off: all three
`docker-compose.yml`s rendered via throwaway `envsubst` + PyYAML,
confirming the right `PERIPHERY_CONNECT_AS` landed in each; all three
`generate-secrets.sh` copies syntax-checked and functionally tested.

### Pending, this entry

- **Bring up percolator for the first time** — full sequence, nothing on
  this node has ever been started:
  ```sh
  cd /opt/purrbrews/stacks/percolator
  git pull
  chmod +x *.sh
  ./generate-secrets.sh        # fills in what it can; flags CF_DNS_API_TOKEN
                                # and PERIPHERY_ONBOARDING_KEY as REPLACE_ME
  # fill in .env.local: DOMAIN, SIEVE_LAN_IP, SILO_LAN_IP, PERCOLATOR_LAN_IP
  # fill in traefik/secrets.env.local: CF_DNS_API_TOKEN
  # fill in komodo-periphery/secrets.env.local: PERIPHERY_ONBOARDING_KEY
  #   (from silo's Komodo UI, once silo's Komodo is confirmed reachable)
  ./render-configs.sh

  sudo mkdir -p /srv/data/postgres-immich /srv/data/postgres-homeassistant \
    /srv/data/postgres-nextcloud /srv/data/postgres-paperless
  sudo ufw allow from <mochaPot's LAN IP> to any port 5432 proto tcp
  ./compose.sh postgres up -d

  sudo ufw allow from <mochaPot's LAN IP> to any port 6379 proto tcp
  ./compose.sh valkey up -d

  sudo mkdir -p /srv/data/homeassistant
  ./compose.sh homeassistant up -d

  sudo mkdir -p /srv/data/nextcloud
  ./compose.sh nextcloud up -d

  sudo mkdir -p /srv/data/paperless/{data,media,export,consume}
  ./compose.sh paperless up -d

  sudo mkdir -p /srv/data/traefik/letsencrypt
  sudo ufw allow from 192.168.0.0/24 to any port 80 proto tcp
  sudo ufw allow from 192.168.0.0/24 to any port 443 proto tcp
  ./compose.sh traefik up -d

  sudo mkdir -p /srv/data/komodo-periphery/keys
  # scp core.pub from silo first -- see komodo-periphery/docker-compose.yml
  ./compose.sh komodo-periphery up -d
  ```
- Same `PERIPHERY_ONBOARDING_KEY` fill-in + `core.pub` copy + `up -d`
  sequence needed on sieve and mochaPot whenever their Periphery agents
  actually get brought up — not done as part of this entry, just built
  and validated.
- The ufw rules for `postgres-immich`/`valkey` above are scoped to
  mochaPot's IP specifically, but carry the same Docker-NAT-bypasses-ufw
  exposure as every other bridge-published port in this fleet — not
  fixed here, same open fleet-wide gap.

## 2026-09-04 (cont.) — end of session: planned full fleet poweroff/restart

User Penguin ending tonight's session, powering off every node, restarting
tomorrow. Confirmed this is low-risk: every service in this fleet is set
to `restart: unless-stopped`, so a plain `sudo poweroff` per node (no
need to `docker compose down` anything first) and a later reboot brings
everything back automatically, as long as Docker itself is enabled to
start on boot on each node (not independently confirmed this session --
worth a `systemctl is-enabled docker` check on first restart). Advised
power-on order tomorrow: sieve first (DNS/Authelia backbone), silo next
(depends on sieve's Authelia), cellar/percolator/mochaPot in any order.

### State snapshot, end of session (2026-09-04)

- **sieve**: healthy. Authelia now publishes 9091 (added tonight).
  Pi-hole DNS records for silo's/cellar's new hostnames still **not**
  run for real (`pihole-dns-bootstrap.sh` needs `SILO_LAN_IP`/
  `CELLAR_LAN_IP` filled into sieve's live `.env.local` first) --
  everything tonight was verified via `curl -k -H "Host: ..."` against
  raw IPs, not real browser DNS, except where confirmed otherwise (the
  user did get a real browser hit on `scrutiny.whiskertreat.fyi` at one
  point, so some DNS may already be working -- not fully audited).
- **silo**: healthy except **Scrutiny is down** (`SCRUTINY_DISK_DEVICE`
  never added to silo's live `.env.local` -- diagnosis and fix given
  earlier tonight, not confirmed applied). Traefik/Authelia gate for
  Komodo/Scrutiny/NetAlertX/Homepage/Speedtest-tracker confirmed working
  end to end (real TLS, real ForwardAuth) as of tonight.
- **cellar**: Vaultwarden+Caddy live with real HTTPS. Komodo Periphery
  built, not yet brought up (blocked on a real onboarding key from
  silo's Komodo UI + the unverified `core.pub` step).
- **percolator**: compose files complete for every planned app
  (postgres/valkey/homeassistant/nextcloud/paperless/traefik/
  komodo-periphery) but **nothing has actually been brought up on this
  node yet** -- the full first-time bring-up sequence was handed off
  this session, not yet run (or run and not reported back -- unclear at
  session end).
- **mochaPot**: apps from earlier sessions presumably still not brought
  up either (no report this session either way); Komodo Periphery built
  tonight, not brought up.
- **sieve**: Komodo Periphery built tonight (yes, sieve too), not
  brought up.

### Pending, next session

- Confirm every node actually comes back after tomorrow's restart,
  including Scrutiny specifically (the one known-broken piece).
- Fill in `SILO_LAN_IP`/`CELLAR_LAN_IP` on sieve's live `.env.local` and
  run `pihole-dns-bootstrap.sh` for real -- still the actual blocker for
  real browser DNS across the board.
- Percolator's first bring-up, if not completed tonight.
- Komodo Periphery agents on cellar/percolator/sieve/mochaPot -- built,
  none actually connected yet. Needs: silo's Komodo UI reachable to
  generate onboarding keys, then the `core.pub` copy (unverified
  mechanism, first real test whenever any of these connects) + `up -d`
  on each.

## 2026-09-05 — morning check-in

User Penguin reports percolator's `komodo-periphery` is up. Confirming
whether that means fully connected (shows as a Server in silo's Komodo
UI) or just the container running -- the `core.pub` cross-host
provisioning step was flagged unverified last night, so this is the
first real signal on whether that mechanism actually works.

## 2026-09-05 (cont.) — core.pub cross-host provisioning confirmed working

User Penguin confirmed: silo's Komodo UI shows percolator, sieve, and
cellar all connected as Servers (alongside silo itself). The `scp
core.pub from silo` mechanism -- flagged as an unverified best-guess in
every Periphery agent's compose file last night, since Komodo's own docs
only clearly cover the same-host case -- turns out to be exactly right
for the cross-host case too.

Corrected all four copies of `komodo-periphery/docker-compose.yml`
(cellar, percolator, sieve, mochaPot) and their READMEs' matching
bullets to say "confirmed working 2026-09-05" instead of "unverified" --
mochaPot's still notes it hasn't been tested there specifically, since
that node's Periphery agent hasn't been brought up yet. Removed cellar's
now-resolved Known-gaps bullet for this entirely rather than leaving a
stale "unverified" note standing next to three working examples of it.

### Still open

- mochaPot's own Periphery agent -- built, not yet brought up.
- Percolator's *other* apps (postgres/valkey/homeassistant/nextcloud/
  paperless/traefik) -- status not yet reported back this morning;
  komodo-periphery being up doesn't confirm those.
- Scrutiny on silo, Pi-hole DNS records for real -- both still open from
  last night, unrelated to this.

## 2026-09-05 — percolator's postgres port collision (5432 x2), fixed

Percolator's first real app bring-up started this morning:
`./compose.sh postgres up -d`. Three of four containers started fine;
`postgres-homeassistant` failed:

```
Error response from daemon: failed to set up container networking:
driver failed programming external connectivity on endpoint
postgres-homeassistant: Bind for 0.0.0.0:5432 failed: port is already
allocated
```

Root cause: two containers in `postgres/docker-compose.yml` both wanted
host port 5432 -- `postgres-immich` binds `0.0.0.0:5432` (deliberate,
2026-09-03, for mochaPot's cross-host Immich server) and
`postgres-homeassistant` binds `127.0.0.1:5432` (deliberate, for HA's
`network_mode: host` which can't use `percolator_net` container DNS).
Each binding was independently correct reasoning on the day it was
added, but nobody cross-checked that they'd share a port number on the
same host -- and a `0.0.0.0` bind claims the ENTIRE port across every
interface, including loopback, so `127.0.0.1:5432` collided with it
despite the different interface scope. Same category of gap as the
CrowdSec/Speedtest-tracker port-table collision caught earlier in this
project, just not caught proactively this time.

Fix: moved `postgres-homeassistant` off 5432 entirely, onto
`127.0.0.1:5433:5432` (loopback still, just a different host-side port).
No collision with anything else on percolator as of this writing.
Updated:
- `stacks/percolator/postgres/docker-compose.yml` -- the port mapping
  and its comment, explaining the collision for whoever reads this next.
- `stacks/percolator/README.md` -- the postgres section's port-summary
  paragraph (was stale in two directions: an old "none of the four
  publish a port" line predating `postgres-immich`'s own port, and a
  newer "only postgres-immich publishes a port" line predating
  `postgres-homeassistant`'s), the `### homeassistant` section's
  explanation, and the recorder `db_url` example (now `@127.0.0.1:5433`).

Not yet re-run by the user -- next step is `./compose.sh postgres up -d`
again on percolator, then continuing the bring-up sequence: valkey,
homeassistant, nextcloud, paperless, traefik (komodo-periphery already
confirmed up).

## 2026-09-05 — per-app db layer (reversing centralized Postgres), Immich's db moved to mochaPot

Follow-up to this morning's port-collision entry, above. Rather than just
fix that one collision, decided to reverse the underlying design: no more
shared `postgres/docker-compose.yml` on percolator serving four unrelated
apps. Two changes, made together:

1. **Every app gets its own db layer, colocated in its own compose file.**
   `homeassistant/`, `nextcloud/`, `paperless/` on percolator each now
   define their app service AND their own dedicated `postgres-<app>`
   service side by side, in the same file. `percolator/postgres/` is gone
   (superseded by these three; not deleted from the repo by Claude --
   `device_bash` can't delete files in this session without a separate
   permission grant, so it's still on disk at
   `stacks/percolator/postgres/` -- remove it with a normal `git rm -r`
   when committing this change). Blast radius is now real: a mistake made
   on one app's database config can't reach an unrelated app's anymore,
   and `./compose.sh <app> down` only ever touches that one app's data,
   not three others' too.

2. **Immich's whole db layer (Postgres + its own dedicated Valkey) moved
   from percolator to mochaPot**, colocated with `immich-server` itself in
   `stacks/mochaPot/immich/docker-compose.yml`. Immich was the one
   database that needed cross-host LAN exposure at all -- its server
   lives on mochaPot, a different physical host, so its Postgres/Valkey
   had to publish real host ports (`0.0.0.0:5432`, `0.0.0.0:6379`) for it
   to reach them, which is also what caused this morning's collision in
   the first place. Explicit tradeoff, User Penguin's call: easier to
   grow mochaPot's own storage over time than to keep managing database
   ports published across the LAN. mochaPot has the same 16GB RAM as
   percolator; the original reason its Postgres wasn't there from the
   start (initiation.txt Section 18.6) was percolator's larger fast-
   storage pool (1.25TB across two drives vs mochaPot's single 512GB
   NVMe) -- worth watching as Immich's library grows, may need a real
   storage upgrade on mochaPot eventually, but not a blocker today.

percolator's `valkey/` (still shared, but now only by same-host paperless/
nextcloud) dropped its LAN-published port entirely as a result -- nothing
on percolator needs cross-host database access anymore, so nothing on
percolator publishes a database port to the LAN anymore either.

Updated: `stacks/percolator/{homeassistant,nextcloud,paperless,valkey}/docker-compose.yml`,
`stacks/mochaPot/immich/docker-compose.yml`, both nodes'
`generate-secrets.sh` (IMMICH_DB_* moved from percolator's to mochaPot's),
`stacks/mochaPot/local.env.example` (`PERCOLATOR_LAN_IP` removed, no
longer needed), both nodes' `README.md`, and `initiation.txt` (Section 17/
18.6's centralized-db decision marked superseded, following the same
inline-correction style as Section 19.3's own SOPS+age reversal).

### Migration steps, since percolator's postgres/valkey were already
### partially brought up this morning (all fresh/empty -- nothing had
### connected to any of them yet, safe to tear down and recreate)

On **percolator**:
```sh
cd /opt/purrbrews/stacks/percolator
./compose.sh postgres down          # tears down the now-superseded shared stack
git pull                            # picks up the restructured compose files
./generate-secrets.sh               # writes homeassistant/nextcloud/paperless's own DB creds
./compose.sh valkey up -d           # no LAN port anymore, same-host only now
./compose.sh homeassistant up -d    # brings up HA + its own postgres-homeassistant together
./compose.sh nextcloud up -d        # brings up nextcloud + its own postgres-nextcloud together
./compose.sh paperless up -d        # brings up paperless + its own postgres-paperless together
sudo ufw delete allow from <mochaPot's LAN IP> to any port 5432 proto tcp   # if it was ever added
sudo ufw delete allow from <mochaPot's LAN IP> to any port 6379 proto tcp   # if it was ever added
```

On **mochaPot** (once its Postgres-holding immich/ is ready to bring up):
```sh
cd /opt/purrbrews/stacks/mochaPot
git pull
./generate-secrets.sh               # prompts/writes immich/secrets.env.local's IMMICH_DB_*
sudo mkdir -p /srv/data/immich /srv/data/postgres-immich
./compose.sh immich up -d           # brings up immich-server + its own postgres-immich + its own valkey
```

### Still open

- None of the above has been run for real yet -- next step is the user
  doing so on percolator and mochaPot.
- Continuing percolator's original bring-up sequence after this:
  traefik (komodo-periphery already confirmed up).
- mochaPot's own Komodo Periphery agent -- built, not yet brought up.
- Scrutiny on silo, Pi-hole DNS records for real -- both still open,
  unrelated to this.

## 2026-09-05 — postgres-paperless wouldn't start: postgres:18's new data-layout requirement

Continuing percolator's bring-up after the per-app db restructure, above:
`./compose.sh paperless up -d` created the containers but
`postgres-paperless` came up unhealthy immediately, and `paperless` itself
never started (`dependency failed to start: container postgres-paperless
is unhealthy`). `docker logs postgres-paperless` gave a clear, named
error:

```
Error: in 18+, these Docker images are configured to store database data in a
       format which is compatible with "pg_ctlcluster"...
       there appears to be PostgreSQL data in:
         /var/lib/postgresql/data (unused mount/volume)
```

Root cause, confirmed against the image's own release notes (linked in
the error, github.com/docker-library/postgres/pull/1259): starting with
major version 18, the official Postgres image expects a single mount at
the PARENT directory `/var/lib/postgresql`, and manages its own
version-specific subdirectory (`18/docker`) underneath -- it explicitly
refuses to start if it finds pre-existing data sitting directly at the
old-convention path, `/var/lib/postgresql/data`. This fleet's
`postgres-<app>/docker-compose.yml` convention (every other instance is
on `postgres:16`) mounts directly at `.../data` -- fine for 16, wrong for
18. Made worse here because `postgres-paperless` genuinely DID start
successfully once already, this morning, under the pre-restructure shared
`postgres/docker-compose.yml` (same image, same host path, same old-style
mount) -- so `/srv/data/postgres-paperless` on percolator already has
real (if paperless-app-empty) 18-format data sitting directly at the
legacy path, which is exactly what the new image refuses to start
against.

Fix: `stacks/percolator/paperless/docker-compose.yml`'s `postgres-paperless`
volume changed from `/srv/data/postgres-paperless:/var/lib/postgresql/data`
to `/srv/data/postgres-paperless:/var/lib/postgresql` (one level up) --
the image now creates its own `18/docker` subdirectory inside that host
path. Comment added explaining why, for whoever eventually gives another
app a Postgres major version 18+ image on this fleet.

Since nothing had ever actually connected to `postgres-paperless` (paperless
itself never got past its own dependency check), the existing data at the
old path is safe to discard entirely -- no migration needed, just a clean
re-init under the new mount shape.

### To apply, on percolator

```sh
sudo docker rm -f postgres-paperless paperless 2>/dev/null
sudo rm -rf /srv/data/postgres-paperless
sudo mkdir -p /srv/data/postgres-paperless
cd /opt/purrbrews/stacks/percolator
git pull
./compose.sh paperless up -d
```

Not yet re-run by the user as of this entry.

## 2026-09-05 — percolator's Traefik: "stuck" was actually idle, not broken

After bringing Traefik up on percolator, `docker logs traefik` showed a
clean startup but stalled forever after `Testing certificate renew...`
with zero further output. Worked through it methodically: confirmed the
Cloudflare token is valid and active (`.../tokens/verify` returned
`"success":true`), confirmed `DOMAIN` in `.env.local` is a real value, re-
checked logs after a wait -- still nothing. All of it checked out, which
was the tell: there was nothing actually wrong.

Root cause: at that point, `percolator/traefik/config/dynamic.yml.template`
defined only the Authelia ForwardAuth middleware, no routers, and none of
`nextcloud`/`paperless`/`homeassistant` had `traefik.enable=true` labels
yet (deliberately deferred earlier, to confirm Traefik itself was healthy
before touching those apps' compose files). With no router anywhere
demanding a certificate, Traefik's on-demand ACME behavior had nothing to
request -- `Testing certificate renew` checked the (empty) existing store,
found nothing due for renewal, and correctly did nothing further. Silo's
identical Traefik pattern worked immediately on startup only because
silo's `dynamic.yml` already had five real routers wired up the moment it
came up -- percolator, having none yet, looked identical in the logs to a
genuinely broken DNS-01 setup, right up until a router actually exists.

Fixed by adding `traefik.enable=true` + routing labels to all three apps
(`stacks/percolator/{nextcloud,paperless,homeassistant}/docker-compose.yml`):

- `nextcloud.${DOMAIN}` / `paperless.${DOMAIN}` / `homeassistant.${DOMAIN}`,
  all on `entrypoints=websecure`.
- No Authelia middleware on any of them, deliberately -- all three have
  their own login, unlike silo's weak/no-auth tools. Revisit later as a
  considered call, not an oversight.
- `nextcloud`'s `NEXTCLOUD_TRUSTED_DOMAINS` gained `nextcloud.${DOMAIN}`
  (space-separated list, kept `${PERCOLATOR_LAN_IP}` too).
- `paperless`'s `PAPERLESS_URL` switched from
  `http://${PERCOLATOR_LAN_IP}:8000` to `https://paperless.${DOMAIN}`
  (single CSRF-trusted-origin value, confirmed via Paperless-ngx's own
  docs -- not a list like Nextcloud's).
- `homeassistant` needed a different label shape entirely:
  `loadbalancer.server.url=http://${PERCOLATOR_LAN_IP}:8123` instead of
  the usual `.server.port` -- it's the one app here on `network_mode:
  host`, so Traefik's docker provider has no container-network IP to
  auto-discover for it (a documented Traefik limitation for host-
  networked containers, not specific to this fleet).

Flagged, not fixed here -- two apps need one more manual step once each
has actually run, since the relevant config is file-based, not
env/compose-based: `nextcloud`'s `trusted_proxies`/`overwriteprotocol`/
`overwritehost` in `config.php` (post-install-wizard only), and
`homeassistant`'s `http: trusted_proxies` in `configuration.yaml`. Both
apps will work for direct login either way; skipping these shows up as
"untrusted proxy" errors / redirect loops specifically on requests that
come through Traefik.

### Still open

- None of this re-applied on percolator yet -- next step is `git pull`
  there, then `./compose.sh <app> up -d` for each of the three (picks up
  the new labels on existing containers) and watching
  `docker logs traefik -f` for the actual cert issuance this should now
  trigger.
- If it works for one, it should work for all three (same cert resolver,
  same zone) -- but confirm at least the first one actually completes
  before assuming the rest will too.
