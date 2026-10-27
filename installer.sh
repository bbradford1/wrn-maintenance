#!/usr/bin/env bash
# WRN 22.04 pilot downloader; does not execute downloaded maintenance.
set -Eeuo pipefail
[[ $EUID -ne 0 ]] || { echo 'Run as wave without sudo'; exit 1; }
. /etc/os-release
[[ ${ID:-} == ubuntu && ${VERSION_ID:-} == 22.04 ]] || { echo 'Ubuntu 22.04 only'; exit 1; }
[[ ${HOME:-} == /home/wave ]] || { echo 'This WRN installer requires wave user'; exit 1; }
command -v wget >/dev/null && command -v sha256sum >/dev/null
D="$HOME/Downloads/maintenance"
mkdir -p "$D"
[[ -d $D && ! -L $D ]] || exit 1
T=$(mktemp "$D/.wrn-pilot.XXXXXXXX")
trap 'rm -f "$T"' EXIT
URL='https://raw.githubusercontent.com/bbradford1/wrn-maintenance/main/wrn_maintenance.sh'
HASH='236f3cf5fb4af25f5ba3b2bfb3dc233e67bf95f989603c6331ac841f990374e5'
wget --https-only -q --timeout=25 --tries=2 -O "$T" "$URL"
printf '%s  %s\n' "$HASH" "$T" | sha256sum -c -
bash -n "$T"
chmod 0644 "$T"
mv -f "$T" "$D/wrn_maintenance.sh"
printf '\nVerified pilot in %s\nRun: cd %s && sudo bash wrn_maintenance.sh --apply\n' "$D" "$D"
