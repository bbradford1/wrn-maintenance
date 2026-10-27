#!/usr/bin/env bash
# WRN Maintenance 1.0.0-dev.10-pilot - PRE-PRODUCTION / SUPERVISED TESTING ONLY
# Ubuntu 22.04. --diagnose and --preview are read-only; --apply performs conditional maintenance.
# No WAVE/network restart, remount, fsck, reboot, or video cleanup.
VERSION='1.0.0-dev.10-pilot'
MODE="${1:---diagnose}"
[[ $# -le 1 ]] || { echo 'Only one option permitted' >&2; exit 2; }
case "$MODE" in
  --diagnose|--preview|--apply|--package-preview|--tidy-preview|--tidy|--finalize) ;;
  --version) echo "$VERSION"; exit 0 ;;
  --help|-h) printf 'WRN Maintenance %s\nUsage: sudo bash wrn_maintenance.sh [--diagnose|--preview|--package-preview|--apply|--finalize|--version]\n--apply is for supervised pre-production validation only.\n' "$VERSION"; exit 0 ;;
  *) echo 'Usage: --diagnose, --preview, --package-preview, --apply, --finalize' >&2; exit 2 ;;
esac
[[ $EUID -eq 0 ]] || { echo 'Run with sudo' >&2; exit 2; }
. /etc/os-release
[[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == '22.04' ]] || { echo 'Only Ubuntu 22.04 is supported' >&2; exit 2; }
WRN_DIR=/home/wave/Downloads/maintenance
[[ -d "$WRN_DIR" && ! -L "$WRN_DIR" ]] || { echo 'STOP: maintenance folder must exist and not be a symlink' >&2; exit 2; }
export WRN_REPORT_DIR="$WRN_DIR"

# Capture diagnostics in a subshell; the original collector retains its own report handling.
collect_diagnostics() (
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
chmod 644 "$REPORT"
chown wave:wave "$REPORT" 2>/dev/null || true

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
printf 'UTC: %s\nHostname: %s\nCollector: WRN Maintenance 1.0.0-dev.10-pilot\nOperator: %s\nMode: READ-ONLY\nArchive selected: %s\nSelection method: %s\nArchive mounted at /mnt/sda: %s\n' "$(date -u -Is)" "$HOST" "$OPERATOR" "${ARCHIVE_DEV:-UNRESOLVED}" "${ARCHIVE_MATCH:-not determined}" "$ARCHIVE_MOUNTED" >> "$REPORT"
run 'OS, KERNEL, TIME, UPTIME' 5 bash -c 'grep -E "^(PRETTY_NAME|VERSION_ID)=" /etc/os-release; printf "Kernel: "; uname -r; printf "Local time: "; date -Is; printf "Boot: "; uptime -s; uptime -p'
run 'OS DISK CAPACITY' 5 df -hT /
run 'OS JOURNAL UTILIZATION (READ-ONLY)' 8 bash -c 'journalctl --disk-usage 2>&1; for p in /var/log/journal /run/log/journal; do if [[ -d "$p" ]]; then du -sh "$p" 2>&1; else echo "$p: not present"; fi; done'
run 'KB LOGGING CONFIGURATION (READ-ONLY)' 12 bash -c 'echo "-- rsyslog syntax --"; rsyslogd -N1 2>&1; echo "-- rsyslog state --"; systemctl is-active rsyslog || true; echo "-- logrotate dry run --"; logrotate -d /etc/logrotate.conf 2>&1 | grep -Ei "warning:|error:|reading config file rsyslog|considering log /var/log/(syslog|kern.log)" | tail -30; echo "-- logrotate timer --"; systemctl list-timers --all --no-pager logrotate.timer 2>&1'
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
run 'ARCHIVE FAILURE AND JOURNAL FLAGS (READ-ONLY)' 8 bash -c '
  systemctl show mnt-sda.mount -p ActiveState -p Result -p TimeoutUSec
  journalctl -u mnt-sda.mount -n 35 --no-pager -o short-iso 2>&1 | grep -Ei "timed out|failed|mounting|mounted|timeout" || true
  journalctl -k -n 2500 --no-pager 2>&1 | grep -Ei "JBD2: recovery failed|EXT4-fs \(sda\): error loading journal|recovering journal" | tail -20 || true
  if ! findmnt -rn -M /mnt/sda >/dev/null 2>&1; then
    echo "WARNING: Archive unmounted; no fsck, journal replay, or mounting attempted. Collect forensics before repair."
  fi
' 
run 'FSTAB DEVICE MATCH AND PERSISTENCE' 5 bash -c 'grep -E "^[^#].*[[:space:]]/mnt/sda[[:space:]]" /etc/fstab; if grep -Eq "^UUID=[^[:space:]]+[[:space:]]+/mnt/sda[[:space:]]+ext4[[:space:]]" /etc/fstab; then echo "PASS: archive fstab uses UUID"; else echo "WARNING: archive fstab not confirmed UUID ext4"; fi'
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
run 'SNAP REFRESH HOLD (READ-ONLY)' 7 bash -c 'if command -v snap >/dev/null; then snap refresh --time; else echo "SKIP: snap unavailable"; fi'
run 'FAILED SYSTEMD UNITS (READ-ONLY)' 7 systemctl --failed --no-pager
run 'COCKPIT PACKAGE VERSIONS / LOCAL WAVE CLIENT' 6 bash -c 'dpkg-query -W cockpit-bridge cockpit-system cockpit-ws cockpit-files 2>&1; ls -1 /home/wave/.local/share/Hanwha/client/hanwha/ 2>/dev/null || true'
section 'INTERPRETATION AND OPERATING LIMITS'
cat >> "$REPORT" <<'NOTES'
This is observation, not a filesystem integrity check. SMART PASSED does not rule out intermittent failures.
Absence of matches may mean logs were vacuumed, rotated, or not persisted.
Unexpected shutdown cannot be inferred from service-level "unclean termination" messages alone.
Archive recording and playback must be independently confirmed in WAVE, especially on active production recorders.
Diagnostic collection does not perform repairs, fsck, journal replay, mount/unmount, reboot, service restart, recording cleanup, or outbound upload.
Report includes sensitive device serials and identifiers; use only approved transfer paths.
A kernel-blocked I/O may not terminate promptly even with timeout.
NOTES
if [[ "$OPERATOR" != root ]]; then
  chown "$OPERATOR" "$REPORT" 2>/dev/null || echo "WARNING: report ownership could not be changed: $REPORT" >&2
fi
chmod 644 "$REPORT"
chown wave:wave "$REPORT" 2>/dev/null || true
printf '\n========== WRN MAINTENANCE 1.0.0-dev.10-pilot | DIAGNOSTICS ========\n'
printf 'Host: %s\nReport: %s\n' "$HOST" "$REPORT"
printf 'OS: '; df -h / | awk 'NR==2 {print $5 " used; " $4 " free"}'
printf 'Archive: %s (%s)\n' "$ARCHIVE_MOUNTED" "${ARCHIVE_DEV:-UNRESOLVED}"
printf 'Mount: %s\n' "$(findmnt -rn -M /mnt/sda -o SOURCE,FSTYPE,OPTIONS 2>/dev/null || echo 'NOT MOUNTED')"
printf 'WAVE service: '; systemctl is-active hanwha-mediaserver.service 2>/dev/null || true
printf 'SMART: '; grep -m1 'SMART overall-health self-assessment test result:' "$REPORT" || echo 'See report'
printf 'Diagnostic report collected. This diagnostic operation did not modify services, mounts or recordings.\n==========================================\n'

)

