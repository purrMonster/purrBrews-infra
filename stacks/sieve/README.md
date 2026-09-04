# sieve — network & identity stack (WBS 18.2)

Six apps, one docker-compose.yml each, brought up in this order (each one
depends on the one before it being healthy — see the "why" in the runbook's
2026-08-28 entries):

1. **pihole** — DNS/DHCP, everything else depends on local name resolution.
   Its admin UI is reverse-proxied through Traefik (see below) rather than
   published directly, so it isn't really usable over HTTP until Traefik is
   also up — DNS itself works from the moment this container is healthy.
2. **lldap** — identity backend
3. **authelia** — bundles its own Redis; needs lldap up first
4. **traefik** — forward-auth middleware points at the now-verified authelia
5. **headscale** — remote LAN mesh
6. **cloudflared** — external exposure, deliberately last

**Plus crowdsec** (Section 18.3, not one of the original six — added
2026-09-01). Originally planned split across silo (LAPI/decision engine)
and sieve (agent + firewall bouncer); moved here entirely once cross-node
agent registration and the firewall bouncer's deployment mechanics turned
out to be the only real source of complexity in that design, and sieve is
also the only node CrowdSec actually has anything to watch on right now
(silo has no public exposure). See the runbook's 2026-09-01 entry for the
full reasoning. Bring it up after `cloudflared` — see its own section
below.

## Ports in use on this host (added 2026-09-01)

**Check this table before publishing a new port in any app's
`docker-compose.yml`.** Added after crowdsec's first bring-up failed
outright (`address already in use`) from colliding with Pi-hole's
already-published 8080 — a collision that would've been caught by
scanning this table first, instead of discovered at `docker compose up`
time. Two entries here need the whole table to make sense: Pi-hole uses
`network_mode: host` (no `ports:` list of its own — whatever it binds
lands directly on the host), and Traefik/lldap/crowdsec use normal
Docker port-publishing (`ports:` in their compose files) — both end up
occupying the same host port space, so they have to be checked against
each other, not just against other entries of the same kind.

| Port | Proto | Owner | Notes |
|------|-------|-------|-------|
| 53 | tcp+udp | pihole | DNS. `network_mode: host`. |
| 67 | udp | pihole | DHCP — **currently off** (see pihole/docker-compose.yml's closing comment); reserved here so it isn't handed out elsewhere before it's turned on. |
| 80 | tcp | traefik | HTTP, redirects to 443. |
| 443 | tcp | traefik | HTTPS, all app routing. |
| 8080 | tcp | pihole | Admin webserver, moved off 80/443 (2026-08-29) — see "Pi-hole's admin UI" below. Reachable only from Traefik's subnet via the ufw rule in that section, not the whole LAN. |
| 8090 | tcp | crowdsec | LAPI, loopback-only (`127.0.0.1:8090:8080` — container's own internal port is still 8080, only the host-side publish moved off 8080 to dodge Pi-hole). Moved here 2026-09-01 after the collision above. |
| 17170 | tcp | lldap | Admin web UI, LAN-reachable directly — not yet routed through Traefik/Authelia (see Known gaps). |

Not host ports at all, for contrast — reachable only via Traefik's
routing over the internal `sieve_proxy` Docker network, never published
directly: authelia (9091), headscale (8080 *inside its own container* —
unrelated to Pi-hole's host 8080 above, no collision since it's never
published to the host).

silo's ports are tracked separately in `stacks/silo/README.md` (different
host, no shared port space with this table).

## Secrets model (decided 2026-08-28)

Not SOPS/age — plain, gitignored, generated locally on the node:
`generate-secrets.sh` fills in every secret it *can* generate (random
passwords/keys) directly into each app's `secrets.env.local`. (This was
sieve's own decision at the time, made before silo existed — silo
initially went a different way, SOPS+age, then dropped it 2026-09-02 in
favor of this exact pattern fleet-wide; see the runbook entries for both
dates. Every node uses sieve's original approach now.) Two values it
can't generate — because they only exist inside your Cloudflare account —
get a `REPLACE_ME` placeholder you fill in by hand. Nothing here ever gets
committed; `.gitignore` in this directory covers all of it.

## First-time setup on sieve

```sh
cd /opt/purrbrews/stacks/sieve

# These were authored/committed from roastery (Windows) — NTFS has no
# executable bit, so git may have checked them in without +x. Harmless to
# run even if it was already set:
chmod +x *.sh

./bootstrap-network.sh      # creates the shared sieve_proxy docker network
./generate-secrets.sh       # fills in every secret it can; flags the rest

# Fill in by hand:
#   .env.local                     DOMAIN=<your real domain>
#   traefik/secrets.env.local      CF_DNS_API_TOKEN=<see below>
#   cloudflared/secrets.env.local  TUNNEL_TOKEN=<see below>

./render-configs.sh         # bakes DOMAIN/SIEVE_LAN_IP into every config
```

### Getting CF_DNS_API_TOKEN

Cloudflare dashboard → My Profile → API Tokens → Create Token → **Edit
zone DNS** template, scoped to your domain's zone only (not account-wide).
Traefik uses this for the DNS-01 ACME challenge, so LAN clients get a real
Let's Encrypt cert instead of a browser warning.

### Getting TUNNEL_TOKEN, and wiring up public hostnames

```sh
cloudflared tunnel login
cloudflared tunnel create sieve
cloudflared tunnel token sieve      # paste this into cloudflared/secrets.env.local
```

This deployment uses a **token-based, remotely-managed** tunnel — there's
no local `config.yml`/`credentials.json` on the node. Instead, in the
Cloudflare Zero Trust dashboard, add a **Public Hostname** for each service
you want reachable from outside, pointing at `http://traefik:80` as the
origin (cloudflared reaches Traefik by its container name over the
`sieve_proxy` network — no host port on Traefik needs to be exposed for
this at all). Traefik's own Host-rule routing (see each app's
`docker-compose.yml` labels) takes it from there.

