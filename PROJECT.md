---
project: purrBrews-infra
status: legacy
status_reason: Superseded by purrbrews-containers, which has run the fleet since the 2026-10-13 rebuild; archiving is the planned close-out
resume_trigger: n/a. Don't resume; reuse parts through purrbrews-containers if needed
last_activity: 2026-09-11
last_reviewed: 2026-10-29
repo: https://github.com/purrMonster/purrBrews-infra
related: ["[[purrbrews-containers]]", "[[purrbrews]]"]
tags: [project]
---

# purrBrews-infra

## What it is
The first infrastructure-as-code repo for the purrBrews fleet: Docker Compose stacks per node and app, Traefik + Authelia single sign-on, SOPS/age-encrypted secrets, and a dated runbook. It planned seven nodes (sieve, silo, cellar, percolator, mochaPot, ristretto, roastery); the fleet that was actually built has five Linux nodes plus roastery and lives in [purrbrews-containers](https://github.com/purrMonster/purrbrews-containers).

## Current state
| Area | State | Evidence |
|---|---|---|
| Code | Stacks for 7 planned nodes plus `_templates`; 70 commits, 2026-08-27 to 2026-09-11 | [stacks/](stacks/), `git log` |
| Release | None (no tags) | `git tag` is empty |
| Deployment | Not running: replaced by purrbrews-containers' fresh stacks on every node (2026-10-13) | purrbrews-containers runbook, 2026-10-13 "Fresh fleet up" |
| Tests / CI | None (no workflows) | no `.github/workflows/` |
| Secrets | Only `*.secrets.env.local.example` placeholders are tracked | `git ls-files` |

## Open points
Kept for the record. None of these get done here.
- purrbrews-containers' Backlog still says "roastery itself joining the fleet; then archive purrBrews-infra".
- [RECOVERY.md](RECOVERY.md), [REINIT_PLAN.md](REINIT_PLAN.md) and [WEEKEND_PLAN.md](WEEKEND_PLAN.md) describe the old seven-node plan, not the running fleet.

## Branches
- None besides `main`.

## Key decisions
- 2026-08-26 · Base node init, source control and the operating model · [runbook](runbook.md)
- 2026-08-27 · Wake-on-LAN for roastery investigated · [runbook](runbook.md)
- 2026-09-15 · Successor repo started: purrbrews-containers ("Repository conventions", its runbook)

## How to resume
Don't resume. Close it out instead:
1. Merge this card.
2. Archive this repository on GitHub (Settings → Archive). The history stays readable.
3. Anything worth reusing (a stack, a fix) goes into purrbrews-containers through a PR there.

## Decisions to remake
- The node roster: silo and ristretto were never built; their roles were folded into the five-node fleet.
- Secrets: SOPS/age files in git gave way to per-node `setup-secrets.sh` with nothing committed.

## Questions for Roastmaster
- Archive now, or after roastery has joined the fleet as the Backlog line says?

## Card history
- 2026-10-29 · First card, written by Claude from the repo at `8a6fe9a` and purrbrews-containers' runbook.
