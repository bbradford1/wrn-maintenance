#!/usr/bin/env bash
# Hanwha WRN Maintenance 1.0.0-dev.1 (DIAGNOSTICS ONLY)
# Derived from WRN diagnostic collector 1.6.1; NOT an approved production maintenance release.
# This development build performs observations and creates a local report only.
# No repairs, service control, mount changes, reboot, or automatic cleanup.
# Usage: sudo bash wrn_maintenance.sh [--diagnose|--help|--version]
VERSION='1.0.0-dev.1'
case "${1:---diagnose}" in
  --diagnose) [[ $# -le 1 ]] || { echo 'Unexpected arguments' >&2; exit 2; } ;;
  --help|-h) printf 'WRN Maintenance %s (diagnostics-only development build)\nUsage: sudo bash wrn_maintenance.sh [--diagnose|--help|--version]\n' "$VERSION"; exit 0 ;;
  --version) printf '%s\n' "$VERSION"; exit 0 ;;
  *) echo 'Only --diagnose is enabled in this development build.' >&2; exit 2 ;;
esac
set -u
export LC_ALL=C
umask 077

if (( EUID != 0 )); then echo 'ERROR: run with sudo for complete system logs and SMART data.' >&2; exit 1; fi
OPERATOR="${SUDO_USER:-root}"
OP_HOME="$(getent passwd "$OPERATOR" | cut -d: -f6)"
[[ -n "$OP_HOME" ]] || OP_HOME=/root
OUTDIR="${WRN_REPORT_DIR:-$OP_HOME/Downloads}"
if [[ ! -d "$OUTDIR" ]]; then echo "ERROR: report directory not found: $OUTDIR" >&2; exit 1; fi
HOST="$(hostname -s 2>/dev/null | tr -cd '[:alnum:]_.-' | cut -c1-48)"
HOST="${HOST:-unknown}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT="$OUTDIR/WRN-Diagnostics_${HOST}_${STAMP}_$$.txt"
: > "$REPORT" || exit 1
chmod 600 "$REPORT"

section() { printf '\n===== %s =====\n' "$1" >> "$REPORT"; }
run() {
  local label="$1" duration="$2"; shift 2
  section "$label"
  timeout -k 2s "${duration}s" "$@" >> "$REPORT" 2>&1
  local result=$?
  if (( result != 0 )); then printf '[command exit status: %d; output may be incomplete]\n' "$result" >> "$REPORT"; fi
}

# Resolve the archive by mounted source, fstab UUID, or by a single detected large ext4 disk.
# Do not assume that /dev/sda is the correct disk on every WRN.
ARCHIVE_MOUNT=/mnt/sda
ARCHIVE_DEV=''
ARCHIVE_MATCH=''
mounted_source="$(findmnt -rn -M "$ARCHIVE_MOUNT" -o SOURCE 2>/dev/null || true)"
if [[ -n "$mounted_source" && -b "$mounted_source" ]]; then
  ARCHIVE_DEV="$(readlink -f "$mounted_source")"; ARCHIVE_MATCH='mounted source'