## Bringing each app up

```sh
./compose.sh pihole    up -d
./pihole-dns-bootstrap.sh --dry-run # preview, then run for real (see below) — sets every cross-node hostname's split-horizon entry via pihole-FTL's own config API
./compose.sh lldap     up -d
./lldap-bootstrap.sh --dry-run # preview, then run for real (see below) — creates LLDAP_INFRA_ADMIN_GROUP + adds barista, via lldap's API
./compose.sh authelia  up -d   # verify login against lldap before continuing
./compose.sh traefik   up -d   # confirm internal routing before continuing
./compose.sh headscale up -d
./headscale-bootstrap.sh --dry-run barista # preview, then run for real (see below) — creates the headscale user(s) you name
./compose.sh cloudflared up -d # last — only after everything above is confirmed working over LAN
./compose.sh crowdsec up -d    # Section 18.3, not one of the six — see its own section below
./crowdsec-bouncer-bootstrap.sh --dry-run # preview, then run for real (see below) — installs + registers the firewall bouncer
```

`./compose.sh <app> logs -f` / `down` / etc. all work the same way — it's a
thin wrapper that just supplies the right `--env-file` flags.

### `headscale-bootstrap.sh` — user provisioning via headscale's CLI (added 2026-08-30)

headscale "users" aren't login accounts — they're a grouping label every
device on the tailnet belongs to, mainly so ACL policy can later say things
like "only barista's nodes can reach the DB ports" (no ACL policy is
configured yet — `config/config.yaml.template` has no `acl_policy_path` —
so today this is purely organizational, but the grouping is far easier to
get right up front than to re-home devices into different users later).
This household's model (decided 2026-08-30): `barista` owns the fleet's own
server nodes (sieve, silo, cellar, percolator, mochaPot); `penguin` and
`bubbles` will own their respective personal devices, whenever those two
are actually being onboarded.

Takes the user(s) to create as arguments — deliberately not a hardcoded
list, since creating a headscale user is a provisioning action (same
category as an lldap account), not a fixed fact about the stack. Concretely:
run it for `barista` now, since the fleet's own nodes are about to join the
tailnet; hold off running it for `penguin`/`bubbles` until you're actually
ready to add their devices, same standing call as those two's lldap
accounts ("once everything's up and we're ready to use the system like
production").

```sh
./headscale-bootstrap.sh --dry-run barista   # see what it would do
./headscale-bootstrap.sh barista             # actually do it

# later, whenever penguin/bubbles are actually being onboarded:
./headscale-bootstrap.sh penguin bubbles
```

Idempotent either way — safe to re-run, only creates whichever named
user(s) don't already exist. Run it any time after `./compose.sh headscale
up -d`. It doesn't generate pre-auth keys or add any devices — that's a
deliberate one-at-a-time manual step (`headscale preauthkeys create --user
<name> --expiration 1h`, then `tailscale up
--login-server=https://headscale.${DOMAIN} --authkey=<key>` on the device
itself), not something to automate away.

### `pihole-dns-bootstrap.sh` — split-horizon DNS via Pi-hole's own config API (added 2026-08-30)

