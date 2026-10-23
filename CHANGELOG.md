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
