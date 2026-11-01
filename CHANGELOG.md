# Changelog

## 1.0.0-dev.19-tech-pilot — multi-drive and OS spillover analysis (UNTESTED)

- Added `wrn_archive_multidrive.sh`: read-only `--audit`, guarded `--apply` normalizes UUID-backed fstab and 60-second device/120-second mount timeouts for each mounted rw ext4 archive `/mnt/sda`–`/mnt/sdd`. Stops on ambiguous/failed or duplicate storage. Does not mount, unmount, fsck, reboot or touch footage.
- Integrated read-only multi-drive preflight/final audit into technician `wrn_maintenance.sh --apply` and replaced single-drive fstab normalization with the guarded multi-drive helper.
- Added `wrn_archive_spillover.sh`: scans dated hi/low-quality video directories only on OS filesystem, reports allocated bytes and archive destination free-space margins. `--plan-move` remains read-only.
- Strengthened the separate OS-recording deletion helper with OS-filesystem guards, protected mounts, active-file detection and mandatory typed interactive approval. Routine maintenance never invokes deletion.
- Updated installer SHA-256 pins for eight Ubuntu 22.04 scripts, documentation and test plan.
- **Not yet tested on a live 2/3/4 archive recorder. Do not promote to main.**

## dev.18 — verified on Gen 2 single-drive lab

- Unified technician verification notice and prompt output through `/dev/tty`.
- Added non-destructive `--prompt-preview` to validate both Y and N presentation.
- Successfully tested from factory image, guided 3-second timeout restoration, OS cleanup and reboot persistence, with recording/playback requiring independent validation.