The original plan was a rendered `custom-dns/*.conf` file bind-mounted into
`/etc/dnsmasq.d/` — a v5-era Pi-hole pattern. This stack runs Pi-hole v6
(FTL v6.7), which generates dnsmasq's actual config entirely from
`/etc/pihole/pihole.toml` at every startup and never scans `/etc/dnsmasq.d`
at all — that file sat there completely inert, no error or warning, just
silently never read. First real login test failed with NXDOMAIN on
`pihole.${DOMAIN}` despite the file being correctly rendered and mounted,
which is how this got caught (see the 2026-08-30 runbook entry for the full
diagnosis). The real v6 mechanism is `pihole.toml`'s `misc.dnsmasq_lines`
array — a raw dnsmasq-config-line passthrough (same `address=/domain/ip`
syntax as before, just relocated), set via `pihole-FTL --config
misc.dnsmasq_lines '[...]'` instead of a file. This script sets it
idempotently: reads the current value, adds only whatever's missing, and
restarts the container only if something actually changed. Originally just
sieve's own four subdomains (all -> `SIEVE_LAN_IP`) — generalized
2026-09-04 to a `HOST_TARGETS` array of `subdomain:TARGET_IP_VAR` pairs
(was a flat `SUBDOMAINS` list before that), once silo's and cellar's own
Traefik/Caddy rework that same day made their hostnames the *only* way to
reach several apps at all (their old raw ports were removed). Add a line
to `HOST_TARGETS` any time a new cross-node hostname needs a DNS entry —
`TARGET_IP_VAR` just needs to already be sourced from `.env.local` (see
the script's own top-of-file guard clauses).

Each subdomain also gets an `address=/domain/::` line (added 2026-08-30,
during `cloudflared` bring-up) — `address=/domain/ip` only intercepts A
(IPv4) queries; an AAAA (IPv6) query for the same name still gets
forwarded upstream and answered for real once that name has actual public
DNS, which `headscale.${DOMAIN}` now does via `cloudflared`. A LAN client
then saw a mix of our local A answer and Cloudflare's real AAAA answer,
and most OSes/browsers prefer IPv6 when it's offered — so it was
connecting straight to Cloudflare's public edge instead of sieve, not the
LAN routing you'd expect (surfaced as `ERR_QUIC_PROTOCOL_ERROR`, then
`ERR_ECH_FALLBACK_CERTIFICATE_INVALID` once QUIC was disabled). The `::`
line is unroutable, so a client that prefers it fails fast and falls back
to the real IPv4 address. Applied to every subdomain, not just the one
that's public today, so this doesn't need rediscovering the next time
another one gets exposed through `cloudflared`.

```sh
./pihole-dns-bootstrap.sh --dry-run   # see what it would do
./pihole-dns-bootstrap.sh             # actually do it
```

Run it any time after `./compose.sh pihole up -d` — nothing else needs to
be up first, and it's safe to re-run (e.g. after adding a new hostname to
the `HOST_TARGETS` array at the top of the script).

### `lldap-bootstrap.sh` — group provisioning via lldap's API (added 2026-08-30)

Authelia's `access_control` (see `authelia/config/configuration.yml.template`)
gates `pihole.${DOMAIN}` and `traefik.${DOMAIN}` on membership in the
`LLDAP_INFRA_ADMIN_GROUP` group (`.env.local`, default
`purrbrews_infra_admins`) — but that variable only feeds Authelia's own
rendered config; nothing pushes it into lldap itself, since lldap's groups
are directory data (created via its UI/API), not something templated into
`lldap/docker-compose.yml` the way `LLDAP_ADMIN_PASSWORD` is. This script
closes that gap: it logs into lldap's REST auth endpoint as `admin`, then
uses lldap's GraphQL API (the same one its own admin UI calls) to create
the group if it's missing and add `barista` to it if not already a member.
Idempotent — safe to re-run.

Run it with `--dry-run` first, at least the first time: reads (auth,
listing groups, looking up barista) happen for real, but it prints what it
*would* create/change instead of actually calling `createGroup` /
`addUserToGroup`. Worth it here specifically because this is the first
script in the stack that calls lldap's live API rather than just
generating a config file — see the note at the top of the script and the
2026-08-30 runbook entry.

```sh
./lldap-bootstrap.sh --dry-run   # see what it would do
./lldap-bootstrap.sh             # actually do it
```

**It does not create the `barista` account itself** — that's still a
manual step in the admin UI (barista's SSO password is meant to be typed
in and known by you, not auto-generated into a secrets file the way
service-to-service credentials are). If `barista` doesn't exist yet when
you run this, the script says so and does nothing destructive; create the
account, then re-run it.

