#!/usr/bin/env bash
# Downloads cleanup helper v0.1: preview by default; explicitly authorized deletion.
set -Eeuo pipefail
MODE="${1:---preview}"
[[ $# -le 1 && ( "$MODE" == --preview || "$MODE" == --delete ) ]] || { echo 'Usage: sudo bash wrn_downloads_cleanup.sh [--preview|--delete]' >&2; exit 2; }
(( EUID == 0 )) || { echo 'Use sudo'; exit 2; }
D=/home/wave/Downloads/maintenance
[[ -d "$D" && ! -L "$D" ]] || exit 2
# Select only known exact tool names and generated report prefixes.
patterns=( -name 'wrn_maintenance.sh' -o -name 'wrn_legacy.sh' -o -name 'wrn_os_archive_cleanup.sh' -o -name 'wrn_archive_cleanup.sh' -o -name 'wrn_archive_recovery.sh' -o -name 'wrn_fstab_dedup.sh' -o -name 'wrn_deep_os_cleanup.sh' -o -name 'wrn_snap_retirement.sh' -o -name 'wrn_remaining_os_space.sh' -o -name 'WRN-Maintenance-dev8-TEST.sh' -o -name 'WRN-*.txt' -o -name 'WRN-Reports.tar.gz' )
echo 'IMPORTANT: export any reports needed for troubleshooting before deleting.'
find "$D" -maxdepth 1 -type f \( "${patterns[@]}" \) -print
if [[ "$MODE" == --preview ]]; then echo 'PREVIEW ONLY. Nothing deleted.'; exit 0; fi
[[ -t 0 ]] || { echo 'Interactive approval required' >&2; exit 2; }
read -r -p 'Type DELETE-REPORTS to remove the listed WRN files: ' answer
[[ "$answer" == DELETE-REPORTS ]] || { echo 'Cancelled'; exit 1; }
find "$D" -maxdepth 1 -type f \( "${patterns[@]}" \) -delete
echo 'Cleanup complete. Maintenance folder retained.'
