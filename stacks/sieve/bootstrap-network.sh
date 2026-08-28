#!/usr/bin/env bash
#
# bootstrap-network.sh — creates the shared docker network every sieve app
# joins to reach each other (traefik <-> authelia, authelia <-> lldap/redis,
# cloudflared -> traefik). Run once, before bringing any app up. Idempotent.
#
set -euo pipefail

docker network inspect sieve_proxy >/dev/null 2>&1 \
  && echo "sieve_proxy already exists — nothing to do." \
  || { docker network create sieve_proxy; echo "sieve_proxy created."; }
