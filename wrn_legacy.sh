#!/usr/bin/env bash
# Hanwha WRN Legacy Utility 1.0.0-dev.1 - DIAGNOSTICS ONLY
# Ubuntu 18.04. Does not vacuum/delete logs, change services, edit fstab, or restart WAVE.
# Usage: sudo bash wrn_legacy.sh [--diagnose|--version|--help]
set -u
export LC_ALL=C
umask 077
VERSION='1.0.0-dev.1'
MODE="${1:---diagnose}"
case "$MODE" in
  --version) [[ $# -eq 1 ]] || exit 2; printf '%s\n' "$VERSION"; exit 0 ;;
  --help|-h) printf 'WRN Legacy %s (read-only development build)\nUsage: sudo bash wrn_legacy.sh [--diagnose|--version|--help]\n' "$VERSION"; exit 0 ;;
  --diagnose) [[ $# -le 1 ]] || { echo 'Unexpected arguments' >&2; exit 2; } ;;
  *) echo 'Only read-only --diagnose is available in this development build.' >&2; exit 2 ;;
esac
(( EUID == 0 )) || { echo 'ERROR: run with sudo' >&2; exit 2; }
[[ -r /etc/os-release ]] || { echo 'ERROR: cannot detect OS' >&2; exit 2; }
# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 18.04 ]] || {
  echo "STOP: Ubuntu 18.04 required (found ${PRETTY_NAME:-unknown}). No report written." >&2
  exit 2
}
for cmd in timeout df du journalctl findmnt systemctl awk date hostname lsblk; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: missing $cmd" >&2; exit 2; }
done
OWNER="${SUDO_USER:-root}"
OWNER_HOME="$(getent passwd "$OWNER" | awk -F: 'NR==1 {print $6}')"
[[ -n "$OWNER_HOME" ]] || OWNER_HOME=/root
OUTDIR="${WRN_REPORT_DIR:-$OWNER_HOME/Downloads/maintenance}"
[[ -d "$OUTDIR" && ! -L "$OUTDIR" ]] || { echo "ERROR: report directory unavailable: $OUTDIR" >&2; exit 2; }
HOST="$(hostname -s | tr -cd '[:alnum:]_.-' | cut -c1-48)"
HOST="${HOST:-unknown}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT="$OUTDIR/WRN-Legacy-Diagnostics_${HOST}_${STAMP}_$$.txt"
( set -o noclobber; : > "$REPORT" ) || { echo 'ERROR: unable to create report' >&2; exit 1; }
chmod 600 "$REPORT"
section() { printf '\n===== %s =====\n' "$1" >> "$REPORT"; }
run() {
  local label="$1" seconds="$2"; shift 2
  section "$label"
  timeout -k 2s "${seconds}s" "$@" >> "$REPORT" 2>&1
  local rc=$?
  if (( rc != 0 )); then printf '[command exit status %d; incomplete or unavailable]\n' "$rc" >> "$REPORT"; fi
}
section 'REPORT INFORMATION'
printf 'WRN Legacy: %s\nMode: READ ONLY\nOS: %s\nUTC: %s\nHostname: %s\n' "$VERSION" "$PRETTY_NAME" "$(date -u -Is)" "$HOST" >> "$REPORT"
run 'OS STORAGE' 8 df -hT / /var/log
run 'JOURNAL UTILIZATION' 8 journalctl --disk-usage
run 'JOURNAL CONFIGURATION' 6 bash -c 'for f in /etc/systemd/journald.conf /etc/systemd/journald.conf.d/*.conf; do [[ -f "$f" ]] && { printf "%s\n" "--- $f ---"; grep -E "^[[:space:]]*(Storage|SystemMaxUse|SystemKeepFree|RuntimeMaxUse|MaxRetentionSec)=" "$f" || true; }; done; true'
run 'LARGE LOG FILES (>= 1 GiB)' 12 find /var/log -xdev -type f -size +1023M -printf '%s bytes %p\n'
run 'LOG FOLDER USAGE' 12 du -shx /var/log
run 'WAVE SERVICE STATE' 6 bash -c 'systemctl is-active hanwha-mediaserver.service; systemctl show hanwha-mediaserver.service -p MainPID -p ActiveEnterTimestamp -p NRestarts'
run 'BLOCK DEVICE AND MOUNT INVENTORY' 8 lsblk -o NAME,SIZE,MODEL,FSTYPE,UUID,MOUNTPOINT,RO
run 'ARCHIVE MOUNT STATUS' 6 bash -c 'if findmnt -rn -M /mnt/sda; then df -hT /mnt/sda; else echo "Archive not mounted at /mnt/sda; no mount attempted"; fi'
run 'FSTAB ENTRIES AND DUPLICATES' 6 awk '
  $1 !~ /^#/ && NF>=4 {
    if ($2 ~ /^\/mnt\/sd[a-z]$/) printf "Archive line %d: %s\n",NR,$0;
    mounts[$2]++;
  }
  END { for(m in mounts) if(mounts[m]>1) printf "WARNING: repeated mount point %s (%d entries)\n",m,mounts[m]; }
' /etc/fstab
run 'OS TOP DIRECTORIES (>= 1 GiB)' 18 bash -c 'du -xhd1 / 2>/dev/null | awk '\''$1 ~ /G$/ && $1+0>=1 || $1 ~ /T$/ { print }'\'' | sort -h'
run 'WAVE FALLBACK STORAGE SIZE (NO DELETION)' 15 bash -c 'p=/opt/hanwha/mediaserver/var/data; if [[ -d "$p" ]]; then du -shx "$p"; findmnt -T "$p" -o TARGET,SOURCE,FSTYPE; else echo "WAVE data directory missing"; fi'
section 'SAFETY AND LIMITATIONS'
cat >> "$REPORT" <<'NOTES'
Read-only diagnostic build. No journald stop/start, log vacuum, journal deletion, cron changes,
WAVE restart, network service changes, mount actions, repairs, or reboot.
SMART health and filesystem checks are not performed by this legacy build.
An absent/healthy mount or active service does not prove WAVE is successfully recording.
Older journal entries may be missing due to prior cleanup. Verify recording in WAVE client.
Report can contain identifying system details; do not post publicly.
NOTES
if [[ "$OWNER" != root ]]; then chown "$OWNER" "$REPORT" 2>/dev/null || true; fi
printf 'WRN Legacy %s: read-only diagnostic report created\n%s\nNo maintenance performed.\n' "$VERSION" "$REPORT"