# Write audit and maintenance transcript to the operator's Downloads folder.
maintenance_log_setup() {
  local who="${SUDO_USER:-wave}" home
  home="$(getent passwd "$who" | cut -d: -f6)"
  [[ -n "$home" && -d "$home/Downloads" ]] || { echo 'STOP: Downloads directory unavailable' >&2; return 1; }
  WRN_LOG="$WRN_DIR/WRN-Maintenance_$(hostname -s)_$(date -u +%Y%m%dT%H%M%SZ)_dev10.txt"
  touch "$WRN_LOG" || return 1
  chmod 644 "$WRN_LOG" || return 1
  if [[ "$who" != root ]]; then
    chown "$who" "$WRN_LOG" || { echo "STOP: cannot grant report access to $who" >&2; return 1; }
  fi
  exec > >(tee -a "$WRN_LOG") 2>&1
  echo "Maintenance build=$VERSION, log=$WRN_LOG"
}

safe_state() {
  [[ "$(systemctl is-active hanwha-mediaserver.service 2>/dev/null)" == active ]] || { echo 'STOP: WAVE not active'; return 1; }
  [[ "$(systemctl is-active display-manager.service 2>/dev/null)" == active ]] || { echo 'STOP: desktop manager not active'; return 1; }
  [[ "$(findmnt -rn -M /mnt/sda -o OPTIONS 2>/dev/null)" =~ (^|,)rw(,|$) ]] || { echo 'STOP: archive /mnt/sda not mounted read-write'; return 1; }
  [[ "$(findmnt -rn -o SOURCE /)" == /dev/mmcblk* ]] || { echo 'STOP: unexpected OS drive layout'; return 1; }
}

# Logrotate KB: validate existing logging first; never replace distro configurations.
logging_kb() {
  echo '=== KB LOGGING AUDIT ==='
  if ! rsyslogd -N1 2>&1; then
    echo 'STOP: rsyslog config is invalid; leave configuration untouched for manual diagnosis'
    return 1
  fi
  [[ "$(systemctl is-active rsyslog.service 2>/dev/null)" == active ]] || { echo 'STOP: rsyslog inactive'; return 1; }
  local out
  out="$(mktemp)" || return 1
  if ! logrotate -d /etc/logrotate.conf > "$out" 2>&1; then
    cat "$out"; rm -f "$out"
    echo 'STOP: logrotate config invalid; manual repair required'; return 1
  fi
  echo 'Logrotate config: valid; existing rotation configuration retained.'
  grep -Ei "warning:.*(size|daily|hourly)" "$out" || true
  rm -f "$out"
  # Unlike the original KB, do not recursively chown /etc or delete all large logs.
  # Only rotate approved system logs with their already validated rules.
  local f
  for f in /var/log/syslog /var/log/kern.log; do
    if [[ -f "$f" && $(stat -c %s "$f") -gt 104857600 ]]; then
      echo "Over 100 MiB: $f; requesting normal rotation using installed rules"
      logrotate /etc/logrotate.conf || { echo 'STOP: logrotate unsuccessful'; return 1; }
      break
    fi
  done
  journalctl --vacuum-size=1G || return 1
  journalctl --vacuum-time=7d || return 1
  echo 'KB logging: configuration valid; bounded rotation and journal cleanup completed.'
}

