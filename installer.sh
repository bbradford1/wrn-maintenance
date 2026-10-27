#!/usr/bin/env bash
# Hanwha WRN download-only installer v1.0.0-dev.12-pilot
# Usage: wget -qO- https://raw.githubusercontent.com/bbradford1/wrn-maintenance/main/installer.sh | bash
# Downloads and verifies the complete toolkit; never executes maintenance.
set -Eeuo pipefail
export LC_ALL=C
umask 077

INSTALLER_VERSION='1.0.0-dev.12-pilot'
BASE_URL='https://raw.githubusercontent.com/bbradford1/wrn-maintenance/main'
MODERN_SHA256='845f4584f6a0ea7033f351bc7aecc6c3ab1c682fc245e131054aae5ff92db723'
LEGACY_SHA256='9f2f878669fc741f18cf8e0001b8128c791191a8218fad50e76350b492e8e5'
ARCHIVE_SHA256='aba17d475f22b907c961f4ee855f0106fda9d16ac317ef50b4119236796d8193'
CLEAN_SHA256='a3d64eb043653d896589429af602c1d2ea2e43e30ac936aa8f469a3f41f1bb18'
SPACE_SHA256='6e122ce3c6694aa0d49d8fb8411dd1e8a049f2d7303c31bfa5b2334f14b821b4'

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Keep the piped command usable by the logged-in desktop user, without sudo.
(( EUID != 0 )) || fail 'Run the installer as the normal desktop user, not with sudo. Maintenance runs separately with sudo.'
[[ -r /etc/os-release ]] || fail 'Cannot detect operating system.'
# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == ubuntu ]] || fail "Unsupported OS: ${PRETTY_NAME:-unknown}; no files downloaded."
case "${VERSION_ID:-}" in
  18.04) FILENAME='wrn_legacy.sh'; EXPECTED_SHA256="$LEGACY_SHA256" ;;
  22.04) FILENAME='wrn_maintenance.sh'; EXPECTED_SHA256="$MODERN_SHA256" ;;
  *) fail "Unsupported Ubuntu release: ${VERSION_ID:-unknown}. No files downloaded." ;;
esac

for tool in bash sha256sum mktemp mv chmod mkdir rm grep; do
  command -v "$tool" >/dev/null 2>&1 || fail "Required utility missing: $tool"
done
if command -v wget >/dev/null 2>&1; then
  DOWNLOADER=wget
elif command -v curl >/dev/null 2>&1; then
  DOWNLOADER=curl
else
  fail 'wget or curl is required to download the WRN script.'
fi

