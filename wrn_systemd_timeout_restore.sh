#!/usr/bin/env bash
# Hanwha WRN — guarded global systemd timeout restoration, v1.0.0
# Ubuntu 22.04 / systemd 249. Preview by default; --apply explicitly writes.
# Does not reboot, restart WAVE, mount/unmount archives, or delete video.
set -Eeuo pipefail
export LC_ALL=C
umask 027

MODE="${1:---preview}"
if (( $# > 1 )) || [[ "$MODE" != --preview && "$MODE" != --apply && "$MODE" != --help ]]; then
  echo 'Usage: sudo bash wrn_systemd_timeout_restore.sh [--preview|--apply|--help]' >&2
  exit 2
fi
if [[ "$MODE" == --help ]]; then
  printf '%s\n' 'WRN systemd timeout restoration v1.0.0' \
    '  --preview  Read-only inspection (default)' \
    '  --apply    Back up config; replace ONLY exact 3s overrides with comments; reexec systemd and verify' \
    'No reboot, no WAVE restart, no archive mount/unmount, no recording deletion.'
  exit 0
fi
(( EUID == 0 )) || { echo 'ERROR: Run with sudo.' >&2; exit 2; }
. /etc/os-release
[[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 22.04 ]] || {
  echo "STOP: Expected Ubuntu 22.04; found ${PRETTY_NAME:-unknown}." >&2; exit 2;
}

DIR=/home/wave/Downloads/maintenance
[[ -d "$DIR" && ! -L "$DIR" ]] || { echo "STOP: Missing or symlinked report directory: $DIR" >&2; exit 2; }
CONFIG=/etc/systemd/system.conf
[[ -f "$CONFIG" && ! -L "$CONFIG" ]] || { echo 'STOP: Unexpected systemd config file.' >&2; exit 2; }
command -v python3 >/dev/null || { echo 'STOP: Python 3 required.' >&2; exit 2; }
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT="$DIR/WRN-Systemd-Timeout-Restore_${MODE#--}_${STAMP}_$$.txt"
( set -C; : > "$REPORT" ) || { echo 'STOP: Could not create report.' >&2; exit 2; }
chmod 640 "$REPORT"
chown wave:wave "$REPORT" || { echo 'STOP: Cannot give report to wave user.' >&2; exit 2; }
# Store all details in report; print only path on exit.
exec 3>&1
exec >> "$REPORT" 2>&1
finish() { rc=$?; echo "===== EXIT STATUS: $rc ====="; printf 'Report saved: %s\n' "$REPORT" >&3; exit "$rc"; }
trap finish EXIT

printf '===== WRN SYSTEMD TIMEOUT RESTORE v1.0.0 =====\nMode: %s\nDate: %s\nHost: %s\n' "$MODE" "$(date -Is)" "$(hostname)"
echo '===== BEFORE ====='
systemctl show -p DefaultTimeoutStartUSec -p DefaultTimeoutStopUSec
printf '\nActive settings in main config:\n'
grep -nE '^[[:space:]]*DefaultTimeout(Start|Stop)Sec[[:space:]]*=' "$CONFIG" || true
printf '\nAll systemd configuration sources:\n'
systemd-analyze cat-config systemd/system.conf 2>&1 | grep -E '(^# /|DefaultTimeout(Start|Stop)Sec)' || true
printf '\nArchive mounts (informational):\n'
for mountpoint in /mnt/sda /mnt/sdb; do findmnt -M "$mountpoint" || true; done
printf '\nWAVE status: '; systemctl is-active hanwha-mediaserver || true

# Only allow the exact observed 3-second overrides, or an already-default config.
# Reject conflicting overrides in drop-ins rather than giving a false success.
CHECK="$(python3 - "$CONFIG" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1]); text = p.read_text()
keys = ('DefaultTimeoutStartSec', 'DefaultTimeoutStopSec')
seen = {}
for key in keys:
    values = re.findall(r'^\s*'+key+r'\s*=\s*(\S.*?)\s*$', text, re.M)
    if values == ['3s']:
        seen[key] = '3s'
    elif values == []:
        seen[key] = 'unset'
    else:
        raise SystemExit('STOP: Unexpected '+key+' active values: '+repr(values))
if len(set(seen.values())) != 1:
    raise SystemExit('STOP: Mixed timeout settings: '+repr(seen))
print(next(iter(seen.values())))
PY
)" || exit 1

if [[ "$CHECK" == unset ]]; then
  echo 'No active 3s overrides in main config; no changes needed.'
  echo 'Effective settings shown above; investigate drop-ins if they are not 90s.'
  exit 0
fi

# Only proceed when effective settings agree with the two exact main-file overrides.
START="$(systemctl show -P DefaultTimeoutStartUSec)"
STOP="$(systemctl show -P DefaultTimeoutStopUSec)"
if [[ "$START" != 3s || "$STOP" != 3s ]]; then
  echo "STOP: Effective values are not 3s/3s ($START/$STOP). Possible drop-in override."
  exit 1
fi

# Check for active overrides in separate system.conf.d fragments.
python3 - <<'PY'
import pathlib, re
for root in ('/etc/systemd/system.conf.d', '/run/systemd/system.conf.d', '/usr/lib/systemd/system.conf.d', '/lib/systemd/system.conf.d'):
    d = pathlib.Path(root)
    if not d.is_dir(): continue
    for p in d.glob('*.conf'):
        try: s = p.read_text()
        except OSError: raise SystemExit('STOP: Cannot read '+str(p))
        if re.search(r'^\s*DefaultTimeout(?:Start|Stop)Sec\s*=', s, re.M):
            raise SystemExit('STOP: Timeout override in '+str(p)+'; review manually.')
PY

if [[ "$MODE" == --preview ]]; then
  echo 'PREVIEW: Eligible for restoring stock 90-second defaults.'
  echo 'No files changed. Apply with: sudo bash wrn_systemd_timeout_restore.sh --apply'
  exit 0
fi

BACKUP="/etc/systemd/system.conf.before-wrn-timeout-restore_${STAMP}.bak"
[[ ! -e "$BACKUP" ]] || { echo "STOP: Backup exists: $BACKUP"; exit 1; }
cp -a -- "$CONFIG" "$BACKUP"
echo "Backup: $BACKUP"

# Atomic replace preserves owner, mode and original file except for those two lines.
python3 - "$CONFIG" <<'PY'
import os, pathlib, re, shutil, sys, tempfile
p = pathlib.Path(sys.argv[1]); original = p.read_text()
new = original
for key in ('DefaultTimeoutStartSec', 'DefaultTimeoutStopSec'):
    pattern = r'(?m)^(\s*)'+key+r'=3s(\s*)$'
    new, count = re.subn(pattern, lambda m: m.group(1)+'# '+key+'=90s (systemd default; former 3s override removed)', new)
    if count != 1: raise SystemExit('STOP: Unexpected '+key+' lines; no config replacement.')
fd, tmp = tempfile.mkstemp(prefix='.system.conf.wrn-', dir=str(p.parent))
try:
    with os.fdopen(fd, 'w') as f:
        f.write(new)
        f.flush(); os.fsync(f.fileno())
    shutil.copystat(p, tmp)
    os.chown(tmp, p.stat().st_uid, p.stat().st_gid)
    os.replace(tmp, p)
except Exception:
    if os.path.exists(tmp): os.unlink(tmp)
    raise
PY

echo '===== RELOAD SYSTEMD MANAGER ====='
# daemon-reexec has been validated on WRN lab and customer; no unit restarts requested.
systemctl daemon-reexec
sleep 1
START="$(systemctl show -P DefaultTimeoutStartUSec)"
STOP="$(systemctl show -P DefaultTimeoutStopUSec)"
echo "Effective start timeout: $START"
echo "Effective stop timeout: $STOP"
if [[ "$START" != '1min 30s' || "$STOP" != '1min 30s' ]]; then
  echo 'WARNING: Expected 90s defaults were not observed; restoring backup.'
  cp -a -- "$BACKUP" "$CONFIG"
  systemctl daemon-reexec || true
  exit 1
fi

echo '===== POST-CHANGE SERVICE CHECK ====='
for service in hanwha-mediaserver NetworkManager cockpit.socket; do
  echo "$service: $(systemctl is-active "$service" 2>&1 || true)"
done
for mountpoint in /mnt/sda /mnt/sdb; do
  if findmnt -M "$mountpoint"; then :; else echo "NOTE: $mountpoint is not mounted (no mounting attempted)."; fi
done
printf 'SUCCESS: 3s global overrides removed; effective defaults are 90s.\n'
echo 'No reboot performed. Previous dmesg.service failed state may persist until a new successful run.'
