## dev.19.4 — isolated guarded dmesg retry (LAB TEST)

- Added `--dmesg-apply` engineering-only entry point to the existing guarded recovery function. It does not invoke full maintenance. Run after `--dmesg-audit`, on authorized systems only.
- This is not a general-purpose service reset. It requires a historical timeout, stock dmesg unit path, corrected 90s defaults, and maintenance safety guards; it retries once and verifies the result.

## dev.19.3 — guarded dmesg.service recovery (UNQUALIFIED LAB PILOT)

- During `--apply`, after approved Snap cleanup, inspect a failed `dmesg.service` and retry it **once** only if the failure result is `timeout`, the effective systemd start/stop timeouts are both 90s, and the stock unit file path matches.
- Success requires systemctl restart success plus `Result=success`, `ExecMainStatus=0`, and no failed state. A normally inactive oneshot service is accepted. Failure is reported but never hidden using `reset-failed`. DHCP units remain unchanged.
- Added read-only `--dmesg-audit` mode. No separate technician confirmation; only operates during approved `--apply`. No video, mounts or WAVE services are restarted.
- Requires lab qualification before use on a customer WRN.

## dev.19.1 — automatic orphaned Snap mount cleanup (candidate, not field qualified)

- Added noninteractive guarded post-removal cleanup of inactive failed Snap mount units with unregistered packages and absent backing images.
- Back up unit files and enablement links before retiring them; target-only `reset-failed`; leave other failed services untouched.
- Added `--snap-orphan-audit` for read-only eligibility checks. No automatic cleaning of per-user Snap autostart artifacts.

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

## dev.19.3 — Test 072D isolated orphan cleanup
- Adds `--snap-orphan-apply`, an engineering-only standalone entry point into the same guarded `snap_orphan_cleanup apply` used by regular `--apply`. No full maintenance, package removal, archive repair or finalization.
- `--snap-orphan-audit` remains read-only and does not alter unit state. Normal `--apply` still performs orphan housekeeping automatically without a new prompt.
- Use only on expendable lab WRN until qualified. Test the synthetic `snap-wrntest-99999.mount` orphan, verify backup and failure-state removal, preserve installed snapd, WAVE and archives.


## dev.19.5 — partition-backed archive exception (lab candidate)
- Archive helper recognizes a mounted ext4 partition only when the fstab device points to its verified direct parent disk (e.g. /dev/sdb -> /dev/sdb1).
- Maintains a safety STOP for unrelated mounted devices, OS devices, unexpected filesystem types, and duplicate archive targets.
- Retains prior behavior on whole-disk ext4 archives and all Snap/dmesg features of dev.19.4.
- Requires read-only audit, supervised apply, fstab verification, and reboot persistence on the expendable lab WRN.
