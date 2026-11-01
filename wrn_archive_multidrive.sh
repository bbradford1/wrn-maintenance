#!/usr/bin/env bash
# WRN multi-archive fstab normalization - dev.19.5 LAB PILOT.
# No disk mounting, unmounting, fsck, video deletion, server restart or formatting.
set -Eeuo pipefail
export LC_ALL=C
MODE=${1:---audit}
[[ $# -eq 1 && ( "$MODE" == --audit || "$MODE" == --apply ) ]] || { echo 'Usage: sudo bash wrn_archive_multidrive.sh [--audit|--apply]' >&2; exit 2; }
[[ ${EUID:-$(id -u)} == 0 ]] || { echo 'STOP: sudo required' >&2; exit 2; }
. /etc/os-release
[[ ${ID:-} == ubuntu && ${VERSION_ID:-} == 22.04 ]] || { echo 'STOP: Ubuntu 22.04 only' >&2; exit 2; }
for c in awk blkid findmnt readlink mktemp cp cmp mv chmod chown lsblk tr; do command -v "$c" >/dev/null || { echo "STOP: missing $c" >&2; exit 2; }; done
fstab=/etc/fstab
[[ -f $fstab && ! -L $fstab ]] || { echo 'STOP: fstab not a regular file' >&2; exit 2; }
[[ -d /mnt && ! -L /mnt ]] || { echo 'STOP: unexpected /mnt' >&2; exit 2; }
# Enforce unique archive targets AND sources before any edit.
awk '$1 !~ /^#/ && NF>=4 && $2 ~ /^\/mnt\/sd[a-d]$/ {if (++targets[$2]>1) bad=1; if(++sources[$1]>1) bad=1} END{exit bad}' "$fstab" || { echo 'STOP: duplicate archive target or source; resolve using dedicated guided dedup, then rerun'; exit 1; }
shopt -s nullglob
mounts=( )
for mp in /mnt/sda /mnt/sdb /mnt/sdc /mnt/sdd; do
  if findmnt -rn -M "$mp" >/dev/null 2>&1; then mounts+=("$mp"); fi
done
(( ${#mounts[@]} )) || { echo 'STOP: no mounted archive drives'; exit 1; }
# Need sda even when multiple drives, consistent with Gen2 factory service.
[[ -n $(findmnt -rn -M /mnt/sda -o SOURCE 2>/dev/null || :) ]] || { echo 'STOP: primary /mnt/sda not mounted'; exit 1; }
printf '=== MULTI-DRIVE ARCHIVE PREFLIGHT (%s) ===\n' "$MODE"
normalized=0
expected=0
replacements=$(mktemp) || exit 1
trap 'rm -f -- "$replacements"' EXIT
for mp in /mnt/sda /mnt/sdb /mnt/sdc /mnt/sdd; do
  count=$(awk -v mp="$mp" '$1 !~ /^#/ && $2==mp {n++} END{print n+0}' "$fstab")
  if ! findmnt -rn -M "$mp" >/dev/null 2>&1; then
    if (( count )); then
      spec=$(awk -v mp="$mp" '$1 !~ /^#/ && $2==mp {print $1;exit}' "$fstab")
      # A real configured device present but unmounted is an unresolved fault; never edit other disks.
      resolved=''
      case "$spec" in UUID=*) resolved=$(blkid -U "${spec#UUID=}" 2>/dev/null || :) ;; /dev/*) [[ -b $spec ]] && resolved=$spec ;; esac
      if [[ -n $resolved ]]; then
        echo "STOP: expected archive $mp has a present device but is NOT mounted ($spec); investigate first"
        exit 1
      fi
      echo "WARNING: optional archive $mp is configured but its device is unavailable ($spec). Not edited."
    fi
    continue
  fi
  ((expected+=1))
  [[ $count == 1 ]] || { echo "STOP: mounted $mp requires exactly one fstab entry; found $count"; exit 1; }
  src=$(findmnt -rn -M "$mp" -o SOURCE)
  fs=$(findmnt -rn -M "$mp" -o FSTYPE)
  opts_live=$(findmnt -rn -M "$mp" -o OPTIONS)
  [[ $src == /dev/* && -b $src && $fs == ext4 && ,$opts_live, == *,rw,* ]] || { echo "STOP: $mp has an unexpected device/filesystem or is not read-write"; exit 1; }
  dev=$(readlink -f "$src")
  [[ -b $dev ]] || { echo "STOP: $mp device resolution failed"; exit 1; }
  uuid=$(blkid -s UUID -o value "$dev" 2>/dev/null || :)
  type=$(blkid -s TYPE -o value "$dev" 2>/dev/null || :)
  [[ $type == ext4 && $uuid =~ ^[0-9A-Fa-f-]{36}$ ]] || { echo "STOP: $mp ext4 UUID invalid"; exit 1; }
  osdev=$(findmnt -rn -M / -o SOURCE)
  [[ $(readlink -f "$osdev") != "$dev" ]] || { echo "STOP: $mp is OS drive!"; exit 1; }
  old=$(awk -v mp="$mp" '$1 !~ /^#/ && $2==mp {print;exit}' "$fstab")
  read -r oldspec oldmp oldtype oldopts dump pass extra <<< "$old"
  [[ -z ${extra:-} && $oldmp == "$mp" && ( $oldtype == ext4 || $oldtype == auto ) ]] || { echo "STOP: unexpected $mp fstab structure"; exit 1; }
  # A factory whole-disk fstab reference may identify the parent of a mounted
  # partition-backed ext4 archive (e.g. /dev/sdb -> /dev/sdb1).  Accept this
  # ONLY when the mounted block device is a direct child of that exact disk.
  # A device-name prefix match alone is never sufficient.
  if [[ $oldspec != "$src" && $oldspec != "$dev" && $oldspec != "UUID=$uuid" ]]; then
    [[ $oldspec == /dev/* && -b $oldspec ]] || { echo "STOP: $mp configured device differs from mounted source"; exit 1; }
    parent=$(readlink -f "$oldspec")
    [[ $(lsblk -dn -o TYPE "$dev" | tr -d '[:space:]') == part ]] || { echo "STOP: $mp mismatch is not a partition-backed archive"; exit 1; }
    parent_name=$(lsblk -dn -o PKNAME "$dev" | tr -d '[:space:]')
    [[ -n $parent_name && -b /dev/$parent_name && $(readlink -f "/dev/$parent_name") == "$parent" ]] || {
      echo "STOP: $mp mounted partition does not belong to configured parent disk"; exit 1;
    }
    [[ $(lsblk -dn -o TYPE "$parent" | tr -d '[:space:]') == disk ]] || { echo "STOP: $mp configured parent is not a physical disk"; exit 1; }
    # Reject disks with a filesystem of their own, and parent disks used for
    # the OS or any other mounted filesystem. No mount changes are attempted.
    [[ -z $(blkid -s TYPE -o value "$parent" 2>/dev/null || :) ]] || { echo "STOP: $mp parent disk has its own filesystem"; exit 1; }
    [[ $(readlink -f "$osdev") != "$parent" ]] || { echo "STOP: $mp parent is the OS disk"; exit 1; }
    if findmnt -rn -S "$parent" >/dev/null 2>&1; then
      echo "STOP: $mp parent disk is also mounted"; exit 1
    fi
    echo "  VERIFIED PARTITION-BACKED ARCHIVE: $oldspec is the direct parent of $dev"
  fi
  [[ $oldopts =~ ^[a-zA-Z0-9._,=-]+$ && ${dump:-0} =~ ^[0-9]+$ && ${pass:-0} =~ ^[0-9]+$ ]] || { echo "STOP: invalid $mp options or trailing fields"; exit 1; }
  # Detect aliases pointing at the same ext4 UUID, including cross-mounted disks.
  for prior in "${seen_uuids[@]:-}"; do [[ $prior != "$uuid" ]] || { echo "STOP: same UUID on multiple archive mounts"; exit 1; }; done
  seen_uuids+=("$uuid")
  dt=60; mt=120; keep=()
  IFS=, read -r -a tokens <<< "$oldopts"
  for o in "${tokens[@]}"; do
    case $o in
      x-systemd.device-timeout=*) v=${o#*=}; [[ $v =~ ^[0-9]+s?$ ]] || { echo "STOP: unsupported device timeout on $mp"; exit 1; }; v=${v%s}; (( 10#$v > dt )) && dt=$((10#$v)) ;;
      x-systemd.mount-timeout=*) v=${o#*=}; [[ $v =~ ^[0-9]+s?$ ]] || { echo "STOP: unsupported mount timeout on $mp"; exit 1; }; v=${v%s}; (( 10#$v > mt )) && mt=$((10#$v)) ;;
      nofail) ;;
      *) keep+=("$o") ;;
    esac
  done
  joined=$(IFS=,; echo "${keep[*]}")
  [[ -n $joined ]] || joined=defaults
  target="UUID=$uuid $mp ext4 $joined,nofail,x-systemd.device-timeout=${dt}s,x-systemd.mount-timeout=${mt}s ${dump:-0} ${pass:-0}"
  printf 'DRIVE: %-9s device=%-18s UUID=%s\n' "$mp" "$dev" "$uuid"
  if [[ $old != "$target" ]]; then
    printf '  CURRENT: %s\n  PROPOSED: %s\n' "$old" "$target"
    ((normalized+=1))
  else echo '  PASS: already normalized'; fi
  # TSV records are safe since the validated lines contain no tab characters.
  printf '%s\t%s\n' "$mp" "$target" >> "$replacements"
done
printf 'RESULT: %d mounted archives; %d corrections proposed\n' "$expected" "$normalized"
[[ $MODE == --apply && $normalized -gt 0 ]] || { echo 'No modifications made.'; exit 0; }
backup="/etc/fstab.wrn-dev19.$(date -u +%Y%m%dT%H%M%SZ).bak"
draft=$(mktemp /etc/.fstab.wrn19.XXXXXXXX) || exit 1
trap 'rm -f -- "$replacements" "$draft"' EXIT
cp -a -- "$fstab" "$backup" || exit 1
awk -F '\t' 'NR==FNR {r[$1]=$2; next} {split($0,f,/[[:space:]]+/); if(f[1] !~ /^#/ && f[2] in r) print r[f[2]]; else print $0}' "$replacements" "$fstab" > "$draft"
chmod --reference="$fstab" "$draft" && chown --reference="$fstab" "$draft" || exit 1
[[ $(awk '$1 !~ /^#/ && $2 ~ /^\/mnt\/sd[a-d]$/ {n++} END{print n+0}' "$draft") -ge $expected ]] || { echo 'STOP: missing archive entries in staged fstab'; exit 1; }
findmnt --verify --tab-file "$draft" >/dev/null 2>&1 || { echo 'STOP: staged fstab verification failed; original untouched'; exit 1; }
cmp -s "$fstab" "$backup" || { echo 'STOP: fstab changed during staging'; exit 1; }
mv -f -- "$draft" "$fstab" || exit 1
if ! findmnt --verify --tab-file "$fstab" >/dev/null 2>&1; then
  cp -a -- "$backup" "$fstab" || echo 'CRITICAL: rollback failed'
  echo 'STOP: installed fstab verification failed; rolled back'; exit 1
fi
echo "PASS: updated $normalized mounted archive fstab entries; backup=$backup"
echo 'NOTICE: No active mount changed. Reboot persistence validation required.'