### crowdsec — log-based intrusion detection + firewall enforcement (added 2026-09-01)

Two pieces: the `crowdsec` container itself (reads logs, decides who to
ban) and `crowdsec-bouncer-bootstrap.sh` (installs the thing that actually
enforces those bans — see the script's own header for why that has to be a
native host package, not a container).

```sh
sudo mkdir -p /srv/data/crowdsec/data /srv/data/traefik/logs
./compose.sh crowdsec up -d
```

Before trusting the sshd collection, confirm sieve is actually writing to
`/var/log/auth.log` (true on a standard rsyslog-based Debian install; not
true on a stripped-down journald-only one):

```sh
ls -la /var/log/auth.log   # should exist and have a recent mtime
```

If it doesn't exist, the sshd collection has nothing to parse and silently
does nothing — this needs a different acquisition method (journalctl
source) rather than the file-based one in `config/acquis.yaml.template`;
not yet built, see the runbook backlog.

Then install and register the firewall bouncer:

```sh
./crowdsec-bouncer-bootstrap.sh --dry-run   # see what it would do
./crowdsec-bouncer-bootstrap.sh             # actually do it
```

Verify it's actually connected (not just installed):

```sh
docker exec crowdsec cscli bouncers list   # should show sieve-firewall-bouncer with a recent last-seen time
docker exec crowdsec cscli metrics         # traffic through each collection's scenarios, once there's been any
```

**Before relying on this to protect anything: test that a ban actually
gets enforced**, the same "don't assume, verify" discipline unbound's
access-control needed twice before it was right. A safe way to test
without banning yourself: `sudo docker exec crowdsec cscli decisions add
--ip 198.51.100.1 --duration 1m --reason test` (a TEST-NET address, not a
real one — see RFC 5737).

You can't actually verify this by trying to send traffic *from*
198.51.100.1 — that would need IP-spoofing tools, not something to reach
for just to test a firewall rule. What you can check directly is whether
the bouncer actually pulled the decision and applied it to sieve's real
firewall state, which is the part that matters (LAPI having a decision
and the bouncer enforcing it are two different things — this is the check
that the second one is actually happening):

```sh
sudo ipset list -n | grep -i crowdsec   # find crowdsec's ipset name(s)
sudo ipset list <name-from-above> | grep 198.51.100.1   # should be present
sudo iptables -L -n -v | grep -i crowdsec   # confirm a rule references that set
```

Then confirm it clears itself, both in crowdsec's own view and in the
actual firewall state, once the minute is up:

```sh
sudo docker exec crowdsec cscli decisions list   # should no longer list it
sudo ipset list <name-from-above> | grep 198.51.100.1   # should be gone here too
```

If the entry shows up in `cscli decisions list` but never actually lands
in the ipset, that's a real gap between "crowdsec decided to ban" and
"sieve's firewall enforces it" — worth chasing down before trusting this
with anything, not something to wave off.

If you ever do lock yourself out from outside (see the runbook's
CrowdSec-self-lockout discussion), fix it from LAN/tailnet access — SSH
isn't publicly exposed, so a ban on your public IP doesn't touch it:

```sh
docker exec crowdsec cscli decisions list             # find the offending entry
docker exec crowdsec cscli decisions delete --ip <ip>
```

## Pi-hole's admin UI, and why it needs a firewall rule (decided 2026-08-29)

Pi-hole uses `network_mode: host` (it needs to see real LAN traffic for
DNS), and Traefik separately publishes host ports 80/443 for LAN-facing
routing — those collide if Pi-hole's own webserver also tries to bind
80/443 on the same host. Fix: Pi-hole's webserver moved to port 8080
(`FTLCONF_webserver_port` in `pihole/docker-compose.yml`), and
`pihole.${DOMAIN}` is now a Traefik route (`traefik/config/dynamic.yml.template`)
that reaches it via `http://host.docker.internal:8080` — `extra_hosts:
host.docker.internal:host-gateway` in `traefik/docker-compose.yml` is what
makes that resolvable from inside Traefik's container, since a host-network
container isn't reachable by container name the way the rest of the stack
is.

**Pi-hole's own password is also disabled** (`FTLCONF_webserver_api_password: ""`)
— Authelia's forward-auth middleware on the `pihole` router is the *only*
gate now, not an additional one in front of Pi-hole's own login. This means
**port 8080 must never be reachable from anywhere except Traefik itself.**
Concretely, on sieve:

