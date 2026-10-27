#!/usr/bin/env bash
# WRN fstab safe deduplication: preview by default, --apply for changes.
set -euo pipefail
MODE="${1:---preview}"
if [[ "$MODE" != "--preview" && "$MODE" != "--apply" ]]; then
  echo 'Usage: sudo bash wrn_fstab_dedup.sh [--preview|--apply]' >&2; exit 2
fi
if (( EUID != 0 )); then echo 'Run with sudo.' >&2; exit 2; fi
python3 - "$MODE" <<'PY'
import collections, datetime, os, pathlib, shutil, subprocess, sys, tempfile
mode = sys.argv[1]
fstab = pathlib.Path('/etc/fstab')
mounts = ['/mnt/sda','/mnt/sdb','/mnt/sdc','/mnt/sdd']
def run(*args):
    return subprocess.run(args, text=True, capture_output=True)
def stop(reason):
    raise SystemExit('STOP: ' + reason + ' No changes made.')
if not fstab.is_file(): stop('/etc/fstab missing.')
raw = fstab.read_text()
lines = raw.splitlines(keepends=True)
by_target = collections.defaultdict(list)
for n,line in enumerate(lines):
    stripped=line.strip()
    if not stripped or stripped.startswith('#'): continue
    fields = stripped.split()
    if len(fields) >= 2 and fields[1] in mounts:
        if len(fields) != 6: stop(f'Unexpected fstab fields on line {n+1}.')
        by_target[fields[1]].append((n,fields))
sda = by_target['/mnt/sda']
if not (1 <= len(sda) <= 2): stop(f'Expected 1 or 2 /mnt/sda entries, found {len(sda)}.')
for target in mounts:
    entries=by_target[target]
    if len(entries)>2: stop(f'More than two {target} entries.')
    if len(entries)==2 and entries[0][1] != entries[1][1]:
        stop(f'Conflicting entries for {target}; manual review needed.')
for target in mounts[1:]:
    for _, f in by_target[target]:
        if f != [f'/dev/{target.split("/")[-1]}',target,'ext4','defaults,nofail,x-systemd.device-timeout=5','0','0']:
            stop(f'Unexpected options for {target}; manual review needed.')
mount = run('findmnt','-n','-M','/mnt/sda','-o','SOURCE,FSTYPE')
if mount.returncode != 0: stop('Archive is not mounted; this tool only handles mounted archives.')
parts=mount.stdout.split()
if len(parts)!=2 or parts[1]!='ext4': stop('Archive mount is not ext4.')
actual_uuid = run('blkid','-s','UUID','-o','value','/dev/sda')
if actual_uuid.returncode or not actual_uuid.stdout.strip(): stop('Cannot read /dev/sda UUID.')
uuid=actual_uuid.stdout.strip()
source_uuid = run('findmnt','-n','-M','/mnt/sda','-o','UUID')
if source_uuid.returncode or source_uuid.stdout.strip()!=uuid:
    stop('Mounted archive UUID differs from /dev/sda UUID.')
for _,f in sda:
    source,target,fs,opts,dump,check=f
    if source not in ('/dev/sda',f'UUID={uuid}') or fs != 'ext4':
        stop('Archive fstab device/UUID or filesystem differs from mounted drive.')
    if opts not in ('defaults,nofail,x-systemd.device-timeout=5',
                    'defaults,nofail,x-systemd.device-timeout=60s',
                    'defaults,nofail,x-systemd.device-timeout=60s,x-systemd.mount-timeout=120s'):
        stop('Unrecognized /mnt/sda options; manual review needed.')
    if dump!='0' or check not in ('0','2'): stop('Unexpected dump/fsck fields.')
new_entry=(f'UUID={uuid} /mnt/sda ext4 '
           'defaults,nofail,x-systemd.device-timeout=60s,'
           'x-systemd.mount-timeout=120s 0 '+sda[0][1][5]+'\n')
remove=set()
for target in mounts:
    for n,_ in by_target[target][1:]: remove.add(n)
archive_idx=sda[0][0]
updated=''.join(new_entry if idx==archive_idx else '' if idx in remove else line
                for idx,line in enumerate(lines))
print(f'Archive UUID: {uuid}')
print(f'Archive: mounted at /mnt/sda ({parts[0]})')
for target in mounts:
    print(f'{target}: {len(by_target[target])} fstab entries -> {1 if by_target[target] else 0}')
print('Archive target entry:',new_entry.strip())
print('Changes needed:', 'yes' if updated!=raw else 'no')
if mode=='--preview':
    print('PREVIEW ONLY. No changes made. Run with --apply to update.')
    sys.exit(0)
if updated==raw:
    print('Already compliant; no changes made.')
    sys.exit(0)
# Validate the candidate before replacing live config.
fd,tmpname=tempfile.mkstemp(prefix='.fstab.wrn-',dir='/etc')
os.close(fd)
tmp=pathlib.Path(tmpname)
try:
    tmp.write_text(updated)
    shutil.copymode(fstab,tmp)
    validation=run('findmnt','--verify','--tab',str(tmp))
    if validation.returncode:
        print(validation.stdout,validation.stderr,file=sys.stderr)
        stop('Candidate fstab failed validation.')
    backup=pathlib.Path('/etc/fstab.wrn-dedup-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'.bak')
    if backup.exists(): stop('Backup filename collision.')
    shutil.copy2(fstab,backup)
    os.replace(tmp,fstab)
    print('Backup:',backup)
    print('Updated /etc/fstab; archive remains mounted.')
    print('Next: sudo systemctl daemon-reload')
except Exception:
    raise
finally:
    if tmp.exists(): tmp.unlink()
PY
