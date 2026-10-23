#!/usr/bin/env bash
# WRN Archive Recovery v1.1 - supervised Ubuntu 22.04 / ext4 recovery
# Standalone; never restarts WAVE, reboots, cleans recordings, or repairs automatically.
set -Eeuo pipefail
umask 022
MODE="${1:---inspect}"
case "$MODE" in --inspect|--recover|--help) ;; *) echo 'Usage: sudo bash wrn_archive_recovery.sh [--inspect|--recover|--help]' >&2; exit 2;; esac
if [[ $MODE == --help ]]; then
  echo 'Usage: sudo bash wrn_archive_recovery.sh [--inspect|--recover]'
  echo '  --inspect  Read-only diagnostics; default.'
  echo '  --recover Explicit interactive journal recovery, safe fstab update and mount.'
  exit 0
fi
[[ $EUID -eq 0 ]] || { echo 'Run using sudo.' >&2; exit 1; }
for cmd in lsblk blkid findmnt systemctl tune2fs smartctl python3; do command -v "$cmd" >/dev/null || { echo "Missing required command: $cmd" >&2; exit 1; }; done
mkdir -p /home/wave/Downloads
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT="/home/wave/Downloads/WRN-Archive-Recovery_${STAMP}_${MODE#--}.txt"
touch "$REPORT"; chmod 644 "$REPORT"
exec > >(tee -a "$REPORT") 2>&1
log(){ printf '\n=== %s ===\n' "$*"; }
stop(){ echo "STOP: $*"; echo "Report: $REPORT"; exit 1; }
trap 'rc=$?; if ((rc)); then echo "Recovery utility exited with status $rc. See $REPORT"; fi' EXIT
log 'WRN ARCHIVE RECOVERY v1.1'
echo "Mode: $MODE | $(date -Is) | host $(hostname) | Report: $REPORT"
echo 'No WAVE restarts, reboots, or recording removal. Inspect mode makes no filesystem changes.'
MNT=/mnt/sda
DEV=/dev/sda
[[ -b "$DEV" ]] || stop "$DEV missing. Do not attempt filesystem recovery; inspect hardware first."
TYPE="$(blkid -s TYPE -o value "$DEV" 2>/dev/null || true)"
UUID="$(blkid -s UUID -o value "$DEV" 2>/dev/null || true)"
SIZE="$(lsblk -dnbo SIZE "$DEV" | tr -d ' ')"
log 'IDENTITY AND CURRENT MOUNT'
lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,UUID,MOUNTPOINTS "$DEV"
findmnt -M "$MNT" || true
findmnt -S "$DEV" || true
df -hT / "$MNT" || true
printf 'Device=%s UUID=%s Type=%s bytes=%s\n' "$DEV" "$UUID" "$TYPE" "$SIZE"
[[ "$TYPE" == ext4 ]] || stop "$DEV is not ext4; no repair supported."
[[ "$UUID" =~ ^[0-9a-fA-F-]{36}$ ]] || stop 'Cannot verify archive UUID.'
(( SIZE >= 3000000000000 && SIZE <= 24000000000000 )) || stop 'Device size outside expected archive range (3–24 TB). No automatic selection.'
# Strong guard against using /dev/sda when OS or other media mounted there.
OS_DEV="$(findmnt -no SOURCE / | sed 's/\[.*//')"
[[ "$OS_DEV" != "$DEV" ]] || stop 'Selected device is OS root.'
DEV_MOUNT="$(findmnt -n -S "$DEV" -o TARGET 2>/dev/null || true)"
if [[ -n "$DEV_MOUNT" && "$DEV_MOUNT" != "$MNT" ]]; then stop "$DEV mounted somewhere unexpected: $DEV_MOUNT"; fi
log 'FSTAB / GENERATED MOUNT SETTINGS'
grep -vE '^[[:space:]]*(#|$)' /etc/fstab || true
systemctl show mnt-sda.mount -p ActiveState -p Result -p TimeoutUSec -p What -p Where || true
log 'EXT4 SUPERBLOCK (READ ONLY)'
tune2fs -l "$DEV" 2>&1 | grep -Ei 'Filesystem state:|Filesystem features:|Error count:|Last mount time:|Last write time:|Last checked:' || true
log 'DRIVE SMART (READ ONLY)'
smartctl -H -A "$DEV" 2>&1 | grep -Ei 'overall-health|SMART Health Status|Reallocated_Sector|Current_Pending|Offline_Uncorrect|UDMA_CRC|Command_Timeout|Power_Off_Retract|Temperature_Celsius|Error:' || true
log 'CURRENT BOOT / HISTORIC MOUNT FAILURE SIGNALS'
journalctl -b -k --no-pager 2>/dev/null | grep -Ei '(EXT4-fs.*sda|JBD2|ata[0-9].*(reset|error|failed)|I/O error.*sda|Buffer I/O error)' | tail -60 || true
journalctl -b -u mnt-sda.mount --no-pager -o short-iso 2>/dev/null | tail -60 || true
log 'ROOT STORAGE AND WAVE SERVICE'
df -h /; systemctl is-active hanwha-mediaserver || true
if [[ "$MODE" == --inspect ]]; then
  echo "INSPECT COMPLETE. No repair or mount attempted. Report: $REPORT"
  exit 0
