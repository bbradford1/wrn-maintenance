#!/usr/bin/env bash
# WRN Remaining OS Space v0.1.0 - read-only inspection, supervised field testing.
# Only writes this diagnostic report in the operator Downloads folder.
set -u
export LC_ALL=C
umask 077
[[ $# -eq 0 || ( $# -eq 1 && "$1" == '--diagnose' ) ]] || { echo 'Usage: sudo bash wrn_remaining_os_space.sh [--diagnose]' >&2; exit 2; }
(( EUID == 0 )) || { echo 'Run with sudo' >&2; exit 2; }
[[ -r /etc/os-release ]] || exit 2
. /etc/os-release
[[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 22.04 ]] || { echo 'Ubuntu 22.04 required' >&2; exit 2; }
OUTDIR=/home/wave/Downloads/maintenance
[[ -d "$OUTDIR" && ! -L "$OUTDIR" ]] || { echo "STOP: $OUTDIR unavailable" >&2; exit 2; }
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT="$OUTDIR/WRN-Remaining-OS-Space_${STAMP}_$$.txt"
( set -C; : > "$REPORT" ) || exit 2
chmod 600 "$REPORT"
section(){ printf '\n===== %s =====\n' "$1" >> "$REPORT"; }
run(){ local label="$1" seconds="$2"; shift 2; section "$label"; timeout -k 2s "${seconds}s" "$@" >> "$REPORT" 2>&1; local rc=$?; if ((rc)); then echo "[command status=$rc; information may be incomplete]" >> "$REPORT"; fi; }
section 'IDENTIFICATION AND LIMITS'
printf 'UTC: %s\nHostname: %s\nUbuntu: %s\nRead-only system inspection. No deletion, package commands, service operations or mount operations.\n' "$(date -u -Is)" "$(hostname -s)" "${PRETTY_NAME:-unknown}" >> "$REPORT"
run 'OS FILESYSTEM' 8 df -hT /
run 'FILESYSTEM AND MOUNT MAP' 10 lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS,RO
run 'ARCHIVE MOUNT' 8 bash -c 'findmnt -M /mnt/sda || echo "NOT MOUNTED"; findmnt -T /opt/hanwha/mediaserver/var/data || true'
run 'WAVE SERVICE' 8 bash -c 'systemctl is-active hanwha-mediaserver.service; systemctl show hanwha-mediaserver.service -p ActiveEnterTimestamp -p NRestarts'
run 'ROOT DIRECTORIES >= 1GiB ACTUAL DISK BLOCKS' 45 bash -c 'du -x -B1 -d1 / 2>/dev/null | awk '\''$1>=1073741824 {printf "%.2f GiB %s\n",$1/1073741824,$2}'\'' | sort -nr'
run 'VAR OPT HOME SUBDIRECTORIES >= 1GiB' 60 bash -c 'for d in /var /opt /home; do du -x -B1 -d2 "$d" 2>/dev/null; done | awk '\''$1>=1073741824 {printf "%.2f GiB %s\n",$1/1073741824,$2}'\'' | sort -nr | head -80'
run 'LARGE OS-RESIDENT FILES >= 1GiB ALLOCATED (NO CONTENT READ)' 60 bash -c 'find /var /opt /home -xdev -type f -printf "%b %s %TY-%Tm-%Td %p\n" 2>/dev/null | awk '\''$1*512>=1073741824 {printf "%.2f GiB allocated / %.2f GiB apparent / %s %s\n",$1*512/1073741824,$2/1073741824,$3,$4}'\'' | sort -nr | head -80'
run 'CORE DUMPS (METADATA ONLY, INCLUDING SPARSE FILES)' 30 bash -c 'find /home/wave -maxdepth 2 -type f \( -name core -o -name "core.*" \) -print0 2>/dev/null | xargs -0 -r stat -c "path=%n owner=%U modified=%y apparent_bytes=%s allocated_blocks_512=%b inode=%i"'
run 'CORE FILE TYPES (NO FILE CONTENT DUMP)' 30 bash -c 'find /home/wave -maxdepth 1 -type f \( -name core -o -name "core.*" \) -print0 2>/dev/null | xargs -0 -r file --'
run 'SNAP STORAGE' 15 bash -c 'for p in /var/lib/snapd /var/lib/snapd/seed /var/lib/snapd/snaps /var/snap /home/wave/snap; do [[ ! -e "$p" ]] || du -shx "$p" 2>&1; done; if command -v snap >/dev/null; then timeout -k 2s 8s snap list --all || echo "SNAP INVENTORY UNAVAILABLE"; fi'
run 'PACKAGE STATE (NO CHANGES)' 12 bash -c 'dpkg-query -W snapd firefox google-chrome-stable gdm3 gnome-shell ubuntu-desktop 2>&1 || true; dpkg --audit'
run 'WAVE DATA AND DATABASE SIZE (NEVER DELETE)' 20 bash -c 'for p in /opt/hanwha/mediaserver/var/data /opt/hanwha/mediaserver/var; do [[ ! -d "$p" ]] || { du -shx "$p" 2>&1; findmnt -T "$p" -o TARGET,SOURCE,FSTYPE; }; done; find /opt/hanwha/mediaserver/var -xdev -type f \( -name "*.sqlite-wal" -o -name "*.sqlite" -o -name "*.nxdb" \) -size +1023M -printf "%s bytes %p\n" 2>/dev/null | head -40'
run 'LARGE LOGS AND JOURNAL' 16 bash -c 'journalctl --disk-usage; find /var/log -xdev -type f -size +1023M -printf "%s bytes %p\n" 2>/dev/null'
section 'SAFETY SUMMARY'
printf 'REPORT ONLY. Do not delete SQLite/WAL, WAVE recordings, indexes, or metadata.\nDo not remove Snap automatically. Archive and recording health must be verified in WAVE client.\n' >> "$REPORT"
chown wave:wave "$REPORT" 2>/dev/null || chmod 644 "$REPORT"
chmod 640 "$REPORT" 2>/dev/null || true
printf 'READ-ONLY WRN OS space report saved:\n%s\n' "$REPORT"
