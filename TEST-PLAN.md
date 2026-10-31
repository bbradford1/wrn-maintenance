# WRN dev.17 test and acceptance plan

## Stage A: static and isolated testing (working container)
- Bash syntax for all eight `.sh` files.
- Installer SHA-256 manifest consistency; corrupt input must fail before publishing any scripts.
- Interactive Y, N and absent-terminal behavior; explicit finalization confirmation.
- No automatic archive recovery or OS recording deletion.

## Stage B: healthy, maintained lab WRN (current machine, no reimage)
1. Back up current `/home/wave/Downloads/maintenance/WRN-Service-History.txt` off device.
2. Extract the candidate to a separate Downloads folder; `sha256sum -c SHA256SUMS.txt`.
3. Run installer in `--local-source` / `--target-dir` isolated test mode; verify hashes.
4. Run the offline installer into normal maintenance only once ready to replace lab copies.
5. `sudo bash wrn_maintenance.sh --diagnose`, then `--preview`; upload the reports.
6. `sudo bash wrn_maintenance.sh --apply` with 90s systemd defaults; the prompt should occur only after successful maintenance.
7. Answer N on first pass; verify all reports remain. On a subsequent verified pass, accept cleanup **only after live recording/playback and desktop checks**. Review service-history entry.
8. Verify `--finalize` rejects duplicate finalization and fails closed without a controlling terminal.
9. Reboot, verify `/mnt/sda` rw, UUID fstab with >=60s device and >=120s mount, 90s global timeouts, WAVE, display manager, SSH and Cockpit; manually test recording/playback.

## Stage C: guarded failure simulations (non-production lab)
- Exact 3s/3s main config; prompted helper preview/apply and effective timeout re-check.
- N on the timeout prompt: no maintenance apply, no finalization.
- Missing helper: stop with actionable error.
- Duplicate identical fstab entries: prompted dedup, post-check and reread.
- Conflicting fstab entries: helper must refuse, preserving evidence.
- Unmounted archive: inspect-only option, then stop; never automatically recover.
- Missing/corrupt device, invalid OS root, inactive WAVE: safe stop.
- No TTY and a required approval: safe stop.
- Unverified recording/playback: decline finalization and preserve artifacts.
- Test corrupt checksum and missing downloaded script with installer; no partial publication.

## Stage D: final GitHub branch + fresh reimage
1. Commit **all** candidate scripts and docs to `technician-workflow-pilot`, NOT `main`.
2. Reimage the lab WRN; use original Hanwha `MountDrivesOnly.sh` and SSH setup.
3. Use the test-branch `wget -qO- .../installer.sh | bash` command.
4. Confirm checksums and six tools installed in Downloads/maintenance.
5. `sudo bash wrn_maintenance.sh --apply`; approve only known guarded repairs, verify recording/playback separately, accept finalization.
6. Reboot and repeat full health checks; require service history to be the only maintenance folder file.
7. Promote to GitHub `main` only after successful field-like qualification and explicit approval.

**Not yet verified:** dev.17 runtime on the physical WRN, the published GitHub branch, or live WAVE recording/playback on this lab unit.

## Test 063 — dev.18 safe Y/N order (no reimage)

1. On the already-maintained lab WRN, install the updated test-branch toolkit with the installer; confirm all script checksums verify.
2. Run `sudo bash wrn_maintenance.sh --prompt-preview` and enter `N`. The instructions MUST appear above the final `[Y/N]:` question. No reports are removed.
3. Repeat `--prompt-preview` and enter `Y`. Preview MUST still perform NO cleanup.
4. Verify `WRN-Service-History.txt` and prior maintenance reports remain untouched.
5. Finalization in `--apply` or `--finalize` still requires legitimate live recording/playback verification.

The new mode does not rerun cleanup or repair, and does not require a reimage.
