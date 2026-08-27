# purrBrews-infra

Self-hosted infrastructure-as-code for a multi-node home server fleet — Docker Compose stacks, Traefik + Authelia SSO, SOPS-encrypted secrets, and a full deployment runbook.

## Layout

- `stacks/<node>/<app>/docker-compose.yml` — one folder per app, grouped by the node it runs on.
- `secrets/` — SOPS-encrypted secrets only (see `secrets/README.md`). Never unencrypted.
- `.env` — shared, non-secret path variables (`PROJECT_DIR`, `DATA_DIR`, `MEDIA_DIR`), identical on every node.
- `.env.local` (not tracked) — host-specific values, e.g. this repo's own remote URL. Never referenced by literal value from a tracked file.
- `runbook.md` — living operational log: decisions, what's done, what's next.

## Nodes

| Node | Role |
|---|---|
| sieve | Gateway — DNS/DHCP, identity, tunnel routing |
| silo | Security, QoL & fleet ops |
| cellar | Vaultwarden, bulk archive & local backup mirror |
| percolator | Core stateful apps |
| mochaPot | Media/utility + kiosk |
| ristretto | Independent monitoring |
| roastery | Opportunistic AI + gaming (not part of the Docker fleet) |

Deploy order: sieve → silo → cellar → percolator → mochaPot → ristretto.

## Secrets

Secrets are encrypted at rest with [SOPS](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age) and committed directly into `secrets/` — safe to store anywhere in ciphertext form. The age private key itself lives outside this repo entirely and is never committed under any circumstance.
