#!/usr/bin/env bash
# Hanwha WRN installer v1.0.0-dev.17-TECH-WORKFLOW-PILOT
# Download-only by default. Never starts maintenance, recovery or cleanup.
# Production: bash installer.sh
# Lab-only: bash installer.sh --local-source PATH --target-dir PATH
set -Eeuo pipefail
export LC_ALL=C
umask 077
VERSION='1.0.0-dev.17-TECH-WORKFLOW-PILOT'
BASE_URL='https://raw.githubusercontent.com/bbradford1/wrn-maintenance/technician-workflow-pilot'
LOCAL_SOURCE=''
TARGET_DIR=''
OFFLINE_BUNDLE='' 
fail(){ echo "STOP: $*" >&2; exit 1; }
usage(){ printf '%s\n' 'Usage: bash installer.sh --offline-bundle ABSOLUTE_DIR' 'Or: bash installer.sh --local-source DIR --target-dir DIR' 'Default (no flags) downloads from GitHub; use offline-bundle to avoid network.'; }
while (( $# )); do
  case "$1" in
    --offline-bundle) (( $# >= 2 )) || fail 'Missing --offline-bundle path'; OFFLINE_BUNDLE="$2"; shift 2 ;;
    --local-source) (( $# >= 2 )) || fail 'Missing --local-source path'; LOCAL_SOURCE="$2"; shift 2 ;;
    --target-dir) (( $# >= 2 )) || fail 'Missing --target-dir path'; TARGET_DIR="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) fail "Unexpected argument: $1" ;;
  esac
done
(( EUID != 0 )) || fail 'Run installer as normal wave user (not sudo).'
[[ -r /etc/os-release ]] || fail 'Missing OS release information.'
. /etc/os-release
[[ "${ID:-}" == ubuntu ]] || fail "Unsupported OS: ${PRETTY_NAME:-unknown}"
case "${VERSION_ID:-}" in
  22.04) FILES=(wrn_maintenance.sh wrn_os_archive_cleanup.sh wrn_remaining_os_space.sh wrn_systemd_timeout_restore.sh wrn_archive_recovery.sh wrn_fstab_dedup.sh) ;;
  18.04) FILES=(wrn_legacy.sh) ;;
  *) fail "Unsupported Ubuntu release: ${VERSION_ID:-unknown}" ;;
esac
[[ -n "${HOME:-}" && "$HOME" == /* && -d "$HOME" ]] || fail 'Unrecognized home directory.'
if [[ -n "$OFFLINE_BUNDLE" ]]; then
  [[ -z "$LOCAL_SOURCE" && -z "$TARGET_DIR" ]] || fail 'Cannot combine offline-bundle with other source/target flags.'
  [[ "$OFFLINE_BUNDLE" == /* && -d "$OFFLINE_BUNDLE" && ! -L "$OFFLINE_BUNDLE" ]] || fail 'Offline bundle must be an absolute real directory.'
  LOCAL_SOURCE="$OFFLINE_BUNDLE"
  TARGET_DIR="$HOME/Downloads/maintenance"
  echo 'MODE: OFFLINE BUNDLE; GitHub not accessed and maintenance will NOT run.'
elif [[ -n "$LOCAL_SOURCE" || -n "$TARGET_DIR" ]]; then
  [[ -n "$LOCAL_SOURCE" && -n "$TARGET_DIR" ]] || fail 'Lab mode requires BOTH --local-source and --target-dir.'
  [[ "$LOCAL_SOURCE" == /* && -d "$LOCAL_SOURCE" && ! -L "$LOCAL_SOURCE" ]] || fail 'Local source must be an absolute real directory.'
  [[ "$TARGET_DIR" == "$HOME"/Downloads/* && "$TARGET_DIR" != "$HOME/Downloads/maintenance" ]] || fail 'Lab destination must be a separate absolute directory under ~/Downloads (not production maintenance).'
  [[ "$TARGET_DIR" != "$LOCAL_SOURCE" ]] || fail 'Source and target cannot match.'
  echo 'MODE: LOCAL TEST; GitHub not accessed and maintenance will NOT run.'
else
  TARGET_DIR="$HOME/Downloads/maintenance"
  echo 'MODE: DOWNLOAD ONLY; GitHub source, no maintenance actions.'
fi
for cmd in sha256sum mktemp mv chmod mkdir rm grep bash head; do command -v "$cmd" >/dev/null || fail "Missing tool: $cmd"; done
mkdir -p -- "$TARGET_DIR"
[[ -d "$TARGET_DIR" && ! -L "$TARGET_DIR" && -w "$TARGET_DIR" ]] || fail 'Target path is not a writable real directory.'
[[ ! -e "$TARGET_DIR/WRN-Service-History.txt" || -f "$TARGET_DIR/WRN-Service-History.txt" ]] || fail 'Unexpected service history file type.'
# All downloads are staged and independently checked before installing ANY script.
STAGE="$(mktemp -d "$TARGET_DIR/.wrn-install-stage.XXXXXXXX")" || fail 'Cannot make secure staging folder.'
trap 'rm -rf -- "$STAGE"' EXIT
expected_sha(){ case "$1" in
  wrn_maintenance.sh) printf "%s\n" "17c944ecc66c0491f0768fe008bec42c04470f95a14c965c9f847395cd00e8cb";;
  wrn_legacy.sh) printf "%s\n" "1dd0a5920eed0b39f6102ed351c12fbc59ebf21aeafde99ea142f2731cc423ff";;
  wrn_os_archive_cleanup.sh) printf "%s\n" "aba17d475f22b907c961f4ee855f0106fda9d16ac317ef50b4119236796d8193";;
  wrn_remaining_os_space.sh) printf "%s\n" "6e122ce3c6694aa0d49d8fb8411dd1e8a049f2d7303c31bfa5b2334f14b821b4";;
  wrn_systemd_timeout_restore.sh) printf "%s\n" "530a0f40d9c073b025965602c204c83c9ab84671ea2aa5fd2a410bbf505519be";;
  wrn_archive_recovery.sh) printf "%s\n" "54515394787b1d9c062d6cc210be6b0e2f487f329bbb2fe590f75f933dde42ed";;
  wrn_fstab_dedup.sh) printf "%s\n" "7cd46fd6e7a72484d913a22bf1beaba83ef39bb7440553eaa5ee200e609a94c3";;
  *) return 1;;
esac; }
for f in "${FILES[@]}"; do
  case "$f" in wrn_*.sh) ;; *) fail 'Unsafe installer manifest name';; esac
  out="$STAGE/$f"
  if [[ -n "$LOCAL_SOURCE" ]]; then
    [[ -f "$LOCAL_SOURCE/$f" && ! -L "$LOCAL_SOURCE/$f" ]] || fail "Missing local source: $f"
    cp -- "$LOCAL_SOURCE/$f" "$out" || fail "Copy failed: $f"
  else
    if command -v wget >/dev/null 2>&1; then
      wget -q --https-only --timeout=20 --tries=2 -O "$out" "$BASE_URL/$f" || fail "Download failed: $f"
    elif command -v curl >/dev/null 2>&1; then
      curl --fail --location --silent --show-error --connect-timeout 10 --max-time 90 --proto '=https' --proto-redir '=https' --output "$out" "$BASE_URL/$f" || fail "Download failed: $f"
    else fail 'Requires wget or curl'; fi
  fi
  [[ -s "$out" ]] || fail "Empty script: $f"
  actual="$(sha256sum "$out" | awk '{print $1}')"
  [[ "$actual" == "$(expected_sha "$f")" ]] || fail "SHA-256 mismatch for $f; NO scripts published"
  bash -n "$out" || fail "Bash syntax failed for $f"
  [[ "$(head -n1 "$out")" == '#!/usr/bin/env bash' ]] || fail "Invalid script header for $f"
  if grep -q $'\r' "$out"; then fail "CRLF line ending rejected for $f"; fi
  chmod 0644 "$out"
  printf 'VERIFIED %s %s\n' "$f" "$actual"
done
# Refuse symlink destination replacement; do not disturb pre-existing service history.
for f in "${FILES[@]}"; do
  [[ ! -L "$TARGET_DIR/$f" ]] || fail "Target symlink rejected: $f"
done
for f in "${FILES[@]}"; do
  mv -f -- "$STAGE/$f" "$TARGET_DIR/$f" || fail "Publishing failed: $f"
done
printf '\nINSTALL COMPLETE: %s verified scripts in %s\n' "${#FILES[@]}" "$TARGET_DIR"
if [[ "${VERSION_ID:-}" == 18.04 ]]; then
  echo 'Ubuntu 18.04: wrn_legacy.sh DIAGNOSTICS ONLY; no --apply.'
else
  echo 'Ubuntu 22.04: run diagnostics / preview / apply explicitly after review.'
  echo 'Recovery/timeout tools are downloaded but NEVER executed by installer.'
  echo 'Finalization (only after confirmed recording/playback): sudo bash wrn_maintenance.sh --finalize'
fi