fi
log 'SUPERVISED RECOVERY PREFLIGHT'
[[ -z "$DEV_MOUNT" ]] || stop 'Archive is already mounted. No repair needed; leaving live recordings untouched.'
# Refuse when expected mountpoint is occupied by any mount, including other media.
[[ -z "$(findmnt -n -M "$MNT" -o SOURCE 2>/dev/null || true)" ]] || stop 'Mount point occupied by a different source.'
[[ -d "$MNT" ]] || stop "$MNT directory missing."
# Require a single, uniquely matching fstab line and validate possible conflicting duplicate targets.
python3 - "$UUID" <<'PY' || stop 'fstab preflight failed; no changes.'
import sys
u=sys.argv[1]; entries=[]
for line in open('/etc/fstab'):
    s=line.strip()
    if not s or s.startswith('#'): continue
    p=s.split()
    if len(p)>=4 and p[1]=='/mnt/sda': entries.append(p)
if len(entries)!=1: raise SystemExit('Expected exactly one /mnt/sda fstab entry')
p=entries[0]
if p[0] not in ('/dev/sda','UUID='+u,'/dev/disk/by-uuid/'+u): raise SystemExit('Unexpected existing /mnt/sda source '+p[0])
if p[2] not in ('ext4','auto'): raise SystemExit('Unexpected filesystem type '+p[2])
print('Fstab entry eligible for update:', ' '.join(p))
PY
log 'HUMAN AUTHORIZATION REQUIRED'
echo "The drive $DEV ($UUID) is UNMOUNTED. Journal-only e2fsck will WRITE filesystem metadata."
echo 'It can change incomplete recording transactions. This is NOT a backup, and not a full fsck repair.'
echo 'Proceed only after customer approval and if loss of unrecovered footage is acceptable.'
[[ -t 0 ]] || stop 'Interactive terminal required. Not running filesystem repair unattended.'
read -r -p 'Type RECOVER to authorize ext4 journal replay and archive mount: ' AUTH
[[ "$AUTH" == RECOVER ]] || stop 'User did not authorize recovery.'
log 'JOURNAL RECOVERY (MUTATING /dev/sda)'
command -v e2fsck >/dev/null || stop 'e2fsck missing'
command -v script >/dev/null || stop 'util-linux script (pseudo-terminal) missing; no repair attempted.'
# Reverify nothing mounted immediately before write.
[[ -z "$(findmnt -n -S "$DEV" -o TARGET 2>/dev/null || true)" ]] || stop 'Device mounted during preflight; abort.'
# The outer report capture (tee/process substitution) is not a real terminal.
# e2fsck can refuse the repair with "need terminal for interactive repairs".
# Run journal-only e2fsck inside a dedicated pseudo-terminal, preserving interactive
# prompts and streaming the child's actual output to the existing report via tee.
# `script -e` propagates e2fsck's exit status; /dev/null prevents a second log.
# DEV is fixed to /dev/sda after strict identity/mount checks above.
set +e
script -q -e -c 'e2fsck -E journal_only /dev/sda' /dev/null
RC=$?
set -e
# e2fsck exit bits: 1 corrected, 2 reboot needed; all others treated as failure.
(( (RC & ~1) == 0 )) || stop "Journal recovery returned status $RC; manual intervention required. Do not mount."
FEATURES="$(tune2fs -l "$DEV" | sed -n 's/^Filesystem features:[[:space:]]*//p')"
STATE="$(tune2fs -l "$DEV" | sed -n 's/^Filesystem state:[[:space:]]*//p')"
echo "Filesystem state: $STATE; features: $FEATURES"
[[ "$STATE" == clean && " $FEATURES " != *' needs_recovery '* ]] || stop 'Journal recovery state uncertain; do not mount or edit fstab.'
log 'FSTAB BACKUP AND SAFE UPDATE'
BACKUP="/etc/fstab.wrn-archive-recovery-${STAMP}.bak"
cp -a /etc/fstab "$BACKUP"
echo "Backup: $BACKUP"
python3 - "$UUID" <<'PY' || { cp -a "$BACKUP" /etc/fstab; stop 'fstab update failed; backup restored.'; }
from pathlib import Path
import sys,os,tempfile
u=sys.argv[1]; path=Path('/etc/fstab'); lines=path.read_text().splitlines(keepends=True); found=[]
for i,line in enumerate(lines):
    s=line.strip()
    if s and not s.startswith('#'):
        p=s.split()
        if len(p)>=4 and p[1]=='/mnt/sda': found.append((i,p))