# Precisely one mounted archive and exactly one fstab target are essential prerequisites.
# No generic mount -a, fsck, or WAVE stop/start.
fstab_kb() {
  echo '=== KB FSTAB AUDIT & CONDITIONAL CORRECTION ==='
  local dev fs uuid cur_source count original draft backup errors=0 line missing_count
  cur_source="$(findmnt -rn -M /mnt/sda -o SOURCE 2>/dev/null)"
  [[ -n "$cur_source" && -b "$cur_source" ]] || { echo 'STOP: no confidently mounted archive device'; return 1; }
  dev="$(readlink -f "$cur_source")"
  fs="$(blkid -s TYPE -o value "$dev" 2>/dev/null)"
  uuid="$(blkid -s UUID -o value "$dev" 2>/dev/null)"
  [[ "$fs" == ext4 && "$uuid" =~ ^[a-fA-F0-9-]{36}$ ]] || { echo 'STOP: unexpected archive filesystem or UUID'; return 1; }
  [[ "$(findmnt -rn -M /mnt/sda -o FSTYPE)" == ext4 ]] || { echo 'STOP: mounted archive not ext4'; return 1; }
  count="$(awk '$1 !~ /^#/ && $2=="/mnt/sda" {n++} END {print n+0}' /etc/fstab)"
  [[ "$count" == 1 ]] || { echo "STOP: expected one /mnt/sda entry, found $count"; return 1; }
  # Fail closed if any source or archive mount point is defined more than once.
  if awk '$1 !~ /^#/ && NF>=4 && $2 ~ /^\/mnt\/sd[a-z]$/ {m[$2]++} END {for (mp in m) if (m[mp]>1) exit 1}' /etc/fstab; then :; else
    echo 'STOP: duplicate archive mount-point entries; manual investigation required'; return 1
  fi
  # Reject reused archive UUID/device in other active fstab entries.
  if awk -v d="$dev" -v u="UUID=$uuid" '$1 !~ /^#/ && $2!="/mnt/sda" && ($1==d || $1==u) {bad=1} END {exit !bad}' /etc/fstab; then
    echo 'STOP: archive filesystem also referenced by another mount; manual investigation required'; return 1
  fi
  # Only permit a stable UUID, ext4 and preserving a reasonable existing timeout.
  original="$(awk '$1 !~ /^#/ && $2=="/mnt/sda" {print; exit}' /etc/fstab)"
  read -r oldsource mount oldtype opts dump pass <<< "$original"
  [[ "$oldsource" == "$cur_source" || "$oldsource" == "$dev" || "$oldsource" == "UUID=$uuid" ]] || {
    echo 'STOP: configured source differs from mounted archive'; return 1;
  }
  [[ "$oldtype" == ext4 || "$oldtype" == auto ]] || { echo 'STOP: unexpected fstab type'; return 1; }
  [[ "$opts" =~ ^[a-zA-Z0-9._,=-]+$ ]] || { echo 'STOP: archive mount options unexpected; requires review'; return 1; }
  [[ "${dump:-0}" =~ ^[0-9]+$ && "${pass:-0}" =~ ^[0-9]+$ ]] || { echo 'STOP: fstab trailing fields malformed'; return 1; }
  [[ "$opts" == *nofail* ]] || echo 'Will add nofail to archive entry'
  # Explicit mount-operation timeout is required: device timeout alone does not
  # protect slow ext4 journal replay. Preserve any longer existing timeouts.
  # Refuse unknown/ambiguous timeout syntax instead of silently overwriting it.
  local opt device_timeout=60 mount_timeout=120 value
  local -a options=() retained=()
  IFS=',' read -r -a options <<< "$opts"
  for opt in "${options[@]}"; do
    case "$opt" in
      x-systemd.device-timeout=*)
        value="${opt#*=}"; [[ "$value" =~ ^[0-9]+s?$ ]] || { echo "STOP: unsupported device timeout: $value"; return 1; }
        value="${value%s}"; (( value > device_timeout )) && device_timeout="$value"
        ;;
      x-systemd.mount-timeout=*)
        value="${opt#*=}"; [[ "$value" =~ ^[0-9]+s?$ ]] || { echo "STOP: unsupported mount timeout: $value"; return 1; }
        value="${value%s}"; (( value > mount_timeout )) && mount_timeout="$value"
        ;;
      nofail) ;;
      *) retained+=("$opt") ;;
    esac
  done
  local newopts joined=''
  for opt in "${retained[@]}"; do
    if [[ -n "$joined" ]]; then joined+=","; fi
    joined+="$opt"
  done
  [[ -n "$joined" ]] || joined=defaults
  newopts="$joined,nofail,x-systemd.device-timeout=${device_timeout}s,x-systemd.mount-timeout=${mount_timeout}s"
  local target="UUID=$uuid /mnt/sda ext4 $newopts ${dump:-0} ${pass:-0}"
  echo "Current: $original"
  echo "Proposed: $target"
  # Do not disable missing /dev/sdb..d entries without checking whether hardware is temporarily absent.
  # These remain warnings that require technician acknowledgement/repair later.
  for dev in /dev/sdb /dev/sdc /dev/sdd; do
    if [[ ! -b "$dev" ]] && grep -Eq "^${dev}[[:space:]]" /etc/fstab; then
      echo "WARNING: fstab references currently missing device $dev; not automatically disabled"
    fi
  done
  [[ "$original" != "$target" ]] || { echo 'KB archive entry already normalized; no edit needed'; return 0; }
  backup="/etc/fstab.wrn-dev7.$(date -u +%Y%m%dT%H%M%SZ).bak"
  draft="$(mktemp /etc/.fstab.wrn.XXXXXXXX)" || return 1
  cp -a /etc/fstab "$backup" || { rm -f "$draft"; return 1; }
  # Exact line replacement, no global substitution.
  awk -v replacement="$target" '$1 !~ /^#/ && $2=="/mnt/sda" {$0=replacement} {print}' /etc/fstab > "$draft"
  chmod --reference=/etc/fstab "$draft"; chown --reference=/etc/fstab "$draft"
  if ! findmnt --verify --tab-file "$draft" >/dev/null 2>&1; then
    echo 'STOP: staged fstab failed verification; original remains unchanged'
    rm -f "$draft"; return 1
  fi
  # Prevent replacing an fstab edited by somebody else during our checks.
  if ! cmp -s /etc/fstab "$backup"; then
    echo 'STOP: fstab changed during preparation; refusing replacement'
    rm -f "$draft"; return 1
  fi
  if ! mv -f "$draft" /etc/fstab; then
    echo 'STOP: could not install staged fstab'; return 1
  fi
  # Validate installed file and restore original from backup if validation fails.
  if ! findmnt --verify --tab-file /etc/fstab >/dev/null 2>&1; then
    echo 'STOP: installed fstab verification failed; restoring backup'
    cp -a "$backup" /etc/fstab || echo 'CRITICAL: rollback copy failed!'
    return 1
  fi
  echo "KB fstab correction verified; backup=$backup"
  # Do not call daemon-reload / mount -a during a remote recording session.
  echo 'NOTICE: Systemd fstab generator will consume the new entry on next controlled boot. No mount changed now.'
}

