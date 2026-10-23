#!/usr/bin/env bash
# Hanwha WRN download-only installer v1.0.0-dev.7
# Usage: wget -qO- https://raw.githubusercontent.com/bbradford1/wrn-maintenance/main/installer.sh | bash
# Downloads one SHA-256-verified script; never runs it.
set -Eeuo pipefail
export LC_ALL=C
umask 077

INSTALLER_VERSION='1.0.0-dev.7'
BASE_URL='https://raw.githubusercontent.com/bbradford1/wrn-maintenance/main'
MODERN_SHA256='c037525e2a342e8d27d146c8c868b2c3d98ec594ce2ca7a68a8a5926c61cdc46'
LEGACY_SHA256='9f2f878669fc741f1b18cf8e0001b8128c791191a8218fad50e76350b492e8e5'
ARCHIVE_SHA256='ac9b89cb20c4eb31a144e2bcf8d3fad13da86995ad049877f398ea36e8fe6e73'

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
TARGET_DIR="$HOME/Downloads"
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
printf '\nDOWNLOAD VERIFIED: %s\nSHA-256: %s\n' "$TARGET_DIR/$FILENAME" "$ACTUAL_SHA256"
printf '\nDownload only. Nothing was executed.\n'
if [[ "$FILENAME" == 'wrn_maintenance.sh' ]]; then
  printf 'Ubuntu 22.04 supervised-test build: --diagnose, --preview, --apply.\n'
  printf 'Run --preview and review results before supervised --apply.\n'
else
  printf 'Ubuntu 18.04 diagnostics-only build: --diagnose only. Do NOT use --apply.\n'
fi
printf 'Commands: cd ~/Downloads && sudo bash %s --diagnose\n' "$FILENAME"

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