```sh
# Find sieve_proxy's actual subnet (Docker assigns it automatically):
docker network inspect sieve_proxy --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'

# Allow only that subnet to reach 8080 — nothing else, not even the rest of the LAN:
sudo ufw allow from <subnet from above> to any port 8080 proto tcp comment 'traefik -> pihole webui'
```

If that rule is ever missing or too broad, the result is a fully
unauthenticated Pi-hole admin panel reachable to whoever can reach it — this
firewall rule *is* the security boundary here, not a hardening extra.
Backlog: check Pi-hole's own docs (and whether a community fork exists) for
a real reverse-proxy auth-trust mechanism (header-based or OIDC) instead of
disabling the password outright — see the runbook backlog.

DNS itself (port 53, TCP+UDP) is unrelated to any of this and still needs
its own `ufw` rule scoped to your LAN subnet, same as always.

## Split-horizon DNS

`pihole-dns-bootstrap.sh` sets every cross-node hostname's split-horizon
entry directly in Pi-hole's own live config (see that script's section
above — this used to be a rendered `custom-dns/*.conf` file, which turned
out to be inert under Pi-hole v6): sieve's own four subdomains (pihole,
authelia, traefik, headscale) resolve to `SIEVE_LAN_IP`; silo's five
Traefik-fronted apps (komodo, scrutiny, netalertx, homepage, speedtest)
resolve to `SILO_LAN_IP`; cellar's Vaultwarden (vault) resolves to
`CELLAR_LAN_IP` — each pointing at *that* node's own LAN IP, not sieve's,
per the hybrid split-horizon architecture (see the initiation doc,
Section 0.3 / WBS 18.2). Added 2026-09-04, once silo's Docker-NAT-
bypasses-ufw fix and cellar's Caddy/HTTPS requirement each made a real
hostname the *only* remaining way to reach several apps — this isn't
optional cosmetic DNS, komodo.${DOMAIN} etc. and vault.${DOMAIN} won't
resolve at all until this script has been run with `SILO_LAN_IP`/
`CELLAR_LAN_IP` filled in on sieve's own `.env.local`.

## Known gaps / things to double-check before relying on this

- **Image tags are pinned to what was current as of 2026-08-28.** Several
  months may have passed — check each app's Docker Hub/GitHub releases (or
  just wait for Diun, once silo is live, to flag it) before first deploy,
  and bump the tag in the relevant `docker-compose.yml` if a newer stable
  release exists.
- **lldap's env var names** (`LLDAP_JWT_SECRET`, `LLDAP_KEY_SEED`,
  `LLDAP_LDAP_BASE_DN`, `LLDAP_LDAP_USER_PASS`) are current as of v0.6.3 —
  double-check against lldap's own docs if you bump the image tag later,
  these have changed across versions before.
- **Authelia's `access_control` policy defaults to `one_factor`** everywhere
  (no TOTP enrollment needed for first login). Tighten individual rules to
  `two_factor` once you've confirmed TOTP enrollment works end to end —
  don't leave it at `one_factor` long-term.
- **Authelia's notifier is filesystem-based** (writes to a file inside the
  container, not email) until you configure SMTP — fine for initial setup,
  but you won't get real notification delivery until that's wired up.
- **lldap's admin web UI (port 17170) is directly host-published**, not yet
  routed through Traefik/Authelia. Worth doing once the rest of this stack
  is confirmed working.
- **crowdsec's firewall-bouncer package variant is hardcoded to
  `-iptables`**, on the assumption that Debian's `iptables` command (even
  when nft-backed, the modern default) is what the bouncer shells out to.
  Not verified against a real nftables-only setup — if rules don't
  actually apply, try `-nftables` instead (see
  `crowdsec-bouncer-bootstrap.sh`'s header comment).
- **No logrotate for `/srv/data/traefik/logs/access.log`** — it grows
  unbounded until something rotates it. Fine at home-lab volume for now,
  revisit if disk usage becomes a problem.
- **crowdsec's sshd collection assumes rsyslog writes `/var/log/auth.log`**
  — not verified against sieve's actual Debian install yet (see the
  crowdsec section above for how to check, and what to do if it's
  journald-only instead).
- **No AppSec component (WAF-style request inspection) configured** —
  scope was kept to log-based detection (traefik/sshd/linux collections)
  plus firewall enforcement, matching what CrowdSec was actually brought
  on to do. `crowdsecurity/appsec-*` collections are a possible later
  addition, not needed for the current threat model.
- **CrowdSec's own remote-unban-method backlog item is unrelated to any of
  the above and still open** — see the runbook.
