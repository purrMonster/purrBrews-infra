# ristretto

Stack directory scaffolded 2026-09-01, ahead of ristretto actually existing
as hardware/a VM — see the runbook's 2026-09-01 entry ("prepare the entire
stack for remaining containers of silo... so that we are prepared for
percolator, cellar and mochaPot and at last ristretto"). **No apps are
built here yet.** What's in this directory is only the generic tooling
every node in this fleet uses (`compose.sh`, `render-configs.sh`,
`setup-secrets.sh`, `generate-secrets.sh`) copied and adapted from
stacks/silo/, plus this stub.

Deploy order, as best understood right now: sieve → silo → ristretto (this
one) → ... — the exact position of ristretto relative to the other
not-yet-built nodes (percolator/cellar/mochaPot/ristretto) is inferred
from the order they were listed in when this scaffolding was requested,
**not confirmed against the initiation doc's own section for ristretto**.
Treat that ordering as a guess, not a fact, until checked there.

Do not add app-specific content to this README speculatively. When
ristretto's actual app list is known (check the initiation doc's relevant
section first), build each app the same way sieve's and silo's apps were
built: research the image/tags, check auth/login default state as a first
step (see silo's runbook entry on why this is a standing discipline now,
not an afterthought), check current ports in use on this host before
publishing a new one, write the docker-compose.yml, add any secrets to
generate-secrets.sh, and document it here under a `## Bringing each app
up` section with the same structure silo's README uses.

## What's here now

- `compose.sh` — wrapper so every app's docker-compose.yml sees the shared
  `.env.local` plus its own `secrets.env.local`. Copied verbatim from
  silo — nothing node-specific in the logic.
- `render-configs.sh` — renders `*.template` files into their real
  counterparts. Copied verbatim from silo.
- `setup-secrets.sh` — first-time-setup script: creates `.env.local` from
  `local.env.example`, prompts for any `REPLACE_ME`, runs
  `generate-secrets.sh` then `render-configs.sh`. Copied from silo, with
  its silo-specific prose adjusted to ristretto.
- `generate-secrets.sh` — generates ristretto's own secrets, locally, right
  here on ristretto, straight into each app's `secrets.env.local` — no
  encryption, no key, nothing committed to git. (Changed 2026-09-02:
  ristretto originally had a two-half SOPS+age bridge here instead —
  `decrypt-secrets.sh` plus a roastery-side `generate-secrets.ps1` —
  dropped fleet-wide for this simpler local-only approach; see that day's
  runbook entry.) Currently has no per-app entries — nothing to generate
  yet.
- `local.env.example` — copy to `.env.local` and fill in. Minimal for now
  (`RISTRETTO_LAN_IP`, `TZ`, `DOMAIN`) — grows as apps are added, same
  as silo's did.
- `.gitignore` — same rules as sieve's/silo's: `.env.local`,
  `*/secrets.env.local`, and rendered `*/config/*` (except the tracked
  `.template` sources) are never committed.

## First-time setup on ristretto

Once ristretto exists and has at least one app built:

```
git pull
./setup-secrets.sh
```

Same one-command flow as silo — see stacks/silo/README.md's "First-time
setup on silo" section for what this actually does step by step (the
script itself is identical).

## Known gaps / things to double-check before relying on this

- The deploy-order guess above (ristretto positioned after silo, before/after
  whichever of percolator/cellar/mochaPot/ristretto) is unverified against
  the initiation doc.
- No apps exist here yet — this whole directory is untested scaffolding,
  copied from a working silo setup but never itself run through
  `setup-secrets.sh` or `compose.sh` against a real host.
- If ristretto will run a Komodo Periphery agent (so silo's Komodo Core can
  manage it), see `stacks/_templates/komodo-periphery/docker-compose.yml`
  — copy it into an app subdirectory here once ristretto exists and fill in
  its `REPLACE_ME` values.