# HOME must be the invoking user's home. Never infer /root or use arbitrary SUDO_USER.
[[ -n "${HOME:-}" && "$HOME" == /* && -d "$HOME" ]] || fail 'Cannot identify the user home directory.'
TARGET_DIR="$HOME/Downloads/maintenance"
mkdir -p -- "$TARGET_DIR" || fail "Cannot create: $TARGET_DIR"
[[ -d "$TARGET_DIR" && -w "$TARGET_DIR" ]] || fail "Downloads folder is not writable: $TARGET_DIR"
TMPFILE="$(mktemp "$TARGET_DIR/.wrn-installer.XXXXXXXX")" || fail 'Unable to create temporary download file.'
cleanup() { rm -f -- "$TMPFILE"; }
trap cleanup EXIT

printf 'WRN installer %s\nOS: %s\nDestination: %s\nFile: %s\n' \
  "$INSTALLER_VERSION" "${PRETTY_NAME:-Ubuntu}" "$TARGET_DIR" "$FILENAME"
printf 'Downloading verified development build (not fleet-approved)...\n'
if [[ "$DOWNLOADER" == wget ]]; then
  wget -q --https-only --timeout=20 --tries=2 -O "$TMPFILE" "$BASE_URL/$FILENAME" \
    || fail 'Download failed; existing file was not changed.'
else
  curl --fail --location --silent --show-error --connect-timeout 10 --max-time 90 \
    --proto '=https' --proto-redir '=https' --output "$TMPFILE" "$BASE_URL/$FILENAME" \
    || fail 'Download failed; existing file was not changed.'
fi
[[ -s "$TMPFILE" ]] || fail 'Downloaded file is empty.'
IFS=' ' read -r ACTUAL_SHA256 _ < <(sha256sum "$TMPFILE")
[[ "$ACTUAL_SHA256" == "$EXPECTED_SHA256" ]] || fail 'Checksum mismatch: download rejected; existing file was not changed.'
bash -n "$TMPFILE" || fail 'Bash syntax check failed; existing file was not changed.'
[[ "$(head -n 1 "$TMPFILE")" == '#!/usr/bin/env bash' ]] || fail 'Unexpected file header.'
if grep -q $'\r' "$TMPFILE"; then fail 'Windows CR line endings detected; download rejected.'; fi

# Publish only after all checks; same-directory rename prevents partial target files.
chmod 0644 "$TMPFILE"
mv -f -- "$TMPFILE" "$TARGET_DIR/$FILENAME" || fail 'Could not publish validated script.'
printf '\nMAIN SCRIPT VERIFIED: %s\nSHA-256: %s\n' "$TARGET_DIR/$FILENAME" "$ACTUAL_SHA256"
# Optional cleanup utility is downloaded for both supported Ubuntu releases.
# It is NEVER executed by this installer. The --delete flag permanently removes recordings.
ARCHIVE_TMP="$(mktemp "$TARGET_DIR/.wrn-archive.XXXXXXXX")" || fail 'Cannot stage archive utility.'
archive_cleanup_tmp() { rm -f -- "$ARCHIVE_TMP"; }
trap 'cleanup; archive_cleanup_tmp' EXIT
if [[ "$DOWNLOADER" == wget ]]; then
  wget -q --https-only --timeout=20 --tries=2 -O "$ARCHIVE_TMP" "$BASE_URL/wrn_os_archive_cleanup.sh" \
    || fail 'Archive utility download failed; maintenance script download was already verified.'
else
  curl --fail --location --silent --show-error --connect-timeout 10 --max-time 90 \
    --proto '=https' --proto-redir '=https' --output "$ARCHIVE_TMP" "$BASE_URL/wrn_os_archive_cleanup.sh" \
    || fail 'Archive utility download failed; maintenance script download was already verified.'
fi
[[ -s "$ARCHIVE_TMP" ]] || fail 'Archive utility download is empty.'
IFS=' ' read -r ARCHIVE_ACTUAL_SHA _ < <(sha256sum "$ARCHIVE_TMP")
[[ "$ARCHIVE_ACTUAL_SHA" == "$ARCHIVE_SHA256" ]] || fail 'Archive utility checksum mismatch; refusing file.'
bash -n "$ARCHIVE_TMP" || fail 'Archive utility Bash syntax check failed.'
[[ "$(head -n 1 "$ARCHIVE_TMP")" == '#!/usr/bin/env bash' ]] || fail 'Archive utility file header unexpected.'
if grep -q $'\r' "$ARCHIVE_TMP"; then fail 'Archive utility CRLF detected.'; fi
chmod 0644 "$ARCHIVE_TMP"
mv -f -- "$ARCHIVE_TMP" "$TARGET_DIR/wrn_os_archive_cleanup.sh" || fail 'Cannot publish archive utility.'
printf '\nARCHIVE UTILITY VERIFIED: %s\nSHA-256: %s\n' "$TARGET_DIR/wrn_os_archive_cleanup.sh" "$ARCHIVE_ACTUAL_SHA"
printf 'Archive utility is DRY RUN by default. --delete permanently destroys the listed OS-drive recordings.\n'

# Additional read-only OS-space diagnostics. Download only, checked against pinned hash.
SPACE_TMP="$(mktemp "$TARGET_DIR/.wrn-space.XXXXXXXX")" || fail 'Cannot stage space diagnostic.'
space_cleanup_tmp() { rm -f -- "$SPACE_TMP"; }
trap 'cleanup; archive_cleanup_tmp; space_cleanup_tmp' EXIT
if [[ "$DOWNLOADER" == wget ]]; then
  wget -q --https-only --timeout=20 --tries=2 -O "$SPACE_TMP" "$BASE_URL/wrn_remaining_os_space.sh" \
    || fail 'OS diagnostic download failed.'
else
  curl --fail --location --silent --show-error --connect-timeout 10 --max-time 90 \
    --proto '=https' --proto-redir '=https' --output "$SPACE_TMP" "$BASE_URL/wrn_remaining_os_space.sh" \
    || fail 'OS diagnostic download failed.'
fi
[[ -s "$SPACE_TMP" ]] || fail 'OS diagnostic download is empty.'
IFS=' ' read -r SPACE_ACTUAL_SHA _ < <(sha256sum "$SPACE_TMP")
[[ "$SPACE_ACTUAL_SHA" == "$SPACE_SHA256" ]] || fail 'OS diagnostic checksum mismatch.'
bash -n "$SPACE_TMP" || fail 'OS diagnostic Bash syntax check failed.'
[[ "$(head -n 1 "$SPACE_TMP")" == '#!/usr/bin/env bash' ]] || fail 'Unexpected OS diagnostic header.'
if grep -q $'\r' "$SPACE_TMP"; then fail 'OS diagnostic CRLF detected.'; fi
chmod 0644 "$SPACE_TMP"
mv -f -- "$SPACE_TMP" "$TARGET_DIR/wrn_remaining_os_space.sh" || fail 'Cannot publish OS diagnostic.'
printf '\nOS DIAGNOSTIC VERIFIED: %s\n' "$TARGET_DIR/wrn_remaining_os_space.sh"
printf 'For read-only OS space report: cd ~/Downloads/maintenance && sudo bash wrn_remaining_os_space.sh\n'

# Optional clean-up helper: downloaded but never executed.
CLEAN_TMP="$(mktemp "$TARGET_DIR/.wrn-clean.XXXXXXXX")" || fail 'Cannot stage cleanup helper.'
cleanup_all() { cleanup; archive_cleanup_tmp; space_cleanup_tmp; rm -f -- "$CLEAN_TMP"; }
trap cleanup_all EXIT
if [[ "$DOWNLOADER" == wget ]]; then
  wget -q --https-only --timeout=20 --tries=2 -O "$CLEAN_TMP" "$BASE_URL/wrn_downloads_cleanup.sh" || fail 'Cleanup helper download failed.'
else
  curl --fail --location --silent --show-error --connect-timeout 10 --max-time 90 --proto '=https' --proto-redir '=https' --output "$CLEAN_TMP" "$BASE_URL/wrn_downloads_cleanup.sh" || fail 'Cleanup helper download failed.'
fi
[[ -s "$CLEAN_TMP" ]] || fail 'Cleanup helper download empty.'
[[ "$(sha256sum "$CLEAN_TMP" | awk '{print $1}')" == "$CLEAN_SHA256" ]] || fail 'Cleanup helper checksum mismatch.'
bash -n "$CLEAN_TMP" || fail 'Cleanup helper syntax error.'
[[ "$(head -n 1 "$CLEAN_TMP")" == '#!/usr/bin/env bash' ]] || fail 'Unexpected cleanup helper header.'
if grep -q $'\r' "$CLEAN_TMP"; then fail 'Cleanup helper CRLF rejected.'; fi
chmod 0644 "$CLEAN_TMP"
mv -f -- "$CLEAN_TMP" "$TARGET_DIR/wrn_downloads_cleanup.sh" || fail 'Cannot publish cleanup helper.'
printf 'CLEANUP HELPER VERIFIED: %s\n' "$TARGET_DIR/wrn_downloads_cleanup.sh"
# Final manifest validation happens AFTER every staged download/checksum has passed.
for required in "$FILENAME" wrn_os_archive_cleanup.sh wrn_remaining_os_space.sh wrn_downloads_cleanup.sh; do
  [[ -s "$TARGET_DIR/$required" && -r "$TARGET_DIR/$required" ]] || fail "INSTALLATION INCOMPLETE: missing $required"
done
printf '\n=== INSTALLATION COMPLETE: 4 VERIFIED SCRIPTS ===\n'
printf 'Selected OS script: %s\n' "$FILENAME"
printf 'OS archive utility: wrn_os_archive_cleanup.sh (dry-run by default)\n'
printf 'OS space audit: wrn_remaining_os_space.sh\n'
printf 'Housekeeping: wrn_downloads_cleanup.sh\n'
printf 'No maintenance or archive deletion has been executed.\n'
if [[ "$FILENAME" == wrn_legacy.sh ]]; then
  printf 'Ubuntu 18.04: diagnostics only; --apply is NOT approved.\n'
else
  printf 'Ubuntu 22.04: supervised maintenance pilot.\n'
fi
