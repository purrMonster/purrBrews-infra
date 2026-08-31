# secrets/

This directory holds SOPS-encrypted files only — ciphertext, safe to commit. Never place an unencrypted secret here or anywhere else in this repo.

- Encryption/decryption key: an age keypair. The **public** key goes into `.sops.yaml` at the repo root (tracked, not secret). The **private** key lives at `/etc/purrbrews/age/keys.txt` on each node that needs to decrypt — outside this repo entirely, generated once (on sieve, first in deploy order) and copied node-to-node over SSH, never committed.
- Offline backup of the private key (printed or on a USB kept safely) is the disaster-recovery copy; a convenience copy in Vaultwarden (once cellar is live) is secondary to that.
- To encrypt a new secret file: `sops -e -i secrets/<name>.sops.yaml`. To edit: `sops secrets/<name>.sops.yaml` (decrypts in your editor, re-encrypts on save — needs the private key present locally).

## Layout (2026-08-31)

One subdirectory per node: `secrets/<node>/<app>.sops.yaml`, one file per app — e.g. `secrets/silo/komodo.sops.yaml`. Each file is a flat YAML mapping (`KEY: value`, no nesting) so it round-trips cleanly through `sops -d --output-type dotenv` into the same `<app>/secrets.env.local` format every stack's `compose.sh`/`render-configs.sh` already consumes.

**Scope: silo onward only.** sieve's own stack deliberately keeps its original pattern instead — `stacks/sieve/generate-secrets.sh` generates secrets locally on the node itself, plaintext, never committed even as ciphertext (decided 2026-08-28, before this SOPS+age layout existed — see that day's runbook entry). Not retrofitted onto SOPS; sieve's mechanism already works and is already deployed, and Komodo's git-sync deployment model (cellar onward) is what actually made committed ciphertext necessary in the first place — sieve and silo are both still deployed by hand over SSH, so silo didn't strictly need the switch either, but starting the SOPS convention at silo (rather than waiting for cellar/Komodo) means it's proven working before anything depends on it for real deployment, not just at first Komodo use.

Two half-scripts bridge each node's secrets into this layout, mirroring `generate-secrets.sh`'s role on sieve but split across where each half has to run (Section 19.6 — no live coding on fleet nodes, so generation/encryption happens on roastery, not the node):

- `stacks/<node>/generate-secrets.ps1` — runs on **roastery**. Fills in real values (random where possible, prompted where not — a Cloudflare token, an API key) and encrypts each file in place with the age **public** key only; no private key needed for this half. Commit and push the resulting ciphertext from here.
- `stacks/<node>/decrypt-secrets.sh` — runs on **the node itself**, after `git pull`. Needs the age **private** key present at `/etc/purrbrews/age/keys.txt`. Decrypts each `secrets/<node>/<app>.sops.yaml` into `<app>/secrets.env.local`, the same gitignored, disposable, locally-consumed file sieve's apps have always used — nothing about `compose.sh` or `render-configs.sh` had to change.

Both scripts are idempotent the same way `generate-secrets.sh` is: a key that already holds a real value is never touched, so re-running either one later (e.g. once a new app needs a new secret) is always safe.