if len(found)!=1: raise SystemExit('Unexpected count of /mnt/sda entries')
i,p=found[0]
if p[0] not in ('/dev/sda','UUID='+u,'/dev/disk/by-uuid/'+u) or p[2] not in ('auto','ext4'): raise SystemExit('fstab changed unexpectedly')
opts=[o for o in p[3].split(',') if o and not o.startswith(('x-systemd.device-timeout=','x-systemd.mount-timeout='))]
# Always require minimum timeouts; no reduction of existing longer durations.
def duration(o):
    try:
        v=o.split('=',1)[1]
        if v.endswith('min'): return float(v[:-3])*60
        if v.endswith('ms'): return float(v[:-2])/1000
        if v.endswith('s'): return float(v[:-1])
        return float(v)
    except Exception: return None
for key,minimum in [('x-systemd.device-timeout=',60),('x-systemd.mount-timeout=',120)]:
    old=[o for o in p[3].split(',') if o.startswith(key)]
    vals=[duration(o) for o in old]
    if any(v is None for v in vals): raise SystemExit('Unrecognized timeout; refuse to overwrite')
    opts.append(key+str(int(max([minimum]+vals)))+'s')
p[0]='UUID='+u; p[2]='ext4'; p[3]=','.join(opts)
lines[i]=' '.join(p)+'\n'
new=''.join(lines)
fd,tmp=tempfile.mkstemp(prefix='.fstab.wrn-',dir='/etc')
try:
    os.fchmod(fd,0o644)
    with os.fdopen(fd,'w') as f: f.write(new)
    os.replace(tmp,str(path))
finally:
    if os.path.exists(tmp): os.unlink(tmp)
print('Updated /mnt/sda:',lines[i].strip())
PY
# findmnt --verify may return warnings from unused sdb-d entries. Require no errors.
VERIFY="$(findmnt --verify 2>&1 || true)"
echo "$VERIFY"
if ! grep -Eq '0 parse errors, 0 errors' <<< "$VERIFY"; then
  cp -a "$BACKUP" /etc/fstab
  stop 'fstab validation did not confirm zero errors; backup restored, no mount attempted.'
fi
log 'RELOAD MOUNT UNIT AND MOUNT ONLY /mnt/sda'
systemctl daemon-reload
systemctl reset-failed mnt-sda.mount || true
systemctl start mnt-sda.mount || stop 'Mount attempt failed; inspect journal. Do not reboot.'
SRC="$(findmnt -n -M "$MNT" -o SOURCE || true)"
MOUNT_UUID="$(findmnt -n -M "$MNT" -o UUID || true)"
[[ -n "$SRC" && "$MOUNT_UUID" == "$UUID" ]] || stop "Mounted source/UUID check failed (source=$SRC UUID=$MOUNT_UUID)."
log 'POST-RECOVERY VERIFICATION'
findmnt -M "$MNT"
df -hT / "$MNT"
systemctl show mnt-sda.mount -p ActiveState -p Result -p TimeoutUSec
systemctl is-active hanwha-mediaserver || true
echo 'SUCCESS: mounted expected UUID. Check live WAVE recording and playback in client.'
echo 'No WAVE restart, reboot, OS fallback cleanup, or automatic full filesystem repair was performed.'
echo "Report: $REPORT"
