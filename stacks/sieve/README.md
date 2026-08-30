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

## Secrets model (decided 2026-08-28)

Not SOPS/age — plain, gitignored, generated locally on the node:
`generate-secrets.sh` fills in every secret it *can* generate (random
passwords/keys) directly into each app's `secrets.env.local`. Two values it
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
./pihole-dns-bootstrap.sh --dry-run # preview, then run for real (see below) — sets pihole/authelia/traefik/headscale split-horizon entries via pihole-FTL's own config API
./compose.sh lldap     up -d
./lldap-bootstrap.sh --dry-run # preview, then run for real (see below) — creates LLDAP_INFRA_ADMIN_GROUP + adds barista, via lldap's API
./compose.sh authelia  up -d   # verify login against lldap before continuing
./compose.sh traefik   up -d   # confirm internal routing before continuing
./compose.sh headscale up -d
./headscale-bootstrap.sh --dry-run # preview, then run for real (see below) — creates the barista/penguin/bubbles headscale users
./compose.sh cloudflared up -d # last — only after everything above is confirmed working over LAN
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
This household's split (decided 2026-08-30): `barista` owns the fleet's own
server nodes (sieve, silo, cellar, percolator, mochaPot), `penguin` and
`bubbles` own their respective personal devices. The script creates
whichever of those three don't already exist, via `headscale users create`
inside the container — idempotent, safe to re-run.

```sh
./headscale-bootstrap.sh --dry-run   # see what it would do
./headscale-bootstrap.sh             # actually do it
```

Run it any time after `./compose.sh headscale up -d`. It doesn't generate
pre-auth keys or add any devices — that's a deliberate one-at-a-time manual
step (`headscale preauthkeys create --user <name> --expiration 1h`, then
`tailscale up --login-server=https://headscale.${DOMAIN} --authkey=<key>`
on the device itself), not something to automate away.

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
idempotently: reads the current value, adds only whatever's missing
(pihole/authelia/traefik/headscale `.${DOMAIN}` -> `SIEVE_LAN_IP`), and
restarts the container only if something actually changed.

```sh
./pihole-dns-bootstrap.sh --dry-run   # see what it would do
./pihole-dns-bootstrap.sh             # actually do it
```

Run it any time after `./compose.sh pihole up -d` — nothing else needs to
be up first, and it's safe to re-run (e.g. after adding a new subdomain to
the `SUBDOMAINS` array at the top of the script).

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

`pihole-dns-bootstrap.sh` sets the sieve-hosted subdomains (pihole,
authelia, traefik, headscale) resolving to `SIEVE_LAN_IP` on the LAN,
directly in Pi-hole's own live config (see that script's section above —
this used to be a rendered `custom-dns/*.conf` file, which turned out to be
inert under Pi-hole v6). Services that end up on percolator/mochaPot later
get their **own** entries pointing at *that* node's LAN IP — sieve's
Traefik only fronts the external tunnel, per the hybrid split-horizon
architecture (see the initiation doc, Section 0.3 / WBS 18.2).

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
