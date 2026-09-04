#!/usr/bin/env bash
#
# mirror.sh -- cellar's local secondary backup mirror. Confirmed 2026-09-03:
# no well-maintained rsync-in-a-container image exists (every candidate
# found was an unmaintained single-person side project) -- current real
# practice is plain host cron/systemd-timer + rsync directly, not
# containerized. This is that: no docker-compose.yml in this directory,
# deliberately.
#
# Runs `rsync -a` (no --delete) from each source into its own subfolder
# under $MIRROR_DEST -- append-only growth, not synced deletion. This is
# explicitly cellar's SECOND copy alongside a separate household NAS
# (Section 4.3) -- if this used --delete, a source-side deletion (bug,
# mistake, ransomware-style event) would propagate here too and destroy
# the only other copy of whatever got deleted in error. Confirmed via
# current homelab backup-strategy guidance this is the right call for a
# secondary mirror specifically (a PRIMARY versioned backup would want
# restic or --link-dest hardlink snapshots instead -- not what this is).
#
# Known gap, not implemented here: no snapshot/rotation (--link-dest) --
# this only ever grows, doesn't prune. Revisit if cellar's HDD fills up
# before a real retention policy gets designed.
#
# Usage: run via the systemd timer in this directory (see
# backup-mirror.timer/.service), or manually: ./mirror.sh
#
set -euo pipefail

MIRROR_DEST="/srv/backup-mirror"
LOG_TAG="cellar-backup-mirror"

log() { logger -t "$LOG_TAG" "$*"; echo "$*"; }

# One rsync call per source. SSH keys for pulling from other nodes need to
# already be set up (ssh-copy-id from cellar to each source, as the user
# this script runs as) -- not automated here, a one-time manual step.
mirror_source() {
  local label="$1" src="$2"
  log "mirroring ${label}: ${src} -> ${MIRROR_DEST}/${label}/"
  mkdir -p "${MIRROR_DEST}/${label}"
  rsync -a --stats "${src}" "${MIRROR_DEST}/${label}/" 2>&1 | tee -a "/var/log/${LOG_TAG}.log"
}

# --- Sources -------------------------------------------------------------
# One line per node/path worth mirroring. REPLACE_ME_* placeholders --
# fill in real hostnames/paths once each node's own /srv/data is actually
# populated with something worth a second copy. Not run against anything
# yet -- percolator/mochaPot don't have real data in them as of
# 2026-09-03.
#
#   mirror_source "sieve"      "barista@REPLACE_ME_SIEVE_LAN_IP:/srv/data/"
#   mirror_source "silo"       "barista@REPLACE_ME_SILO_LAN_IP:/srv/data/"
#   mirror_source "percolator" "barista@REPLACE_ME_PERCOLATOR_LAN_IP:/srv/data/"
#   mirror_source "mochapot"   "barista@REPLACE_ME_MOCHAPOT_LAN_IP:/srv/data/"
#
# cellar's own archive shares (/srv/media on this same host) don't need
# an rsync hop -- consider a periodic local snapshot of those separately
# if that's ever wanted; out of scope for this script, which is about
# pulling FROM other nodes.
# --------------------------------------------------------------------------

log "nothing configured yet -- see the Sources section above"