# Snap refresh suspension is deliberately explicit: preventing an update is not the
# same as preventing a user or another process from manually reinstalling a snap.
# Snap refresh --hold=forever is supported on the target snapd; verify the resulting
# setting before deleting cached downloads or considering the Snap stage complete.
snap_refresh_hold() {
  echo '=== SNAP AUTOMATIC REFRESH HOLD ==='
  if ! command -v snap >/dev/null 2>&1; then
    echo 'SKIP: snap not installed'
    return 0
  fi
  echo 'Before (snap refresh --time):'
  snap refresh --time 2>&1 || echo 'WARNING: unable to read refresh schedule before hold'
  echo 'APPLY: request indefinite hold of all automatic Snap refreshes'
  if ! snap refresh --hold=forever; then
    echo 'STOP: failed to request indefinite Snap refresh hold'; return 1
  fi
  echo 'After (snap refresh --time):'
  local schedule
  schedule="$(snap refresh --time 2>&1)" || {
    echo "STOP: could not read Snap refresh schedule after applying hold: $schedule"; return 1;
  }
  echo "$schedule"
  # snap refresh --hold and system refresh.hold are different mechanisms.
  # Explicitly identify the indefinite hold if snapd displays it; otherwise
  # report command success without falsely claiming a parsed confirmation.
  if echo "$schedule" | grep -Eiq '(^|[[:space:]])hold:.*forever|(^|[[:space:]])held:.*forever'; then
    echo 'PASS: indefinite automatic-refresh hold visible in refresh schedule'
  else
    echo 'NOTICE: hold command succeeded, but indefinite hold not independently parsed from this snapd output'
  fi
  echo 'NOTE: holding auto-refresh does not prohibit manual upgrades or reinstallations'
}

snap_cleanup() {
  echo '=== SNAP CLEANUP / STATE AUDIT ==='
  command -v snap >/dev/null 2>&1 || { echo 'Snap not installed; skipping'; return 0; }
  local name rev
  while read -r name rev; do
    [[ -n "${name:-}" && "$rev" =~ ^[0-9]+$ ]] || continue
    case "$name" in
      core20|core22|core24|snapd|firefox|snap-store|snapd-desktop-integration|gnome-42-2204|gnome-46-2404|mesa-2404) ;;
      *) echo "SKIP unapproved disabled revision: $name $rev"; continue ;;
    esac
    if snap list --all "$name" | awk -v r="$rev" 'NR>1 && $3==r && /disabled/ {ok=1} END {exit !ok}'; then
      safe_state || return 1
      echo "Removing disabled Snap: $name revision $rev"
      snap remove "$name" --revision="$rev" --purge || return 1
    fi
  done < <(snap list --all | awk 'NR>1 && /disabled/ {print $1, $3}')
  for name in firefox snap-store snapd-desktop-integration; do
    if snap list "$name" >/dev/null 2>&1; then
      echo "REVIEW: active $name retained; no silent active application removal"
    fi
  done
  if [[ -d /var/lib/snapd/cache ]]; then
    echo "Snap download cache before: $(du -sh /var/lib/snapd/cache 2>/dev/null || true)"
    find /var/lib/snapd/cache -mindepth 1 -maxdepth 1 -type f -delete || return 1
    echo "Snap download cache after: $(du -sh /var/lib/snapd/cache 2>/dev/null || true)"
  fi
  echo 'Failed Snap mount units, if any:'
  systemctl list-units --all --type=mount --state=failed --no-pager | grep 'snap-' || true
  echo 'NOTE: failed Snap units are reported, not blindly reset or deleted.'
  echo 'IMPORTANT: a refresh hold does not prevent manual snap install, apt operations, or other installers.'
}

