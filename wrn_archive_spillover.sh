#!/usr/bin/env bash
# WRN dev.19 WAVE OS archive spillover and move-feasibility AUDIT ONLY.
# No move, copy, deletion, reindex, WAVE service changes, or disk mount changes.
set -Eeuo pipefail
export LC_ALL=C
MODE=${1:---audit}
[[ $# -eq 1 && ( $MODE == --audit || $MODE == --plan-move ) ]] || { echo 'Usage: sudo bash wrn_archive_spillover.sh [--audit|--plan-move] (both read-only)' >&2; exit 2; }
[[ ${EUID:-$(id -u)} == 0 ]] || { echo 'STOP: sudo required' >&2; exit 2; }
DATA=/opt/hanwha/mediaserver/var/data
REPORT_DIR=/home/wave/Downloads/maintenance
[[ -d $REPORT_DIR && ! -L $REPORT_DIR ]] || { echo 'STOP: reports folder unavailable' >&2; exit 1; }
REPORT="$REPORT_DIR/WRN-Archive-Spillover_$(date -u +%Y%m%dT%H%M%SZ)_$$.txt"
: > "$REPORT" && chmod 644 "$REPORT"
exec > >(tee -a "$REPORT") 2>&1
printf '=== WAVE OS SPILLOVER AUDIT (READ-ONLY; %s) ===\n' "$MODE"
echo "Report: $REPORT"
[[ -d $DATA && ! -L $DATA ]] || { echo "NOTICE: WAVE data root not present as regular directory: $DATA"; exit 0; }
osdev=$(stat -c %d /)
datadev=$(stat -c %d "$DATA")
if [[ $datadev != "$osdev" ]]; then
  echo 'STOP: WAVE data root not on OS filesystem; do not assume spillover source'; exit 1
fi
shopt -s nullglob
found=0
bytes=0
for server in "$DATA"/*; do
  [[ -d $server && ! -L $server ]] || continue
  [[ $(stat -c %d "$server") == "$osdev" ]] || { echo "SKIP: not on OS filesystem $server"; continue; }
  for quality in hi_quality low_quality; do
    qpath="$server/$quality"
    [[ -d $qpath && ! -L $qpath ]] || continue
    [[ $(stat -c %d "$qpath") == "$osdev" ]] || continue
    while IFS= read -r -d '' year; do
      [[ -d $year && ! -L $year && $(stat -c %d "$year") == "$osdev" ]] || continue
      # Calculate allocated bytes using du -s -B1 confined to the source filesystem.
      size=$(du -sx -B1 "$year" 2>/dev/null | awk 'NR==1 {print $1}')
      [[ $size =~ ^[0-9]+$ ]] || { echo "WARNING: cannot size $year"; continue; }
      printf 'OS RECORDINGS: %12s bytes  %s\n' "$size" "$year"
      (( found+=1 )); bytes=$((bytes+size))
    done < <(find "$qpath" -xdev -mindepth 2 -maxdepth 2 -type d -name '20[0-9][0-9]' -print0 2>/dev/null)
  done
done
printf 'TOTAL: %s dated directories; %s allocated bytes on OS filesystem\n' "$found" "$bytes"
echo '=== POSSIBLE DESTINATIONS (INFORMATIONAL ONLY) ==='
for mp in /mnt/sda /mnt/sdb /mnt/sdc /mnt/sdd; do
  if ! findmnt -rn -M "$mp" >/dev/null 2>&1; then echo "$mp: not mounted"; continue; fi
  fs=$(findmnt -rn -M "$mp" -o FSTYPE)
  mountopts=$(findmnt -rn -M "$mp" -o OPTIONS)
  [[ $fs == ext4 && ,$mountopts, == *,rw,* ]] || { echo "$mp: NOT ELIGIBLE (not rw ext4)"; continue; }
  # Insist destination really is a different mounted filesystem from /.
  [[ $(stat -c %d "$mp") != "$osdev" ]] || { echo "$mp: NOT ELIGIBLE (same OS filesystem)"; continue; }
  read -r total avail < <(df -B1 --output=size,avail "$mp" | awk 'NR==2 {print $1,$2}')
  [[ $total =~ ^[0-9]+$ && $avail =~ ^[0-9]+$ ]] || { echo "$mp: cannot determine free space"; continue; }
  # Conservative extra reserve; VMS can need considerably more and recycle constantly.
  reserve=$((50 * 1024 * 1024 * 1024))
  headroom=$(( avail > reserve ? avail - reserve : 0 ))
  printf '%s: free=%s bytes  conservative non-VMS headroom=%s bytes' "$mp" "$avail" "$headroom"
  if (( bytes > 0 && bytes <= headroom )); then echo '  CAPACITY MAY BE SUFFICIENT (NOT APPROVED FOR MOVE)';
  elif (( bytes > 0 )); then echo '  INSUFFICIENT HEADROOM';
  else echo '  no OS recording data identified'; fi
done
if (( found )); then
  cat <<'WARNING'
WARNING: Video chunks are indexed by WAVE to a physical storage path.
Moving or copying chunks can make timeline video unavailable until a supported
archive reindex is performed. A running WAVE server may recycle files during a
copy; full destination disks may recycle old footage to maintain recordings.
Do NOT move, delete, overwrite or reindex from this script. Coordinate with
Hanwha/WAVE support, preserve existing footage, confirm destination path format
and free-space headroom, arrange a maintenance window, and validate playback.
WARNING
else
  echo 'No standard dated hi_quality/low_quality OS video folders detected; other WAVE metadata and unrecognized archive layouts are not classified.'
fi
if [[ $MODE == --plan-move ]]; then
  echo 'PLAN ONLY: dev.19 intentionally does not implement migration or select a destination.'
fi
echo 'AUDIT COMPLETE: no media files modified.'
