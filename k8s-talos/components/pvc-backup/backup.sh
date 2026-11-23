#!/bin/sh
# Generic PVC backup to TrueNAS (restic over NFS), used by the <app>-pvc-backup CronJobs.
#
#   /data   : the app PVC(s), mounted read-write (sqlite3 needs to write the -shm file of WAL databases)
#   /dump   : emptyDir; SQLite snapshots are written here, an init container may add dumps (pg_dump)
#   /repos  : NFS export backup-pool-2/k8s-pvc; the restic repo is /repos/$APP
#
# Env: APP (required, repo name and restic --host), RESTIC_PASSWORD (required),
#      EXCLUDES (optional, one restic exclude pattern per line).
#
# SQLite files are never read live: each one is copied with the online backup API (.backup) to
# /dump<original path> and the live file (plus -wal/-shm) is excluded. Restore: copy
# /dump/data/<path> back over /data/<path> with the app stopped.
set -eu

: "${APP:?APP is required}"
export RESTIC_REPOSITORY="/repos/$APP"
export RESTIC_CACHE_DIR=/cache

excludes=/tmp/excludes
printf '%s\n' 'lost+found' > "$excludes"
printf '%s\n' "${EXCLUDES:-}" | sed '/^[[:space:]]*$/d' >> "$excludes"

targets=/dump
if [ -d /data ]; then
  targets="/data /dump"
  apk add --no-cache sqlite >/dev/null
  find /data -type f \( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) > /tmp/dbs
  while read -r db; do
    head -c 15 "$db" | grep -q 'SQLite format 3' || continue
    mkdir -p "$(dirname "/dump$db")"
    echo "sqlite snapshot: $db"
    sqlite3 "$db" ".backup '/dump$db'"
    # single self-contained file (no -wal/-shm next to the copy), then verify it
    sqlite3 "/dump$db" 'PRAGMA journal_mode=DELETE;' >/dev/null
    sqlite3 "/dump$db" 'PRAGMA integrity_check;' | grep -qx ok
    rm -f "/dump$db-wal" "/dump$db-shm"
    printf '%s\n' "$db" "$db-wal" "$db-shm" "$db-journal" >> "$excludes"
  done < /tmp/dbs
fi

restic cat config >/dev/null 2>&1 || restic init
# concurrencyPolicy is Forbid, so any lock left here is stale (a killed pod); unlock removes only stale ones
restic unlock || true
# shellcheck disable=SC2086 # $targets is a list of paths
restic backup $targets --host "$APP" --exclude-file "$excludes"
restic forget --host "$APP" --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
