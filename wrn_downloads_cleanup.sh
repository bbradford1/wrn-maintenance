#!/usr/bin/env bash
# WRN maintenance finalization v0.4.0: auto service history, one confirmation.
# No WAVE, archive, mount, package or recording operations.
set -Eeuo pipefail
MODE="${1:---preview}"
[[ $# -le 1 && ( "$MODE" == --preview || "$MODE" == --finalize ) ]] || { echo 'Usage: sudo bash wrn_downloads_cleanup.sh [--preview|--finalize]' >&2; exit 2; }
(( EUID == 0 )) || { echo 'Run using sudo.' >&2; exit 2; }
D="${WRN_MAINT_DIR:-/home/wave/Downloads/maintenance}"
[[ -d "$D" && ! -L "$D" ]] || { echo 'STOP: maintenance directory missing or is a symlink.' >&2; exit 1; }
H="$D/WRN-Service-History.txt"
[[ ! -L "$H" ]] || { echo 'STOP: history symlink not allowed.' >&2; exit 1; }
if [[ -e "$H" ]]; then
  [[ -f "$H" && -s "$H" && $(stat -c %h -- "$H") == 1 ]] || { echo 'STOP: history not a regular, nonempty, singly linked file.' >&2; exit 1; }
fi
# This tool operates only within the dedicated maintenance directory.
# Deliberately narrow allowlist; excludes service history and unrelated downloads.
patterns=( -name 'wrn_maintenance.sh' -o -name 'wrn_legacy.sh' -o -name 'wrn_os_archive_cleanup.sh' -o -name 'wrn_archive_cleanup.sh' -o -name 'wrn_archive_recovery.sh' -o -name 'wrn_fstab_dedup.sh' -o -name 'wrn_deep_os_cleanup.sh' -o -name 'wrn_snap_retirement.sh' -o -name 'wrn_remaining_os_space.sh' -o -name 'WRN-Maintenance-dev8-TEST.sh' -o -name 'WRN-Diagnostics_*.txt' -o -name 'WRN-Legacy-Diagnostics_*.txt' -o -name 'WRN-Maintenance_*.txt' -o -name 'WRN-KB-Repair-Preview_*.txt' -o -name 'WRN-Remaining-OS-Space_*.txt' -o -name 'WRN-Archive-Recovery_*.txt' -o -name 'WRN-Deep-OS-Cleanup_*.txt' -o -name 'WRN-Snap-Retirement_*.txt' -o -name 'WRN-Downloads-Cleanup-Preview_*.txt' -o -name 'WRN-Service-History-Preview_*.txt' -o -name 'WRN-Reports.tar.gz' )
mapfile -d '' CANDIDATES < <(find "$D" -maxdepth 1 -type f \( "${patterns[@]}" \) ! -name 'WRN-Service-History.txt' -print0)
SELF="$(readlink -f -- "$0")"
# Create text draft entirely from on-disk logs; Python only reads reports in maintenance folder.
DRAFT="$(mktemp "$D/.wrn-history-draft.XXXXXXXX")"
trap 'rm -f -- "$DRAFT"' EXIT
if ! python3 - "$D" "$H" > "$DRAFT" <<'PY'
import pathlib, sys, re, hashlib, datetime
p=pathlib.Path(sys.argv[1]); history=pathlib.Path(sys.argv[2]);
logs=sorted((f for f in p.glob('WRN-Maintenance_*.txt') if f.is_file() and not f.is_symlink()),key=lambda x:x.stat().st_mtime)
if not logs: sys.exit('STOP: no WRN-Maintenance_*.txt apply log. Cannot produce verified automatic service entry; retain files and use normal supervised review.')
log=logs[-1]; txt=log.read_text(errors='replace'); fingerprint=hashlib.sha256(log.read_bytes()).hexdigest()
marker='Maintenance-log-SHA256: '+fingerprint
if history.exists() and marker in history.read_text(errors='replace'):
    sys.exit('STOP: this maintenance log is already in the permanent history. No new service event to record.')
if '=== FINAL KB / OPERATIONAL SUMMARY ===' not in txt:
    sys.exit('STOP: maintenance log lacks final operational summary. Do not finalize partial maintenance.')
# Only record observed facts. Unknown is not a pass.
start=txt.split('=== BEFORE ===',1)[-1].split('=== SNAP AUTOMATIC REFRESH HOLD ===',1)[0]
end=txt.split('=== AFTER ===',1)[-1]
percent=lambda s: re.search(r'(?m)^/dev/\S+\s+\S+\s+\S+\s+(\S+)\s+(\d+)%\s+/$',s)
a=percent(start); b=percent(end)
extract=lambda pat,s,default='not documented': (m.group(1).strip() if (m:=re.search(pat,s,re.M)) else default)
removed=re.findall(r'^Removing disabled Snap: (.+)$',txt,re.M)
backup=extract(r'^KB fstab correction verified; backup=(.+)$',txt)
wave=extract(r'^PASS WAVE: (.+)$',txt)
archive=extract(r'^PASS KB2: (.+)$',txt)
logging=extract(r'^PASS KB1: (.+)$',txt)
hold=extract(r'^PASS SNAP: (.+)$',txt)
notes=list(dict.fromkeys(re.findall(r'^(?:WARNING|REVIEW|NOTE):?[^\n]*',txt,re.M)))
diagnostics=sorted((f for f in p.glob('WRN-Diagnostics_*.txt') if f.is_file() and not f.is_symlink()),key=lambda x:x.stat().st_mtime)
last=diagnostics[-1].read_text(errors='replace') if diagnostics else ''
host=extract(r'^Hostname: (.+)$',last,extract(r'^Host: (.+)$',txt,'unknown'))
os=extract(r'^PRETTY_NAME="?([^"\n]+)',last,'unknown')
service=extract(r'(?m)^WAVE service: (.+)$',txt,'not documented')
now=datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%d %H:%M:%SZ')
print('=== SERVICE ENTRY ===')
print('UTC date:',now)
print('Hostname:',host)
print('OS:',os)
print('Source maintenance log:',log.name)
print(marker)
print('OS before:',f'{a.group(2)}% used, {a.group(1)} free' if a else 'not documented')
print('OS after:',f'{b.group(2)}% used, {b.group(1)} free' if b else 'not documented')
if a and b: print('OS utilization change:',f'{int(a.group(2))-int(b.group(2))} percentage points lower')
print('Logging:',logging)
print('Archive/fstab:',archive)
print('Fstab backup:',backup)
print('Disabled Snap revisions removed:',len(removed))
if removed: print('Snap revisions:', '; '.join(removed))
print('Snap automatic refresh:',hold)
print('WAVE status from logs:',wave if wave!='not documented' else service)
print('Recording/playback:', 'technician confirmation required at finalization')
if notes:
    print('Warnings and notes (from maintenance log):')
    for n in notes[:18]: print(' -',n[:350])
print('Evidence files available at finalization:',', '.join(f.name for f in ([log]+diagnostics[-2:])) )
PY
then
  echo 'STOP: automatic service-history draft failed; no files deleted.' >&2; exit 1
fi
printf 'WRN Service History / Cleanup v0.4.0 — %s\n' "$MODE"
printf '\nProposed permanent service entry:\n'
cat "$DRAFT"
printf '\nPreserve: %s\n' "$H"
printf 'Temporary files to remove: %d\n' "${#CANDIDATES[@]}"
for f in "${CANDIDATES[@]}"; do printf '  %s\n' "${f##*/}"; done
if [[ "$MODE" == --preview ]]; then
  echo 'PREVIEW ONLY. No history changes, no files deleted.'
  exit 0
fi
[[ -t 0 ]] || { echo 'STOP: interactive terminal required.' >&2; exit 1; }
read -r -p 'Reports reviewed and WAVE recording/playback verified? Finalize? [y/N]: ' ANSWER
[[ "$ANSWER" == y || "$ANSWER" == Y || "$ANSWER" == yes || "$ANSWER" == YES ]] || { echo 'Cancelled; no changes.'; exit 0; }
# Recheck obvious path changes and preserve the history via atomic replacement.
[[ ! -L "$H" ]] || { echo 'STOP: history path changed.' >&2; exit 1; }
if [[ -e "$H" ]]; then [[ -f "$H" && $(stat -c %h -- "$H") == 1 ]] || exit 1; fi
python3 - "$DRAFT" "$H" <<'PY'
import pathlib,os,sys,tempfile
entry=pathlib.Path(sys.argv[1]).read_text(); h=pathlib.Path(sys.argv[2])
old=h.read_text(errors='replace') if h.exists() else 'WRN SERVICE HISTORY\n===================\n'
marker=next(s for s in entry.splitlines() if s.startswith('Maintenance-log-SHA256: '))
if marker in old: sys.exit('STOP: duplicate service entry')
entry=entry.replace('Recording/playback: technician confirmation required at finalization','Recording/playback: manually confirmed by technician at finalization')
new=old.rstrip()+'\n\n'+entry.rstrip()+'\n\n'
fd,tmp=tempfile.mkstemp(dir=str(h.parent),prefix='.wrn-history-write.')
try:
    with os.fdopen(fd,'w') as f:
        f.write(new); f.flush(); os.fsync(f.fileno())
    if h.exists():
        st=h.stat(); os.chown(tmp,st.st_uid,st.st_gid); os.chmod(tmp,st.st_mode & 0o777)
    else:
        import pwd
        
        try:
            w=pwd.getpwnam('wave'); os.chown(tmp,w.pw_uid,w.pw_gid)
        except KeyError:
            if 'WRN_MAINT_DIR' not in os.environ: raise
        os.chmod(tmp,0o644)
    os.replace(tmp,h)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PY
failures=0
for f in "${CANDIDATES[@]}"; do
  [[ -f "$f" && ! -L "$f" && $(stat -c %h -- "$f") == 1 ]] || { echo "SKIP changed/linked: $f"; failures=$((failures+1)); continue; }
  rm -- "$f" || { echo "FAILED removal: $f"; failures=$((failures+1)); }
done
if (( failures )); then echo "INCOMPLETE: $failures temporary items remain; permanent history saved, helper retained." >&2; exit 1; fi
if [[ "$SELF" == "$D/wrn_downloads_cleanup.sh" && -f "$SELF" && ! -L "$SELF" ]]; then rm -- "$SELF"; fi
echo "FINALIZED: $H"; find "$D" -mindepth 1 -maxdepth 1 -printf '  %f\n'