run_preview() {
  local who="${SUDO_USER:-wave}" home out current source fs uuid entries oldtype opts oldspec
  home="$(getent passwd "$who" | cut -d: -f6)"
  [[ -n "$home" && -d "$home/Downloads" ]] || { echo 'STOP: Downloads not found'; return 1; }
  out="$WRN_DIR/WRN-KB-Repair-Preview_$(hostname -s)_$(date -u +%Y%m%dT%H%M%SZ)_dev10.txt"
  ( umask 077
    {
      echo "=== WRN MAINTENANCE $VERSION / READ-ONLY REPAIR PLAN ==="
      date -Is
      echo '=== SAFETY GUARDS ==='
      if safe_state; then echo 'PASS: WAVE, desktop, OS and mounted archive guards'; else echo 'BLOCKED: Apply unsafe'; fi
      echo '=== KB1 LOGGING ==='
      if rsyslogd -N1 2>&1 && [[ "$(systemctl is-active rsyslog.service 2>/dev/null)" == active ]]; then
        echo 'PASS: rsyslog valid and active'; else echo 'BLOCKED: rsyslog invalid/inactive'; fi
      local tmp
      tmp="$(mktemp)" || exit 1
      if logrotate -d /etc/logrotate.conf >"$tmp" 2>&1; then
        echo 'PASS: logrotate rules parse; retain existing configuration'
      else
        echo 'BLOCKED: logrotate validation failed'; fi
      grep -Ei "warning:.*(size|daily|hourly)|error:" "$tmp" | tail -25 || true
      rm -f "$tmp"
      for current in /var/log/syslog /var/log/kern.log; do
        if [[ -f "$current" ]]; then
          echo "LOG: $current $(stat -c %s "$current") bytes"
          if [[ $(stat -c %s "$current") -gt 104857600 ]]; then echo 'WOULD: request normal logrotate execution'; else echo 'SKIP: below 100 MiB threshold'; fi
        fi
      done
      journalctl --disk-usage 2>&1
      echo 'APPLY: bounded journal vacuum (no active journal deletion)'
      echo '=== KB2 ARCHIVE FSTAB ==='
      source="$(findmnt -rn -M /mnt/sda -o SOURCE 2>/dev/null || :)"
      fs="$(findmnt -rn -M /mnt/sda -o FSTYPE 2>/dev/null || :)"
      uuid=''
      if [[ -b "$source" ]]; then uuid="$(blkid -s UUID -o value "$source" 2>/dev/null || :)"; fi
      entries="$(awk '$1 !~ /^#/ && $2=="/mnt/sda" {n++} END {print n+0}' /etc/fstab)"
      echo "Mounted source: ${source:-NONE}; filesystem: ${fs:-NONE}; UUID: ${uuid:-NONE}; fstab entries: $entries"
      if [[ -z "$source" ]]; then echo 'BLOCKED: archive not mounted; manual journal/mount investigation required (never repaired by maintenance)'; fi
      awk '$1 !~ /^#/ && $2=="/mnt/sda" {print "CURRENT:", $0}' /etc/fstab
      opts="$(awk '$1 !~ /^#/ && $2=="/mnt/sda" {print $4; exit}' /etc/fstab)"
      if [[ "$entries" == 1 && "$fs" == ext4 && "$uuid" =~ ^[a-fA-F0-9-]{36}$ ]]; then
        if awk -v u="UUID=$uuid" '$1==u && $2=="/mnt/sda" && $3=="ext4" {ok=1} END {exit !ok}' /etc/fstab; then
          if [[ "$opts" == *"x-systemd.device-timeout="* && "$opts" == *"x-systemd.mount-timeout="* ]]; then
            echo "REVIEW: UUID present; apply will preserve or raise device timeout to >=60s and mount-operation timeout to >=120s"
          else
            echo "CANDIDATE: UUID present but missing one/both explicit timeouts (60s device, 120s mount)"
          fi
        else
          echo "CANDIDATE: normalize to UUID=$uuid while preserving safe options and timeout"
        fi
        echo 'NOTE: Apply also checks duplicate mount points, existing source identity and fstab staging validation'
      else echo 'BLOCKED: archive identity or fstab entries ambiguous'; fi
      for current in /dev/sdb /dev/sdc /dev/sdd; do
        if [[ ! -b "$current" ]] && awk -v d="$current" '$1==d && $1 !~ /^#/ {found=1} END{exit !found}' /etc/fstab; then
          echo "REVIEW: $current absent but referenced in fstab; no automatic removal"
        fi
      done
      echo '=== SNAP ==='
      if command -v snap >/dev/null; then
        snap list --all | awk 'NR==1 || /disabled/'
        echo "Current Snap refresh schedule:"; snap refresh --time 2>&1 || true
        echo 'APPLY: request snap refresh --hold=forever; report schedule afterward; purge approved disabled revisions and clear cache'
        echo 'NOTE: hold stops automatic Snap refresh; it does NOT prohibit new installs by other tools'
        echo 'ACTIVE SNAP APPS RETAINED: no silent active application removal'
      fi
      echo '=== SYSTEMD FAILED UNITS ==='; systemctl --failed --no-pager || true
      echo '=== END READ-ONLY PLAN; NO CHANGES ==='
    } >"$out" 2>&1
  )
  chmod 644 "$out"
  if [[ "$who" != root ]]; then chown "$who" "$out" || return 1; fi
  echo "Repair preview saved: $out"
}

final_kb_summary() {
  echo '=== FINAL KB / OPERATIONAL SUMMARY ==='
  if rsyslogd -N1 >/dev/null 2>&1 && [[ "$(systemctl is-active rsyslog.service 2>/dev/null)" == active ]] && logrotate -d /etc/logrotate.conf >/dev/null 2>&1; then
    echo 'PASS KB1: rsyslog operational and logrotate configuration parses'
  else
    echo 'FAIL KB1: logging verification requires investigation'; return 1
  fi
  local source fs uuid entry count
  source="$(findmnt -rn -M /mnt/sda -o SOURCE 2>/dev/null)"
  fs="$(findmnt -rn -M /mnt/sda -o FSTYPE 2>/dev/null)"
  uuid="$(blkid -s UUID -o value "$source" 2>/dev/null)"
  entry="$(awk '$1 !~ /^#/ && $2=="/mnt/sda" {print; exit}' /etc/fstab)"
  count="$(awk '$1 !~ /^#/ && $2=="/mnt/sda" {n++} END {print n+0}' /etc/fstab)"
  if [[ "$count" == 1 && "$fs" == ext4 && -n "$uuid" && "$entry" == "UUID=$uuid "* ]] && [[ "$(findmnt -rn -M /mnt/sda -o OPTIONS)" =~ (^|,)rw(,|$) ]]; then
    if [[ "$entry" != *"x-systemd.device-timeout="* || "$entry" != *"x-systemd.mount-timeout="* ]]; then
      echo 'FAIL KB2: explicit archive timeouts missing'; return 1
    fi
    echo 'PASS KB2: mounted rw ext4 archive matches persistent UUID fstab entry and explicit timeouts' 
  else
    echo 'FAIL KB2: mounted archive and fstab mismatch'; return 1
  fi
  if grep -Eq '^/dev/sd[b-d][[:space:]]' /etc/fstab; then
    echo 'WARNING KB2: additional /dev/sdb..sdd fstab entries remain; review for optional bays'
  fi
  if command -v snap >/dev/null 2>&1; then
    local schedule
    schedule="$(snap refresh --time 2>&1)" || { echo 'WARNING SNAP: refresh hold unverified'; return 1; }
    if grep -Eiq '(^|[[:space:]])hold:.*forever|(^|[[:space:]])held:.*forever' <<< "$schedule"; then
      echo 'PASS SNAP: automatic refresh hold is forever'
    else
      echo 'FAIL SNAP: indefinite refresh hold not verified'; return 1
    fi
  fi
  if [[ "$(systemctl is-active hanwha-mediaserver.service 2>/dev/null)" == active ]]; then
    echo 'PASS WAVE: service active (recording and playback require independent user check)'
  else
    echo 'FAIL WAVE: service not active'; return 1
  fi
  echo 'NOTE: logrotate size/schedule warnings may still exist, and historical alerts may remain in WAVE logs'
}


