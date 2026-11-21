#!/bin/bash
# Writes ZFS pool/quota metrics for the node_exporter textfile collector (from cron; reading ZFS needs no root).
# Metric names are consumed by prometheus/rules/nas-storage.yml in the monitor-stack.
set -u
export PATH="$PATH:/usr/sbin:/sbin"   # zpool/zfs are not on PATH for non-root users (TrueNAS)
OUT_DIR="${OUT_DIR:-/var/lib/node_exporter}"
OUT="$OUT_DIR/nas_storage.prom"
TMP=$(mktemp "$OUT_DIR/.nas_storage.XXXXXX") || exit 1
trap 'rm -f "$TMP"' EXIT

{
  echo "# TYPE nas_zpool_health gauge"
  echo "# TYPE nas_zpool_capacity_ratio gauge"
  echo "# TYPE nas_zpool_errors_read_total gauge"
  echo "# TYPE nas_zpool_data_errors gauge"
  echo "# TYPE nas_zpool_last_scrub_timestamp_seconds gauge"
  echo "# TYPE nas_zpool_scrub_in_progress gauge"
  echo "# TYPE nas_zfs_dataset_quota_usage_ratio gauge"

  for pool in $(zpool list -H -o name); do
    read -r size alloc health < <(zpool list -Hp -o size,allocated,health "$pool")
    case "$health" in ONLINE) code=0 ;; DEGRADED) code=1 ;; *) code=2 ;; esac
    status=$(zpool status -p "$pool")

    # Pool-level READ/WRITE/CKSUM counters (the table row whose name is the pool)
    read -r r w c < <(awk -v p="$pool" '$1==p && $2 ~ /^[A-Z]+$/ {print $3, $4, $5; exit}' <<<"$status")

    # "errors: 41 data errors, use '-v' for a list" (without -v), absent when clean
    data_errors=$(sed -n 's/^errors: \([0-9][0-9]*\) data errors.*/\1/p' <<<"$status")

    # Last completed scrub: "scan: scrub repaired 0B in 04:59:48 with 0 errors on Sun Jan 11 13:59:50 2026"
    last_scrub=0
    scan=$(grep -E '^\s*scan:' <<<"$status")
    if [[ "$scan" =~ scrub\ repaired.*\ on\ (.+)$ ]]; then
      last_scrub=$(date -d "${BASH_REMATCH[1]}" +%s 2>/dev/null || echo 0)
    fi
    in_progress=0
    [[ "$scan" == *"scrub in progress"* || "$scan" == *"resilver in progress"* ]] && in_progress=1

    echo "nas_zpool_health{pool=\"$pool\"} $code"
    echo "nas_zpool_size_bytes{pool=\"$pool\"} $size"
    echo "nas_zpool_allocated_bytes{pool=\"$pool\"} $alloc"
    awk -v p="$pool" -v a="$alloc" -v s="$size" 'BEGIN {printf "nas_zpool_capacity_ratio{pool=\"%s\"} %.4f\n", p, a/s}'
    echo "nas_zpool_errors_read_total{pool=\"$pool\"} ${r:-0}"
    echo "nas_zpool_errors_write_total{pool=\"$pool\"} ${w:-0}"
    echo "nas_zpool_errors_cksum_total{pool=\"$pool\"} ${c:-0}"
    echo "nas_zpool_data_errors{pool=\"$pool\"} ${data_errors:-0}"
    echo "nas_zpool_last_scrub_timestamp_seconds{pool=\"$pool\"} $last_scrub"
    echo "nas_zpool_scrub_in_progress{pool=\"$pool\"} $in_progress"
  done

  # Datasets with a quota or refquota: usage as a fraction of the limit
  zfs list -Hp -t filesystem -o name,used,referenced,quota,refquota | grep -v '/\.system' | while read -r name used ref quota refquota; do
    if [[ "$quota" != "0" && "$quota" != "-" ]]; then
      awk -v n="$name" -v u="$used" -v q="$quota" 'BEGIN {printf "nas_zfs_dataset_quota_usage_ratio{dataset=\"%s\",type=\"quota\"} %.4f\n", n, u/q}'
    fi
    if [[ "$refquota" != "0" && "$refquota" != "-" ]]; then
      awk -v n="$name" -v u="$ref" -v q="$refquota" 'BEGIN {printf "nas_zfs_dataset_quota_usage_ratio{dataset=\"%s\",type=\"refquota\"} %.4f\n", n, u/q}'
    fi
  done

  echo "# TYPE nas_storage_textfile_timestamp_seconds gauge"
  echo "nas_storage_textfile_timestamp_seconds $(date +%s)"
} >"$TMP"

chmod 0644 "$TMP"
mv "$TMP" "$OUT"
trap - EXIT
