#!/usr/bin/env bash
# WRN read-only field inventory, v0.1.0 (2026-11-06)
# Compatible with Ubuntu 18.04 and 22.04; no maintenance or filesystem modifications.
set -u
export LC_ALL=C
umask 077

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
HOST=$(hostname -s 2>/dev/null || printf 'unknown')
HOST=${HOST//[^A-Za-z0-9_.-]/_}
BASE="${HOME:-/tmp}"
if [[ $(id -u) -eq 0 && -d /home/wave ]]; then BASE=/home/wave; fi
if [[ ! -d "$BASE" || ! -w "$BASE" ]]; then BASE=/tmp; fi
REPORT="$BASE/WRN-Inspection-${HOST}-${STAMP}.txt"
if ! ( : > "$REPORT" ) 2>/dev/null; then
  REPORT="/tmp/WRN-Inspection-${HOST}-${STAMP}.txt"
  : > "$REPORT" || { echo 'ERROR: Cannot save report'; exit 1; }
fi
chmod 644 "$REPORT" 2>/dev/null || true
# Keep the output visible while also saving it; never allow failures to stop later checks.
exec > >(tee -a "$REPORT") 2>&1

section() { printf '\n========== %s ==========\n' "$1"; }
run() {
  printf '\n$'; printf ' %q' "$@"; printf '\n'
  if command -v timeout >/dev/null 2>&1; then timeout 20 "$@" 2>&1 || printf '[NOTE] Command exited nonzero or timed out: %s\n' "$1"
  else "$@" 2>&1 || printf '[NOTE] Command exited nonzero: %s\n' "$1"; fi
}

section 'WRN READ-ONLY INSPECTION v0.1.0'
printf 'UTC: %s\nHost: %s\nReport: %s\n' "$STAMP" "$HOST" "$REPORT"
printf 'No maintenance, package changes, mounting, service restarts, or reboot.\n'
section 'OPERATING SYSTEM'
if [[ -r /etc/os-release ]]; then grep -E '^(PRETTY_NAME|ID|VERSION_ID)=' /etc/os-release; fi
run uname -a
run uptime
section 'ROOT FILESYSTEM'
run df -hT /
run df -i /
section 'STORAGE BLOCK DEVICES'
if command -v lsblk >/dev/null 2>&1; then
  run lsblk -e 7 -o NAME,TYPE,SIZE,MODEL,FSTYPE,UUID,MOUNTPOINT
else echo 'NOT TESTED: lsblk unavailable'; fi
section 'ACTIVE MOUNTS'
if command -v findmnt >/dev/null 2>&1; then
  findmnt -rn -o SOURCE,TARGET,FSTYPE,OPTIONS | awk '$2=="/" || $2 ~ /^\/mnt\// || $2 ~ /^\/opt\/hanwha\//'
else echo 'NOT TESTED: findmnt unavailable'; fi
section 'ARCHIVE FSTAB ENTRIES (READ ONLY)'
if [[ -r /etc/fstab ]]; then
  awk 'BEGIN{print "SOURCE TARGET TYPE OPTIONS"} /^[[:space:]]*#/ || NF<4 {next} {if ($2 ~ /^\/mnt\// || tolower($2) ~ /hanwha|wave/ || $1 ~ /^UUID=/ || $1 ~ /^\/dev\/sd/) print $1,$2,$3,$4}' /etc/fstab
else echo 'NOT TESTED: Cannot read fstab'; fi
section 'WAVE SERVICE'
if command -v systemctl >/dev/null 2>&1; then
  run systemctl is-active hanwha-mediaserver.service
  run systemctl is-enabled hanwha-mediaserver.service
  run systemctl show hanwha-mediaserver.service -p ActiveState -p SubState -p UnitFileState -p ExecMainStartTimestamp
else echo 'NOT TESTED: systemctl unavailable'; fi
section 'WAVE DATA DIRECTORY (METADATA ONLY)'
for d in /opt/hanwha/mediaserver/var/data /mnt/sda /mnt/sda1 /mnt/sdb /mnt/sdb1 /mnt/sdc /mnt/sdc1 /mnt/sdd /mnt/sdd1; do
  if [[ -d "$d" ]]; then
    printf 'Directory: %s\n' "$d"
    if command -v findmnt >/dev/null 2>&1; then findmnt -T "$d" -n -o SOURCE,TARGET,FSTYPE 2>&1 || true; fi
  fi
done
section 'JOURNAL STORAGE'
if command -v journalctl >/dev/null 2>&1; then run journalctl --disk-usage; else echo 'NOT TESTED: journalctl unavailable'; fi
section 'JOURNAL CONFIGURATION'
if [[ -r /etc/systemd/journald.conf ]]; then
  grep -HnE '^[[:space:]]*(Storage|SystemMaxUse|SystemKeepFree|RuntimeMaxUse)=' /etc/systemd/journald.conf || true
fi
if [[ -d /etc/systemd/journald.conf.d ]]; then
  for f in /etc/systemd/journald.conf.d/*.conf; do
    [[ -f "$f" && -r "$f" ]] || continue
    grep -HnE '^[[:space:]]*(Storage|SystemMaxUse|SystemKeepFree|RuntimeMaxUse)=' "$f" || true
  done
fi
section 'SNAP INVENTORY'
if command -v snap >/dev/null 2>&1; then
  run snap list --all
  section 'SNAP TRANSACTIONS'
  run snap changes
else echo 'Snap not installed'; fi
section 'SYSTEMD GLOBAL TIMEOUT SETTINGS'
for f in /etc/systemd/system.conf /etc/systemd/system.conf.d/*.conf; do
  [[ -f "$f" && -r "$f" ]] || continue
  grep -HnE '^[[:space:]]*Default(TimeoutStartSec|TimeoutStopSec)=' "$f" || true
done
section 'DISK HEALTH TOOL AVAILABILITY'
if command -v smartctl >/dev/null 2>&1; then echo 'smartctl available (SMART probing intentionally omitted; may require device-specific selection)'; else echo 'smartctl not installed'; fi
section 'FINAL SUMMARY'
run df -hT /
if command -v systemctl >/dev/null 2>&1; then run systemctl is-active hanwha-mediaserver.service; fi
printf '\nINSPECTION COMPLETED. Report: %s\n' "$REPORT"
printf 'Review required: inspection does not prove cameras are recording or playback is working.\n'
