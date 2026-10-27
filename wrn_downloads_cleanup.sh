#!/usr/bin/env bash
# WRN Downloads cleanup v0.3.0 — one-confirmation technician finalization.
# Protects WRN-Service-History.txt; no recording/database/archive changes.
set -Eeuo pipefail
MODE="${1:---preview}"
[[ $# -le 1 && ( "$MODE" == --preview || "$MODE" == --finalize ) ]] || { echo 'Usage: sudo bash wrn_downloads_cleanup.sh [--preview|--finalize]' >&2; exit 2; }
(( EUID == 0 )) || { echo 'Run using sudo.' >&2; exit 2; }
D='/home/wave/Downloads/maintenance'
H="$D/WRN-Service-History.txt"
[[ -d "$D" && ! -L "$D" ]] || { echo 'STOP: maintenance directory missing or symbolic link.' >&2; exit 1; }
[[ -f "$H" && -s "$H" && ! -L "$H" ]] || { echo 'STOP: valid nonempty service history required before final cleanup.' >&2; exit 1; }
[[ "$(stat -c %h -- "$H")" == 1 ]] || { echo 'STOP: service history has multiple hard links.' >&2; exit 1; }
# Only exact names and dedicated WRN report patterns, never arbitrary downloads.
patterns=( -name 'wrn_maintenance.sh' -o -name 'wrn_legacy.sh' -o -name 'wrn_os_archive_cleanup.sh' -o -name 'wrn_archive_cleanup.sh' -o -name 'wrn_archive_recovery.sh' -o -name 'wrn_fstab_dedup.sh' -o -name 'wrn_deep_os_cleanup.sh' -o -name 'wrn_snap_retirement.sh' -o -name 'wrn_remaining_os_space.sh' -o -name 'WRN-Maintenance-dev8-TEST.sh' -o -name 'WRN-Diagnostics_*.txt' -o -name 'WRN-Legacy-Diagnostics_*.txt' -o -name 'WRN-Maintenance_*.txt' -o -name 'WRN-KB-Repair-Preview_*.txt' -o -name 'WRN-Remaining-OS-Space_*.txt' -o -name 'WRN-Archive-Recovery_*.txt' -o -name 'WRN-Deep-OS-Cleanup_*.txt' -o -name 'WRN-Snap-Retirement_*.txt' -o -name 'WRN-Downloads-Cleanup-Preview_*.txt' -o -name 'WRN-Reports.tar.gz' )
mapfile -d '' CANDIDATES < <(find "$D" -maxdepth 1 -type f \( "${patterns[@]}" \) ! -name 'WRN-Service-History.txt' -print0)
SELF="$(readlink -f -- "$0")"
printf 'WRN maintenance finalization v0.3.0\n'
printf 'Permanent history: %s (PRESERVED)\n' "$H"
printf 'Temporary files: %d\n' "${#CANDIDATES[@]}"
for f in "${CANDIDATES[@]}"; do printf '  %s\n' "${f##*/}"; done
if [[ "$SELF" == "$D/wrn_downloads_cleanup.sh" ]]; then
  printf 'Cleanup helper: will remove itself after successful finalization.\n'
fi
if [[ "$MODE" == --preview ]]; then
  printf 'PREVIEW ONLY — no files changed.\n'
  exit 0
fi
[[ -t 0 ]] || { echo 'STOP: interactive terminal required.' >&2; exit 1; }
printf '\nFINAL CHECK: Save any needed reports, review the history, and verify WAVE recording/playback in the client.\n'
read -r -p 'All three complete? Finalize and remove the listed temporary files? [y/N]: ' ANSWER
[[ "$ANSWER" == y || "$ANSWER" == Y || "$ANSWER" == yes || "$ANSWER" == YES ]] || { echo 'Cancelled; no changes.'; exit 0; }
# Preserve verification as a technician attestation, not an automated WAVE check.
{
  printf '\nFINALIZATION — %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'Technician attestation: required reports saved/reviewed; WAVE recording and playback manually verified.\n'
  printf 'Temporary cleanup approved: %d selected files.\n' "${#CANDIDATES[@]}"
} >> "$H"
chown wave:wave "$H" 2>/dev/null || true
chmod 0644 "$H"
failures=0
for f in "${CANDIDATES[@]}"; do
  if [[ -f "$f" && ! -L "$f" && "$f" != "$H" ]]; then
    if ! rm -- "$f"; then printf 'ERROR: could not remove %s\n' "$f" >&2; failures=$((failures+1)); fi
  else
    echo "SKIPPED: file changed or absent: $f"
    failures=$((failures+1))
  fi
done
if (( failures )); then
  printf 'INCOMPLETE: %d file(s) require review. Helper retained. History preserved.\n' "$failures" >&2
  exit 1
fi
if [[ "$SELF" == "$D/wrn_downloads_cleanup.sh" && -f "$SELF" && ! -L "$SELF" ]]; then
  rm -- "$SELF"
fi
printf 'COMPLETE — permanent history retained: %s\n' "$H"
printf 'Folder contents:\n'; find "$D" -mindepth 1 -maxdepth 1 -printf '  %f\n'
