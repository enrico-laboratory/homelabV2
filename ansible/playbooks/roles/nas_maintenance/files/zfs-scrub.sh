#!/bin/bash
# Usage: zfs-scrub.sh <pool>. Starts a scrub unless one (or a resilver) is already running.
set -eu
pool="$1"
if zpool status "$pool" | grep -qE 'scrub in progress|resilver in progress'; then
  echo "$pool: scrub or resilver already running, skipping"
  exit 0
fi
zpool scrub "$pool"
