# dev.19 validation plan — lab-only

## Non-destructive first

1. Download package to workstation, `sha256sum -c SHA256SUMS.txt` and `bash -n` all scripts.
2. On lab WRN, retain/archive the dev.18 test reports. Do not reimage yet.
3. Run `sudo bash wrn_archive_multidrive.sh --audit` and `sudo bash wrn_archive_spillover.sh --audit` using locally staged scripts. Check their outputs and ensure no video/mount/config changes.
4. Confirm exact `/mnt/sda` block identity, UUID, ext4 rw state, fstab count, and historical fstab backup. Run second audit to prove idempotence.
5. Run `sudo bash wrn_archive_spillover.sh --plan-move`; it must not attempt to copy/move/delete, even when a large archive has available space.

## Required simulated and hardware multi-drive cases

- One mounted archive + absent `/dev/sdb` through `/dev/sdd`: report absent bays and do not edit them.
- Two and three independent ext4 volumes mounted rw with unique UUIDs: propose and guard each fstab change, stage one atomic transaction, preserve originals and options. Restart and verify all mounts after successful lab apply.
- Disk mounted read-only, wrong fstab UUID/source, duplicate target/source, one present configured disk unmounted, missing UUID, unsupported options, swap/root device alias: MUST STOP before modifying fstab.
- Multi-drive failure: no disk formatting, filesystem check, mount attempts, video deletion or server restart.
- Reapply: zero corrections, unchanged fstab. Verify backup, report and finalization behavior.
- OS spillover: empty root, synthetic hi/low dated camera directories on OS filesystem, symlinked folders, mounted nested filesystem; ensure scanner never crosses filesystem boundaries. Compare allocated byte totals.
- Candidate archive with free space equal to or less than 50 GiB: no migration suggested. A larger free-space amount is information only, not permission.
- Preserve/validate all recorded footage and the WAVE client after reboot. Never interpret `systemctl is-active` as recording/playback proof.

## Potential future migration pilot — NOT IMPLEMENTED

Seek OEM support confirmation on supported archive relocation paths and reindex requirements. Use test video with verified start/end timestamps and hashes; independent destination storage with ample space (not VMS reserve); controlled WAVE access or downtime; abort-safe copy verification; WAVE Storage Management reindex; timeline playback proof; delayed removal only after customer approval. No direct rsync/mv on field recordings in dev.19.

## Test 070 — orphan mount cleanup (must be performed on disposable lab VM/WRN first)

1. Audit actual field orphans with `sudo bash wrn_maintenance.sh --snap-orphan-audit` (no modification).
2. Test against synthetic FAILED mount unit with missing image on disposable lab environment; verify matching eligibility and backups.
3. Test current working installed snapd revision and other installed snaps remain completely untouched.
4. Test the preservation path for active mounts, unexpected paths, present image files and registered names.
5. Validate backup restoration/recovery, idempotence and reboot behavior.
6. Do not run `--apply` on a customer WRN until those lab conditions have passed.

### Test 070B — dmesg recovery candidate (dev.19.2)

1. Confirm `--dmesg-audit` is read-only on healthy lab WRN and on a WRN with old `Result=timeout`.
2. In isolated mocks exercise healthy (`inactive/success`), timeout with 3s defaults (skip), timeout with 90s defaults (one restart), non-timeout failure (skip), unexpected unit path (skip), and restart failure (report without `reset-failed`).
3. On an expendable lab, intentionally exercise the actual single-service recovery under controlled conditions; verify `Result=success`, no WAVE/archive impact, and reboot persistence. Do not induce errors on a customer recorder.
4. Only after lab qualification, conduct a supervised pilot on a permitted WRN; do not touch DHCP services.