else
  fstab_spec="$(awk '$1 !~ /^#/ && $2=="/mnt/sda" {print $1; exit}' /etc/fstab 2>/dev/null)"
  if [[ -n "$fstab_spec" ]]; then
    case "$fstab_spec" in
      UUID=*) ARCHIVE_DEV="$(blkid -U "${fstab_spec#UUID=}" 2>/dev/null || true)" ;;
      LABEL=*) ARCHIVE_DEV="$(blkid -L "${fstab_spec#LABEL=}" 2>/dev/null || true)" ;;
      /dev/*) [[ -b "$fstab_spec" ]] && ARCHIVE_DEV="$(readlink -f "$fstab_spec")" ;;
    esac
    if [[ -n "$ARCHIVE_DEV" ]]; then ARCHIVE_MATCH='fstab resolution'; fi
  fi
fi
if [[ -z "$ARCHIVE_DEV" ]]; then
  mapfile -t candidates < <(lsblk -bpnro NAME,SIZE,FSTYPE,TYPE 2>/dev/null | awk '$3=="ext4" && $2>=1000000000000 && ($4=="disk" || $4=="part") {print $1}')
  if (( ${#candidates[@]} == 1 )); then ARCHIVE_DEV="${candidates[0]}"; ARCHIVE_MATCH='unique large ext4 device'; fi
fi
if [[ -n "$ARCHIVE_DEV" && ! -b "$ARCHIVE_DEV" ]]; then ARCHIVE_DEV=''; ARCHIVE_MATCH=''; fi
ARCHIVE_FS=''
[[ -n "$ARCHIVE_DEV" ]] && ARCHIVE_FS="$(lsblk -dnro FSTYPE "$ARCHIVE_DEV" 2>/dev/null | head -1)"
ARCHIVE_MOUNTED='NO'
if findmnt -rn -M "$ARCHIVE_MOUNT" >/dev/null 2>&1; then ARCHIVE_MOUNTED='YES'; fi

section 'REPORT INFORMATION'
printf 'UTC: %s\nHostname: %s\nCollector: WRN Maintenance 1.0.0-dev.1 diagnostics-only\nOperator: %s\nMode: READ-ONLY\nArchive selected: %s\nSelection method: %s\nArchive mounted at /mnt/sda: %s\n' "$(date -u -Is)" "$HOST" "$OPERATOR" "${ARCHIVE_DEV:-UNRESOLVED}" "${ARCHIVE_MATCH:-not determined}" "$ARCHIVE_MOUNTED" >> "$REPORT"
run 'OS, KERNEL, TIME, UPTIME' 5 bash -c 'grep -E "^(PRETTY_NAME|VERSION_ID)=" /etc/os-release; printf "Kernel: "; uname -r; printf "Local time: "; date -Is; printf "Boot: "; uptime -s; uptime -p'
run 'OS DISK CAPACITY' 5 df -hT /
run 'OS JOURNAL UTILIZATION (READ-ONLY)' 8 bash -c 'journalctl --disk-usage 2>&1; for p in /var/log/journal /run/log/journal; do if [[ -d "$p" ]]; then du -sh "$p" 2>&1; else echo "$p: not present"; fi; done'
run 'LOG AND WAVE DIRECTORY CAPACITY (READ-ONLY)' 12 bash -c 'for p in /var/log /opt/hanwha/mediaserver/var/log /opt/hanwha/mediaserver/var/data; do if [[ -d "$p" ]]; then du -shx "$p" 2>&1; fi; done; find /var/log -xdev -type f -size +100M -printf "%s bytes %p\n" 2>/dev/null | sort -rn | head -15'
run 'WAVE STORAGE PATH AND THRESHOLD CONTEXT' 8 bash -c 'df -hT / /opt/hanwha/mediaserver/var/data 2>&1; findmnt -T /opt/hanwha/mediaserver/var/data -o TARGET,SOURCE,FSTYPE,OPTIONS 2>&1'
run 'BLOCK DEVICES / MODEL / UUID / MOUNTS' 6 lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN,FSTYPE,UUID,MOUNTPOINTS,RO
run 'ARCHIVE MOUNT AND SPACE' 5 bash -c 'if findmnt -rn -M /mnt/sda; then df -hT /mnt/sda; else echo "NOT MOUNTED at /mnt/sda (archive df skipped; /mnt/sda may reside on OS filesystem)"; fi'
run 'ARCHIVE FSTAB ENTRY' 5 awk '$2=="/mnt/sda" && $1 !~ /^#/ {print}' /etc/fstab
run 'FSTAB DUPLICATE AND TIMEOUT AUDIT (READ-ONLY)' 5 awk '
  $1 !~ /^#/ && NF>=4 {
    mounts[$2]++; devices[$1]++;
    if ($2 ~ /^\/mnt\/sd[a-z]$/) {
      printf "ARCHIVE_ENTRY line=%d device=%s mount=%s options=%s\n", NR,$1,$2,$4;
      if ($1 ~ /^\/dev\/sd[a-z]$/) print "WARNING: volatile /dev/sdX naming";
      if ($4 ~ /x-systemd.device-timeout=5([,s]|$)/) print "WARNING: 5-second device timeout";
    }
  }
  END {
    for (m in mounts) if (mounts[m]>1) printf "WARNING: duplicate mountpoint %s count=%d\n",m,mounts[m];
    for (d in devices) if (d ~ /^(UUID=|LABEL=|\/dev\/)/ && devices[d]>1) printf "REVIEW: repeated source %s count=%d\n",d,devices[d];
  }
' /etc/fstab
run 'EXPECTED ARCHIVE DEVICE PRESENCE (READ-ONLY)' 5 bash -c 'for d in /dev/sda /dev/sdb /dev/sdc /dev/sdd; do if [[ -b "$d" ]]; then echo "PRESENT: $d"; else echo "ABSENT: $d"; fi; done'
run 'SYSTEMD ARCHIVE MOUNT STATE' 5 systemctl show mnt-sda.mount -p LoadState -p ActiveState -p Result -p What -p Where -p TimeoutUSec -p ActiveEnterTimestamp
run 'FSTAB DEVICE MATCH AND PERSISTENCE' 5 bash -c 'sed -n "/[[:space:]]\/mnt\/sda[[:space:]]/p" /etc/fstab; echo "fstab device naming may be unstable if /dev/sdX is used"'
if [[ -n "$ARCHIVE_DEV" ]]; then
  run 'ARCHIVE IDENTITY AND FILESYSTEM SIGNATURE' 7 bash -c 'lsblk -dn -o NAME,SIZE,FSTYPE,UUID,MODEL,SERIAL "$1"; blkid "$1"' _ "$ARCHIVE_DEV"
  if [[ "$ARCHIVE_MOUNTED" == NO && "$ARCHIVE_FS" == ext4 ]] && ! findmnt -rn -S "$ARCHIVE_DEV" >/dev/null 2>&1; then
    run 'EXT4 SUPERBLOCK METADATA (UNMOUNTED ONLY; NO REPAIR)' 9 bash -c 'tune2fs -l "$1" | grep -Ei "Filesystem (state|features)|Journal inode|Last (mount|write) time|Last checked|Mount count|error|Lifetime writes"' _ "$ARCHIVE_DEV"
  else
    section 'EXT4 SUPERBLOCK METADATA'
    printf 'Skipped: mounted=%s, detected filesystem=%s. Avoiding ambiguous live recovery-flag interpretation.\n' "$ARCHIVE_MOUNTED" "${ARCHIVE_FS:-unknown}" >> "$REPORT"
  fi
else
  section 'ARCHIVE IDENTITY'; echo 'Unable to identify archive confidently. NO DEVICE-SPECIFIC CHECKS performed.' >> "$REPORT"
fi
run 'BOOT RECORDS (AVAILABLE JOURNAL)' 6 bash -c 'journalctl --list-boots --no-pager | tail -12; echo "--- last reboot/shutdown events ---"; last -x -n 12 2>&1'
run 'ARCHIVE MOUNT UNIT JOURNAL (AVAILABLE)' 8 journalctl -u mnt-sda.mount --no-pager -n 100 -o short-iso
# Limit journal reading before filtering: avoid traversing months of unrelated system logs.
run 'KERNEL: EXT4 / JBD2 / SATA / I-O / eMMC (LAST 4000 KERNEL LINES)' 12 bash -c 'journalctl -k -n 4000 --no-pager -o short-iso | grep -Ei "EXT4-fs|JBD2|I/O error|Buffer I/O|ata[0-9]|SATA|resetting link|blk_update_request|device timeout|task blocked|sda|mmcblk" | tail -110 || true'
run 'SYSTEM: MOUNT FAILURES / JOURNAL REPLAY / SHUTDOWNS (RECENT 4000)' 12 bash -c 'journalctl -n 4000 --no-pager -o short-iso | grep -Ei "mnt-sda.mount|Failed to mount /mnt/sda|error loading journal|recovering journal|EXT4-fs.*error|systemd-shutdown|Reached target Shutdown|Starting Reboot|Starting Power-Off" | tail -100 || true'
if [[ -n "$ARCHIVE_DEV" ]]; then
  run 'SMART IDENTITY, HEALTH AND KEY ATTRIBUTES (NO SELF-TEST)' 15 bash -c 'if command -v smartctl >/dev/null; then smartctl -i -H -A "$1" 2>&1 | grep -Ei "Device Model|Serial Number|Firmware Version|User Capacity|SATA Version|overall-health|SMART Health Status|Reallocated_Sector|Current_Pending|Offline_Uncorrectable|UDMA_CRC|Power_Cycle|Power_On_Hours|Power-Off_Retract|Command_Timeout|Reported_Uncorrect|Temperature"; else echo "smartctl not installed"; fi' _ "$ARCHIVE_DEV"
  run 'SMART ERROR LOG SUMMARY (NO SELF-TEST)' 12 bash -c 'if command -v smartctl >/dev/null; then smartctl -l error "$1" 2>&1 | tail -35; else echo "smartctl not installed"; fi' _ "$ARCHIVE_DEV"
fi
# WAVE Media Server history: inspect bounded rotated logs, preserving filename and timestamp.
# Never search recording archives or write inside the mediaserver tree.
collect_wave_logs() {
  section 'WAVE MEDIA SERVER STORAGE EVENTS (CLASSIFIED, BOUNDED)'
  local logdir=/opt/hanwha/mediaserver/var/log
  if [[ ! -d "$logdir" ]]; then
    echo 'STATUS: LOG DIRECTORY MISSING' >> "$REPORT"; return
  fi
  local tmpdir sourcef size rc selected=0 skipped=0 warnings=0
  local -a list=()
  tmpdir="$(mktemp -d "$OUTDIR/.wrn-wave-XXXXXX")" || {
    echo 'STATUS: TEMP FILE CREATION FAILED' >> "$REPORT"; return;
  }
  chmod 700 "$tmpdir"
  : > "$tmpdir/high"
  : > "$tmpdir/context"
  # Recent log rotations only; do not search recordings, ZIPs, or update logs.
  mapfile -t list < <(find "$logdir" -maxdepth 1 -type f \
    \( -name 'main.log' -o -name 'main.log.[0-9]*' -o -name 'system.log' -o -name 'system.log.[0-9]*' \) \
    ! -name '*.zip' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -24 | cut -d' ' -f2-)
  if (( ${#list[@]} == 0 )); then
    echo 'STATUS: NO MATCHING LOG FILES' >> "$REPORT"
    rm -rf -- "$tmpdir"; return
  fi
  for sourcef in "${list[@]}"; do
    size="$(stat -c %s -- "$sourcef" 2>/dev/null || echo 0)"
    if (( size > 100000000 )); then ((skipped+=1)); continue; fi
    ((selected+=1))
    # Each log is processed as a stream; only up to 120 lines per category
    # per file are staged. Output lines limited to 450 characters.
    # No WAVE application state is changed.
    case "$sourcef" in
      *.gz) timeout -k 2s 12s gzip -cd -- "$sourcef" 2> "$tmpdir/err" ;;
      *) timeout -k 2s 12s cat -- "$sourcef" 2> "$tmpdir/err" ;;
    esac | LC_ALL=C awk -v source="$(basename "$sourcef")" '
      {
        x=tolower($0)
        # Ignore known lab noise, routine housekeeping, metadata reads,
        # WAVE updater download messages and cloud integration.
        if (x ~ /\/boot\/efi\/wisenet wave media|\/sys\/fs\/fuse\/connections\/wisenet wave media|filealreadydownloaded|wave-server_update|removeemptydirs: finished|loading chunks from db|specific_features.txt|skip missing resource|resourcemonitor\(|catalog rebuild operation is canceled|cloud_integration/) next
        if (x ~ /\/(mnt\/sda|opt\/hanwha\/mediaserver\/var\/data)/) path=1; else path=0
        # High confidence: actual recording/archive path with failure,
        # or severe disk / filesystem / write error.
        severe=(x ~ /i\/o error|input\/output error|no space left on device|read-only file system|error loading journal|journal abort|failed to write|write failed|disk disconnected|archive.*inaccessible|storage.*inaccessible|storage.*unavailable|storage.*disconnected|failed to mount/)
        if ((path && x ~ /fail|error|inaccess|unavail|disconnect|read.only|timeout|no space/) || severe) kind="HIGH"
        else if (x ~ /(warning|error|fatal)/ && x ~ /(createstorage|qnfilestorageresource|storagedb|storage directory|storage|archive|filesystem|disk|mount|recording|write)/) kind="CONTEXT"
        else next
        if (length($0)>450) $0=substr($0,1,450) "...[truncated]"
        printf "%s %s : %s\n", kind, source, $0
      }
    ' | tail -n 240 > "$tmpdir/selected"
    grep '^HIGH ' "$tmpdir/selected" | cut -c6- | tail -n 120 >> "$tmpdir/high"
    grep '^CONTEXT ' "$tmpdir/selected" | cut -c9- | tail -n 120 >> "$tmpdir/context"
    # File reading status is checked separately below.
    if [[ -s "$tmpdir/err" ]]; then
      ((warnings+=1))
      printf 'READ WARNING: %s: ' "$(basename "$sourcef")" >> "$REPORT"
      head -c 120 "$tmpdir/err" >> "$REPORT"
      printf '\n' >> "$REPORT"
    fi
    : > "$tmpdir/err"
  done
  # AWK error output is also collected in high, so select only tagged dated events.
  local high_count context_count
  high_count="$(grep -Ec '^[^ ]+ : [0-9]{4}-[0-9]{2}-[0-9]{2} ' "$tmpdir/high" || true)"
  context_count="$(wc -l < "$tmpdir/context")"
  printf 'STATUS: SEARCHED; files=%d; skipped=%d; read_warnings=%d\n' "$selected" "$skipped" "$warnings" >> "$REPORT"
  printf 'CATEGORIES: HIGH=%s CONTEXT=%s (before final output limit)\n' "$high_count" "$context_count" >> "$REPORT"
  echo 'HIGH means matching severe storage/write errors; verify exact affected path before concluding archive failure.' >> "$REPORT"
  echo 'Known non-archive initialization noise and updater download warnings excluded.' >> "$REPORT"
  echo '--- HIGH PRIORITY (last 80, timestamp order) ---' >> "$REPORT"
  if (( high_count )); then
    grep -E '^[^ ]+ : [0-9]{4}-[0-9]{2}-[0-9]{2} ' "$tmpdir/high" | LC_ALL=C sort -s -k3,3 -k4,4 | tail -80 >> "$REPORT"
  else echo 'No high-priority matching events in searched logs.' >> "$REPORT"; fi
  echo '--- CONTEXT ONLY (last 30, timestamp order) ---' >> "$REPORT"
  if (( context_count )); then
    LC_ALL=C sort -s -k3,3 -k4,4 "$tmpdir/context" | tail -30 >> "$REPORT"
  else echo 'No contextual matching events in searched logs.' >> "$REPORT"; fi
  rm -rf -- "$tmpdir"
}
collect_wave_logs
# WAVE Event Log is separate from text logs. Open SQLite read-only with WAL visibility.
# Never use immutable=1 here: it hides recent committed WAL events.
# The read connection may participate briefly in SQLite WAL read-lock coordination.
section 'WAVE EVENT LOG (SQLITE, READ-ONLY; BOUNDED)'
timeout -k 2s 9s python3 - /opt/hanwha/mediaserver/var/mserver.sqlite >> "$REPORT" 2>&1 <<'PYWAVE'
import collections
import datetime
import json
import sqlite3
import sys
import time

path = sys.argv[1]
MAX_EVENTS = 20000
DAYS = 30
now = time.time()
cutoff_us = int((now - DAYS * 86400) * 1000000)

def clean(value, limit=260):
    return str(value).replace('\n', ' ').replace('\r', ' ')[:limit]

def classify(event, subtype, payload):
    typ = (str(event or '') + ' ' + str(subtype or '')).lower()
    try:
        d = json.loads(payload) if payload else {}
        if not isinstance(d, dict):
            d = {'value': d}
    except (TypeError, ValueError, UnicodeDecodeError):
        d = {'raw': clean(payload, 100)}
    # Keys and values in WAVE event_data may hold important paths and reasons.
    relevant = ' '.join(str(d.get(k, '')) for k in ('type', 'reason', 'message', 'description', 'caption', 'storagePath', 'path', 'name', 'error', 'details')).lower()
    signal = typ + ' ' + relevant
    is_storage = any(k in signal for k in ('storage', 'disk', 'archive', 'filesystem', 'file system', 'space', 'recording', 'volume'))
    if not is_storage:
        return 'OTHER', d
    if any(k in signal for k in ('/mnt/sda', 'archive', 'disconnected', 'inaccessible', 'mount fail', 'disk failure')):
        return 'ARCHIVE_OR_STORAGE', d
    if any(k in signal for k in ('systemstoragefull', 'system storage full', 'system disk', 'systemdisk', '/opt/hanwha/mediaserver/var/data', 'disk almost full', 'disk full', 'low disk space')):
        return 'OS_DISK', d
    return 'STORAGE_UNCLASSIFIED', d

print(f'SOURCE: {path}')
print(f'WINDOW: last {DAYS} days, up to {MAX_EVENTS} most recent events; no event modifications')
print('NOTE: This reads local event_log records, not necessarily every UI-aggregated event; entries may differ across servers.')
try:
    db = sqlite3.connect('file:' + path + '?mode=ro', uri=True, timeout=1.0)
    db.execute('PRAGMA query_only=ON')
    db.execute('PRAGMA busy_timeout=1000')
    started = time.monotonic()
    db.set_progress_handler(lambda: 1 if time.monotonic() - started > 5 else 0, 3000)
    rows = db.execute('''SELECT timestamp, event_type, event_subtype, event_data, aggregated_info
                         FROM event_log WHERE timestamp >= ?
                         ORDER BY timestamp DESC LIMIT ?''', (cutoff_us, MAX_EVENTS + 1)).fetchall()
    db.close()
    capped = len(rows) > MAX_EVENTS
    rows = rows[:MAX_EVENTS]
    counts = collections.Counter()
    types = collections.Counter()
    recent = collections.defaultdict(list)
    for ts, typ, subtype, data, agg in rows:
        category, detail = classify(typ, subtype, data)
        counts[category] += 1
        types[str(typ)] += 1
        if category != 'OTHER' and len(recent[category]) < 8:
            try:
                dt = datetime.datetime.fromtimestamp(int(ts) / 1e6, datetime.timezone.utc).astimezone()
                stamp = dt.strftime('%Y-%m-%d %H:%M:%S%z')
            except (ValueError, TypeError, OverflowError, OSError):
                stamp = clean(ts)
            summary = ' '.join(clean(detail.get(k, ''), 140) for k in ('reason', 'message', 'description', 'caption', 'storagePath', 'path', 'error') if detail.get(k))
            try:
                ai = json.loads(agg) if agg else {}
                total = ai.get('total', 1) if isinstance(ai, dict) else 1
            except (ValueError, TypeError):
                total = '?'
            recent[category].append(f'{stamp} | {clean(typ, 65)} | subtype={clean(subtype or "-", 60)} | grouped_total={total} | {clean(summary or detail, 260)}')
    print(f'STATUS: OK; records_read={len(rows)}; query_limit_reached={"YES" if capped else "NO"}')
    if rows:
        print('OLDEST_INCLUDED_TIMESTAMP_US:', rows[-1][0])
    print('CLASSIFICATION COUNTS (database rows, NOT expanded aggregated occurrence totals):')
    for key in ('OS_DISK', 'ARCHIVE_OR_STORAGE', 'STORAGE_UNCLASSIFIED', 'OTHER'):
        print(f'  {key}: {counts[key]}')
    print('MOST COMMON EVENT TYPES (up to 12):')
    for key, count in types.most_common(12):
        print(f'  {clean(key, 90)}: {count}')
    for key in ('OS_DISK', 'ARCHIVE_OR_STORAGE', 'STORAGE_UNCLASSIFIED'):
        print(f'--- {key} RECENT EXAMPLES (up to 8) ---')
        print('\n'.join(recent[key]) if recent[key] else 'None found in examined database records.')
    print('Interpretation: zero matched rows does not prove zero WAVE alerts; inspect UI and logs if needed.')
except Exception as exc:
    print(f'STATUS: UNAVAILABLE / INCOMPLETE: {type(exc).__name__}: {clean(exc, 220)}')
    print('Do not interpret missing event data as no storage errors.')
PYWAVE
wave_event_rc=$?
if (( wave_event_rc != 0 )); then
  echo "WAVE EVENT COLLECTOR EXIT: $wave_event_rc (timeout/error; counts may be incomplete)" >> "$REPORT"
fi
run 'WAVE SERVICE STATUS (NO RESTART)' 5 bash -c 'systemctl is-active hanwha-mediaserver.service; systemctl show hanwha-mediaserver.service -p MainPID -p NRestarts -p ActiveEnterTimestamp'
# OS fallback directory can contain recordings: measure only, never alter.
run 'WAVE OS FALLBACK DATA (DEPTH 2, NO DELETION)' 12 bash -c 'p=/opt/hanwha/mediaserver/var/data; if [[ -d "$p" ]]; then du -xhd2 "$p" 2>/dev/null | sort -h | tail -25; else echo "No fallback path"; fi'
run 'OS TOP DIRECTORIES >= 1 GiB' 18 bash -c 'du -xhd1 / 2>/dev/null | awk '\''{x=$1; if (x ~ /G$/ && x+0>=1 || x ~ /T$/) print}'\'' | sort -h'
run 'LARGE SUBDIRECTORIES (VAR, OPT, HOME; >= 1 GiB)' 22 bash -c 'for p in /var /opt /home; do du -xhd2 "$p" 2>/dev/null; done | awk '\''{x=$1; if (x ~ /G$/ && x+0>=1 || x ~ /T$/) print}'\'' | sort -h | tail -35'
run 'SNAP INSTALLED / DISABLED REVISIONS (INFORMATION ONLY)' 6 bash -c 'if command -v snap >/dev/null; then snap list --all 2>&1 | head -35; else echo "snap unavailable"; fi'
run 'COCKPIT PACKAGE VERSIONS / LOCAL WAVE CLIENT' 6 bash -c 'dpkg-query -W cockpit-bridge cockpit-system cockpit-ws cockpit-files 2>&1; ls -1 /home/wave/.local/share/Hanwha/client/hanwha/ 2>/dev/null || true'
section 'INTERPRETATION AND OPERATING LIMITS'
cat >> "$REPORT" <<'NOTES'
This is observation, not a filesystem integrity check. SMART PASSED does not rule out intermittent failures.
Absence of matches may mean logs were vacuumed, rotated, or not persisted.
Unexpected shutdown cannot be inferred from service-level "unclean termination" messages alone.
Archive recording and playback must be independently confirmed in WAVE, especially on active production recorders.
No repairs, fsck, journal replay, mount/unmount, reboot, service restart, recording cleanup, or outbound upload performed.
Report includes sensitive device serials and identifiers; use only approved transfer paths.
A kernel-blocked I/O may not terminate promptly even with timeout.
NOTES
[[ "$OPERATOR" != root ]] && chown "$OPERATOR" "$REPORT" 2>/dev/null || true
printf '\n========== WRN MAINTENANCE 1.0.0-dev.1 | DIAGNOSTICS ONLY ========\n'
printf 'Host: %s\nReport: %s\n' "$HOST" "$REPORT"
printf 'OS: '; df -h / | awk 'NR==2 {print $5 " used; " $4 " free"}'
printf 'Archive: %s (%s)\n' "$ARCHIVE_MOUNTED" "${ARCHIVE_DEV:-UNRESOLVED}"
printf 'Mount: %s\n' "$(findmnt -rn -M /mnt/sda -o SOURCE,FSTYPE,OPTIONS 2>/dev/null || echo 'NOT MOUNTED')"
printf 'WAVE service: '; systemctl is-active hanwha-mediaserver.service 2>/dev/null || true
printf 'SMART: '; grep -m1 'SMART overall-health self-assessment test result:' "$REPORT" || echo 'See report'
printf 'No service, mount, configuration or recording changes made. A local report was created; download through Cockpit.\n==========================================\n'
