# WRN Maintenance — Engineering and Support Guide

**Version:** 1.0.0 · Target: Hanwha Gen 2 WRN / Ubuntu 22.04. This is a technical companion to the technician [README](README.md). Do not substitute it for vendor-supported WAVE storage-recovery procedures.

## Workflow and safety boundaries

1. `installer.sh` downloads scripts to `/home/wave/Downloads/maintenance`, validates per-file SHA-256 pins and Bash syntax, and does **not** execute repairs. A production installer must fetch files from the same reviewed `main` release.
2. `wrn_maintenance.sh --diagnose` produces a read-only system and archive report. The short summary enumerates mounted `/mnt/sda`–`/mnt/sdd` archives, but mounted state does not prove recording.
3. `wrn_maintenance.sh --apply` runs a guarded preflight; may offer a supervised 3-second global systemd timeout repair and duplicate fstab repair; audits the mounted archives; runs limited OS/logging/Snap maintenance; invokes the multi-drive helper; verifies core conditions and asks for operational confirmation. It can change system configuration and installed packages, so run only on approved hardware with rollback/report retention.
4. `wrn_maintenance.sh --finalize` retains permanent service history and removes temporary toolkit files/reports after technician-verified desktop, live recording and playback.

**Never** use this workflow as permission to format a drive, erase or move customer recordings, delete the WAVE main database, or force-remount an ambiguous archive. Unexpected mounts, UUID conflicts, read-only filesystems, and other unsafe conditions must be investigated before applying changes.

## Script reference

| File | Role | Normal technician use |
|---|---|---|
| `installer.sh` | Download-only installer and SHA verification | Yes, first command |
| `wrn_maintenance.sh` | Diagnostics, preflight, guided maintenance, service history, finalization | Yes, second command |
| `wrn_archive_multidrive.sh` | Audits `/mnt/sda`–`/mnt/sdd`; guarded UUID and mount-timeout normalization (60s device/120s mount) | Called by main workflow; optional engineering `--audit` |
| `wrn_fstab_dedup.sh` | Guarded repair of duplicate archive mount entries | Invoked only when approved by preflight |
| `wrn_systemd_timeout_restore.sh` | Audit/restore unusual 3-second systemd start/stop defaults to standard 90-second values | Invoked only with guarded technician approval |
| `wrn_archive_recovery.sh` | Diagnose offline archive and supervised recovery path | Exception handling, not routine maintenance |
| `wrn_archive_spillover.sh` | Read-only inspection of recognizable WAVE video folders on OS filesystem | Called during preflight; `--plan-move` is **only** an estimate |
| `wrn_os_archive_cleanup.sh` | Separate, destructive OS video deletion helper requiring explicit approval and protective checks | **Never** automatic; use only with customer authorization |
| `wrn_remaining_os_space.sh` | Additional guarded OS space inspection/cleanup | Support-directed exception use |
| `wrn_legacy.sh` | Legacy Ubuntu 18.04 diagnostics | Diagnostics only, no maintenance apply |

## Archive rules

- UUID normalization is limited to physically verified, mounted, RW ext4 archive filesystems. The helper verifies direct parentage when the mounted source is a partition (`/dev/sdb1`) but the legacy fstab record names its whole parent disk (`/dev/sdb`). Unrelated device mismatches remain a STOP.
- It never formats, unmounts, fscks, reindexes, or relocates video. Backups of repaired `/etc/fstab` are preserved in `/etc`, outside the finalization cleanup.
- Configured but absent optional drives are reported and not automatically removed from fstab. A physically expected but offline archive requires investigation; merely suppressing warnings is not a repair.
- The collector's primary-archive deep diagnostics remain centered on `/mnt/sda`; the mounted-volume summary and the separate multi-drive audit cover other mounted archive paths.

## System cleanup / services

- Holds automatic Snap refresh indefinitely; this does not block manual Snap installs or upgrades. Approved desktop/Snap removals are guarded by a required-package protection list.
- Automatic orphan Snap mount cleanup is restricted to inactive failed units with absent image and unregistered Snap name; eligible definitions are backed up under `/etc/systemd/wrn-snap-orphan-backups/`. Active Snap mounts are preserved. Per-user desktop autostarts are not automatically cleaned.
- Historical `dmesg.service` timeout recovery is a one-time guarded restart, only when effective global timeouts and the unit path meet requirements. An inactive oneshot service with `Result=success` is normal. DHCP server service failures are not repaired by this tool.
- Logging checks/cleanup preserve rsyslog/logrotate functionality; package guards aim to retain Ubuntu desktop, WAVE, remote access, and essential software. Always verify actual services and video afterward.

## Useful read-only engineering commands

```bash
cd /home/wave/Downloads/maintenance
sudo bash wrn_maintenance.sh --version
sudo bash wrn_maintenance.sh --diagnose
sudo bash wrn_archive_multidrive.sh --audit
sudo bash wrn_archive_spillover.sh --audit
sudo bash wrn_maintenance.sh --snap-orphan-audit
sudo bash wrn_maintenance.sh --dmesg-audit
```

Standalone `--snap-orphan-apply`, `--dmesg-apply`, and recovery helpers are **engineering-only operations**, not general technician steps. Do not run any manual media-deletion mode without independent customer authorization.

## Qualification evidence and outstanding limits

- Gen 2 single-drive restore/cleanup testing; two real SATA archives tested (`/dev/sda` and partition-backed `/dev/sdb1`), fstab repair and reboot persistence confirmed.
- A deliberately broken lab `/mnt/sdb` fstab entry was repaired by the **main `--apply`** path (Test 092); both archives remained RW after reboot with zero audit corrections (Test 093); technician confirmed desktop, live WAVE recording and playback (Test 094).
- Customer three-drive system was read-only audited; orphan Snap units and `dmesg.service` recovery were separately tested under authorization. **No three-drive fault injection or customer reboot persistence test has been performed.**
- OS spillover positive detection and automatic relocation are not qualified or planned for this release. The scanner is limited to recognized paths and cannot conclusively exclude unusual recordings on the OS drive.
- Diagnostic summary `SMART PASSED` is not a complete guarantee of drive health. Check logs, actual archive use, live recording, and playback.