# --- PILOT: guarded optional application removal (tested on WRN #2). ---
APP_ALLOWED=(libreoffice-common libreoffice-core libreoffice-gnome libreoffice-gtk3 libreoffice-help-common libreoffice-help-da libreoffice-help-en-gb libreoffice-help-en-us libreoffice-help-es libreoffice-help-et libreoffice-help-fi libreoffice-help-fr libreoffice-help-it libreoffice-help-nl libreoffice-help-pl libreoffice-help-pt libreoffice-help-pt-br libreoffice-help-sv libreoffice-help-tr libreoffice-l10n-da libreoffice-l10n-en-gb libreoffice-l10n-en-za libreoffice-l10n-es libreoffice-l10n-et libreoffice-l10n-fi libreoffice-l10n-fr libreoffice-l10n-is libreoffice-l10n-it libreoffice-l10n-lt libreoffice-l10n-lv libreoffice-l10n-nl libreoffice-l10n-nn libreoffice-l10n-pl libreoffice-l10n-pt libreoffice-l10n-pt-br libreoffice-l10n-sv libreoffice-l10n-tr libreoffice-math libreoffice-pdfimport libreoffice-voikko mythes-pl python3-uno thunderbird thunderbird-gnome-support thunderbird-locale-da thunderbird-locale-en thunderbird-locale-en-gb thunderbird-locale-en-us thunderbird-locale-es thunderbird-locale-es-ar thunderbird-locale-es-es thunderbird-locale-et thunderbird-locale-fi thunderbird-locale-fr thunderbird-locale-is thunderbird-locale-it thunderbird-locale-lt thunderbird-locale-lv thunderbird-locale-nl thunderbird-locale-nn thunderbird-locale-nn-no thunderbird-locale-pl thunderbird-locale-pt thunderbird-locale-pt-br thunderbird-locale-pt-pt thunderbird-locale-sv thunderbird-locale-sv-se thunderbird-locale-tr)
LEFT_ALLOWED=(libboost-filesystem1.74.0 libboost-iostreams1.74.0 libboost-locale1.74.0 libboost-thread1.74.0 libclucene-contribs1v5 libclucene-core1v5 libeot0 libexttextcat-2.0-0 libexttextcat-data libgpgmepp6 liblangtag-common liblangtag1 libmessaging-menu0 libmhash2 libmythes-1.2-0 liborcus-0.17-0 liborcus-parser-0.17-0 libraptor2-0 librasqal3 librdf0 libreoffice-style-elementary libreoffice-style-yaru librevenge-0.0-0 libuno-cppu3 libuno-cppuhelpergcc3-3 libuno-purpenvhelpergcc3-3 libuno-sal3 libuno-salhelpergcc3-3 libxmlsec1 libxmlsec1-nss libyajl2 uno-libs-private ure)
PROTECTED_PKGS=(ubuntu-desktop ubuntu-desktop-minimal gnome-shell gdm3 network-manager openssh-server cockpit google-chrome-stable snapd)
APP_RESULT=not-run
LEFT_RESULT=not-run

package_guard() {
  safe_state || return 1
  local pkg status
  for pkg in "${PROTECTED_PKGS[@]}"; do
    status="$(dpkg-query -W -f='${db:Status-Abbrev}' "$pkg" 2>/dev/null || true)"
    [[ "$status" == ii* ]] || { echo "BLOCKED: required package missing: $pkg ($status)"; return 1; }
  done
  [[ -z "$(dpkg --audit 2>/dev/null)" ]] || { echo 'BLOCKED: dpkg audit not clean'; return 1; }
  [[ "$(findmnt -rn -M /mnt/sda -o FSTYPE 2>/dev/null)" == ext4 ]] || return 1
}

