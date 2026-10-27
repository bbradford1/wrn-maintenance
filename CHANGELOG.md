## 2026-10-27 — supervised folder-pilot.1
- Installer creates `~/Downloads/maintenance`, downloads verified maintenance, OS cleanup, OS diagnostic, and cleanup helper there; download-only.
- Routine maintenance diagnostics, preview and apply reports now use the subfolder; legacy diagnostics use the subfolder.
- OS diagnostic and archive-cleanup transcript use the subfolder. No change to WAVE recording cleanup selection or maintenance fix logic.
- Optional cleanup helper previews/deletes only recognized files directly in that subfolder, after approval.
- Not field-qualified. Core/Snap retirement and fstab recovery remain separate.

# Changelog

## 2026-10-23 — 1.0.0-dev.5 controlled testing

- Ubuntu 22.04 live-tested: logging KB checks, guarded archive UUID repair, Snap refresh hold, diagnostics, report permissions, no WAVE interruption; successful subsequent reboot and WAVE recording/playback validation on one WRN.
- Ubuntu 22.04 apply re-run correctly skipped already-normalized archive entry.
- Ubuntu 18.04 remains unmodified diagnostic-only dev.1; no apply support or qualification yet.
- Installer updated to verify SHA-256 of modern dev.5 and legacy dev.1.
- Fleet deployment NOT yet qualified; retain warnings for absent optional archive bays and logrotate scheduling rules.

## 1.0.0-dev.7 (2026-10-23)
- Explicit 60s device and 120s mount-operation timeouts for mounted UUID-based ext4 `/mnt/sda`; preserve longer numeric-second values.
- Read-only archive failure/journal event diagnostics; no automatic repair, mount, reboot, or WAVE restart.
- Installer checksum refreshed; auxiliary OS archive cleanup remains independent and download-only.

## 2026-10-27 — supervised diagnostics add-on (no maintenance behavior change)
- Preserve byte-for-byte Ubuntu 22.04 dev.7 maintenance, Ubuntu 18.04 dev.1 diagnostics and original OS fallback-recording cleanup.
- Add verified, download-only `wrn_remaining_os_space.sh` for read-only >=1 GiB storage investigation on Ubuntu 22.04.
- Installer now downloads the additional diagnostic with a pinned SHA-256.
- Exclude unqualified Snap retirement and dev.8 experimental repair paths from routine rollout.