# Run a fresh APT simulation and permit removal ONLY if every proposed package
# belongs to an explicitly reviewed package list. No broad autoremove executes.
package_stage() {
  local stage="$1" action="$2"; shift 2
  local sim list approved explicit checked pkg
  sim="$(mktemp)" || return 1
  list="$(mktemp)" || { rm -f "$sim"; return 1; }
  approved="$(mktemp)" || { rm -f "$sim" "$list"; return 1; }
  explicit="$(mktemp)" || { rm -f "$sim" "$list" "$approved"; return 1; }
  checked="$(mktemp)" || { rm -f "$sim" "$list" "$approved" "$explicit"; return 1; }
  echo "=== GUARDED $stage ==="
  if ! package_guard; then echo "SKIP $stage: preflight failure"; rm -f "$sim" "$list" "$approved" "$explicit" "$checked"; return 2; fi
  if [[ "$stage" == APPLICATIONS ]]; then
    printf '%s\n' "${APP_ALLOWED[@]}" | sort -u > "$approved"
    if ! apt-get -s --no-install-recommends purge thunderbird libreoffice-core libreoffice-common > "$sim" 2>&1; then
      echo "SKIP $stage: APT simulation failed"; tail -35 "$sim"; rm -f "$sim" "$list" "$approved" "$explicit" "$checked"; return 2
    fi
  else
    printf '%s\n' "${LEFT_ALLOWED[@]}" | sort -u > "$approved"
    if ! apt-get -s autoremove --purge > "$sim" 2>&1; then
      echo "SKIP $stage: APT simulation failed"; tail -35 "$sim"; rm -f "$sim" "$list" "$approved" "$explicit" "$checked"; return 2
    fi
  fi
  awk '$1=="Purg" {print $2}' "$sim" | sort -u > "$list"
  if grep -Eq '^(Inst|Conf|Remv) ' "$sim"; then
    echo "SKIP $stage: APT proposed non-purge transaction"; rm -f "$sim" "$list" "$approved" "$explicit" "$checked"; return 2
  fi
  if [[ ! -s "$list" ]]; then
    echo "SKIP $stage: nothing left to remove"; rm -f "$sim" "$list" "$approved" "$explicit" "$checked"; return 0
  fi
  if [[ -n "$(comm -23 "$list" "$approved")" ]]; then
    echo "SKIP $stage: unexpected packages; no changes"; comm -23 "$list" "$approved"
    rm -f "$sim" "$list" "$approved" "$explicit" "$checked"; return 2
  fi
  mapfile -t selection < "$list"
  # Explicitly purge the exact approved packages, never execute apt autoremove.
  if ! apt-get -s --no-install-recommends purge "${selection[@]}" > "$explicit" 2>&1; then
    echo "SKIP $stage: explicit simulation failed"; tail -35 "$explicit"
    rm -f "$sim" "$list" "$approved" "$explicit" "$checked"; return 2
  fi
  awk '$1=="Purg" {print $2}' "$explicit" | sort -u > "$checked"
  if ! cmp -s "$checked" "$list" || grep -Eq '^(Inst|Conf|Remv) ' "$explicit"; then
    echo "SKIP $stage: explicit transaction changed removal plan"
    diff -u "$list" "$checked" || true
    rm -f "$sim" "$list" "$approved" "$explicit" "$checked"; return 2
  fi
  echo "APPROVED $stage: $(wc -l < "$list") packages"; cat "$list"
  if [[ "$action" == preview ]]; then
    echo "PREVIEW ONLY $stage: no changes made"
    rm -f "$sim" "$list" "$approved" "$explicit" "$checked"
    return 0
  fi
  if ! DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt-get -y --no-install-recommends purge "${selection[@]}"; then
    echo "ERROR $stage: APT failed. Check dpkg status before more package maintenance."
    rm -f "$sim" "$list" "$approved" "$explicit" "$checked"; return 1
  fi
  rm -f "$sim" "$list" "$approved" "$explicit" "$checked"
  package_guard || { echo "ERROR $stage: post-apply safety check failed"; return 1; }
  echo "COMPLETE $stage: approved packages removed"
}

# Append a machine-local service entry without claiming playback validation.
record_service_history() {
  local h="$WRN_DIR/WRN-Service-History.txt" before="$1" after="$2" rc="$3" entry
  [[ ! -L "$h" ]] || { echo 'ERROR: service history is a symlink'; return 1; }
  [[ ! -e "$h" || ( -f "$h" && "$(stat -c %h "$h")" == 1 ) ]] || return 1
  entry="$(date -u '+%Y-%m-%d %H:%M:%SZ')"
  {
    [[ -s "$h" ]] || printf 'WRN SERVICE HISTORY\n===================\n'
    printf '\n=== MAINTENANCE VISIT ===\n'
    printf 'Date UTC: %s\nHost: %s\nScript: %s\n' "$entry" "$(hostname -s)" "$VERSION"
    printf 'OS initial: %s\nOS final: %s\n' "$before" "$after"
    printf 'Optional applications: %s\nLeftover dependencies: %s\n' "$APP_RESULT" "$LEFT_RESULT"
    printf 'Core maintenance exit code: %s\n' "$rc"
    printf 'WAVE service: %s\n' "$(systemctl is-active hanwha-mediaserver.service 2>/dev/null || true)"
    printf 'Archive: %s\n' "$(findmnt -rn -M /mnt/sda -o SOURCE,FSTYPE,OPTIONS 2>/dev/null || true)"
    printf 'Updates policy: unchanged by this script (audit separately per WRN)\n'
    printf 'Recording/playback: manual verification required (NOT automatically verified)\n'
    printf 'Maintenance report: %s\n' "${WRN_LOG##*/}"
  } >> "$h" || return 1
  chown wave:wave "$h" && chmod 0644 "$h"
}

# Clear only known report files; leave the history, main script and unfamiliar files.
# Reports from current run are pruned only after the service entry exists and the run succeeds.
tidy_reports() {
  local mode="$1" h="$WRN_DIR/WRN-Service-History.txt" file n=0
  [[ -f "$h" && -s "$h" && ! -L "$h" ]] || { echo 'STOP: permanent service history required'; return 1; }
  local patterns=( -name 'WRN-Diagnostics_*.txt' -o -name 'WRN-Maintenance_*.txt'
     -o -name 'WRN-KB-Repair-Preview_*.txt' -o -name 'WRN-Remaining-OS-Space_*.txt'
     -o -name 'WRN-Optional-Apps-*.txt' -o -name 'WRN-Leftovers-*.txt'
     -o -name 'WRN-Autoremove-Updates-Audit_*.txt' -o -name 'WRN-App-Space-Estimate_*.txt'
     -o -name 'WRN-Downloads-Cleanup-Preview_*.txt' -o -name 'WRN-Service-History-Preview_*.txt' )
  mapfile -d '' to_remove < <(find "$WRN_DIR" -maxdepth 1 -type f ! -links +1 \( "${patterns[@]}" \) -print0)
  echo "=== REPORT TIDY ($mode): ${#to_remove[@]} known temporary reports ==="
  printf '  %s\n' "${to_remove[@]##*/}"
  if [[ "$mode" == preview ]]; then return 0; fi
  # Note that these old reports are being deleted, but preserve the most recent
  # maintenance transcript as a diagnostic audit when running automatically.
  for file in "${to_remove[@]}"; do
    [[ "$file" == "$WRN_LOG" ]] && continue
    [[ -f "$file" && ! -L "$file" && "$(stat -c %h "$file")" == 1 ]] || continue
    rm -f -- "$file" && ((n+=1)) || true
  done
  echo "Removed $n prior reports; preserved current log and permanent history."
}

# Explicit end-of-visit finalization, only AFTER technician confirms live video,
# playback and local desktop. This removes top-level regular files including the
# running script but never descends into directories and refuses symlinks.
finalize_visit() {
  local h="$WRN_DIR/WRN-Service-History.txt" f
  [[ -f "$h" && -s "$h" && ! -L "$h" && "$(stat -c %h "$h")" == 1 ]] || {
    echo 'STOP: verified permanent history required before deletion'; return 1;
  }
  safe_state || return 1
  if find "$WRN_DIR" -mindepth 1 -maxdepth 1 -type l | grep -q .; then
    echo 'STOP: symlinks present in maintenance folder; inspect manually'; return 1
  fi
  if find "$WRN_DIR" -mindepth 1 -maxdepth 1 -type d | grep -q .; then
    echo 'STOP: subdirectories present; inspect manually'; return 1
  fi
  # Document finalization itself before removing evidence.
  {
    printf '\n=== VISIT FINALIZED ===\nUTC: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'Technician confirmation: desktop, recording and playback confirmed before running --finalize\n'
    printf 'WAVE service: %s\n' "$(systemctl is-active hanwha-mediaserver.service 2>/dev/null || true)"
    printf 'Archive: %s\n' "$(findmnt -rn -M /mnt/sda -o SOURCE,FSTYPE,OPTIONS 2>/dev/null || true)"
    printf 'OS: %s\n' "$(df -h / | awk 'NR==2{print $5 " used, " $4 " free"}')"
  } >> "$h" || return 1
  chown wave:wave "$h" && chmod 0644 "$h" || return 1
  for f in "$WRN_DIR"/* "$WRN_DIR"/.[!.]* "$WRN_DIR"/..?*; do
    [[ -e "$f" ]] || continue
    [[ "$f" == "$h" ]] && continue
    [[ -f "$f" && ! -L "$f" && "$(stat -c %h "$f")" == 1 ]] || {
      echo "STOP: unexpected file type/hardlink, retained: $f"; return 1;
    }
  done
  find "$WRN_DIR" -mindepth 1 -maxdepth 1 -type f ! -name WRN-Service-History.txt -delete || return 1
  echo 'FINALIZED: maintenance folder now contains permanent WRN-Service-History.txt only.'
  ls -la "$WRN_DIR"
}

run_apply() {
  maintenance_log_setup || return 1
  echo "SUPERVISED TEST BUILD $VERSION; DO NOT DEPLOY TO FLEET"
  INITIAL_SPACE="$(df -h / | awk 'NR==2{print $5 " used, " $4 " free"}')"
  echo '=== BEFORE ==='
  safe_state || return 1
  df -h /
  collect_diagnostics || return 1
  safe_state || return 1
  snap_refresh_hold || return 1
  safe_state || return 1
  logging_kb || return 1
  safe_state || return 1
  fstab_kb || return 1
  safe_state || return 1
  snap_cleanup || return 1
  safe_state || return 1
  echo '=== AFTER ==='
  echo "FINAL Snap refresh schedule:"; snap refresh --time 2>&1 || true
  df -h /
  collect_diagnostics || return 1
  safe_state || return 1
  final_kb_summary || return 1
  echo '=== GUARDED OPTIONAL SOFTWARE STAGES ==='
  APP_RESULT=skipped
  LEFT_RESULT=skipped
  if package_stage APPLICATIONS apply; then APP_RESULT='completed-or-not-needed'; else APP_RESULT='blocked'; echo 'STOP: application stage failed its guard'; return 1; fi
  safe_state || return 1
  if package_stage LEFTOVERS apply; then LEFT_RESULT='completed-or-not-needed'; else LEFT_RESULT='blocked'; echo 'STOP: leftovers stage failed its guard'; return 1; fi
  safe_state || return 1
  echo '=== FINAL FREE SPACE ==='; df -h /
  record_service_history "$INITIAL_SPACE" "$(df -h / | awk 'NR==2{print $5 " used, " $4 " free"}')" 0 || return 1
  echo "PERMANENT HISTORY UPDATED — $WRN_DIR/WRN-Service-History.txt"
  echo 'PILOT COMPLETE: verify desktop and WAVE recording/playback, then run --finalize.'
  echo 'Logs and scripts are intentionally preserved until verification and finalization.' 
  echo "Maintenance log: $WRN_LOG"
}

if [[ "$MODE" == --package-preview ]]; then
  package_stage APPLICATIONS preview; package_stage LEFTOVERS preview
elif [[ "$MODE" == --tidy-preview ]]; then
  tidy_reports preview
elif [[ "$MODE" == --tidy ]]; then
  tidy_reports apply
elif [[ "$MODE" == --finalize ]]; then
  finalize_visit
elif [[ "$MODE" == --diagnose ]]; then
  collect_diagnostics
elif [[ "$MODE" == --preview ]]; then
  run_preview
else
  run_apply
fi
