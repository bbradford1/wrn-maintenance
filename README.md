# Hanwha WRN Maintenance — dev.19.1 technician workflow pilot

**TEST BRANCH ONLY — NOT APPROVED FOR FLEET DEPLOYMENT.** Ubuntu 22.04 Gen 2 only; Ubuntu 18.04 diagnostics only.

## Technician: the same two commands

As the normal `wave` user (NOT sudo), download scripts:

```bash
wget -qO- https://raw.githubusercontent.com/bbradford1/wrn-maintenance/technician-workflow-pilot/installer.sh | bash
```

Then run the guided maintenance over an interactive SSH session:

```bash
cd /home/wave/Downloads/maintenance && sudo bash wrn_maintenance.sh --apply
```

The installer verifies **eight** Ubuntu 22.04 scripts and DOES NOT execute them. The technician approves the exact 3-second systemd timeout repair if detected, and duplicate archive fstab repair if detected. The preflight now inventories mounted archive volumes and OS recording spillover. Core maintenance normalizes the UUID/timeout configuration for all correctly mounted `/mnt/sda` through `/mnt/sdd` drives. For absent optional bays, the existing fstab entries are reported but not silently deleted. A present archive device that should be mounted but is offline is a STOP condition.

A missing primary archive halts routine maintenance and optionally offers read-only archive inspection, never blind fsck or mounting. OS recording spillover detection is read-only; it does not delete or move recordings.

Finalization occurs only after technician independently verifies desktop, live recording, and playback:

```bash
cd /home/wave/Downloads/maintenance && sudo bash wrn_maintenance.sh --finalize
```

Answer `N` if cameras are unavailable, footage cannot be played, or review is incomplete. `Y` finalization intentionally keeps **only** `WRN-Service-History.txt` in the maintenance directory; save required reports first.

## Additional diagnostic commands

```bash
cd /home/wave/Downloads/maintenance
sudo bash wrn_archive_multidrive.sh --audit
sudo bash wrn_archive_spillover.sh --audit
sudo bash wrn_archive_spillover.sh --plan-move
sudo bash wrn_maintenance.sh --prompt-preview
```

All four are safe inspection/preview commands. `--plan-move` is capacity analysis only: **no automatic move is implemented**. The existing `wrn_os_archive_cleanup.sh --delete` is an exceptional, separate, interactive, explicitly authorized operation with additional filesystem/active-recording guards; it is NEVER invoked by routine maintenance. Never delete OS recordings just because the OS disk is near full.

## Why dev.19 does not offer automatic migration

WAVE/Nx records video in chunks indexed by location; moving files manually can break timeline playback until archives are reindexed. WAVE automatically balances and recycles its storage volumes. A nearly-full archive with 30 GB remaining may be at its VMS reserve, NOT have 30 GB safely available for a file copy. The audit displays actual `df` free bytes and a **conservative 50 GiB margin**; this is a screening value, not proof of capacity or an endorsement to move. Migration must be separately designed with Hanwha/Network Optix support, tested against real footage, and validated after reindexing. Preserve originals until validated.

## Lab and safety

- `main` remains unchanged. Commit all scripts plus the updated installer and SHA256 manifest to `technician-workflow-pilot` together only **after** a reviewed lab test.
- The dev.18 factory-to-maintained single-drive flow passed previously. **Dev.19 multi-drive logic has not yet passed real multi-drive hardware validation**.
- No automatic video modification, filesystem repair, WAVE restart, disk mount/unmount, or reboot.
- Retain reports when an exception occurs and seek supervised diagnosis rather than guessing.
- USB/removable or unexpected filesystems are never automatically assigned as archives.
- `isc-dhcp-server6` factory failure is not modified.
- Diagnostics, scripts and history belong under `/home/wave/Downloads/maintenance`.

See `TEST-PLAN.md` and `DEPLOYMENT-NOTES.txt`.

## dev.19.1 automatic post-Snap orphan cleanup

After the normal approved Snap removal stage, `--apply` automatically detects and retires ONLY failed, inactive systemd `snap-*.mount` definitions where the mounted image is absent and the Snap name is unregistered. No additional technician Y/N question is asked. It preserves active mounts, installed Snap names, and unexpected units; backs up eligible unit definitions and their enablement links under `/etc/systemd/wrn-snap-orphan-backups/`; then reloads systemd and clears only those specific failed-unit statuses. It does **not** remove snapd, WAVE data, or unrelated `dmesg`/DHCP failures. User-session autostarts are not automatically changed.

Read-only audit, without repeating maintenance: `sudo bash wrn_maintenance.sh --snap-orphan-audit`. This candidate has **not** been validated with real failed orphan units; do not run `--apply` on a customer recorder until lab qualification.

### dev.19.3 dmesg one-shot recovery

`sudo bash wrn_maintenance.sh --dmesg-audit` inspects eligibility without changes. During `--apply` the script will retry `dmesg.service` once only for a previously failed timeout after the effective global timeouts are verified at 90 seconds. A successful one-shot service may appear inactive/dead; `Result=success` is the key. No DHCP service is changed and no failed state is blindly reset.

### Engineering test mode (dev.19.3; lab only)
`sudo bash wrn_maintenance.sh --snap-orphan-apply` invokes the same guarded orphan cleanup used automatically in `--apply`, without running other maintenance stages. Use only for supervised lab qualification.


Dev.19.4 engineering test: `sudo bash wrn_maintenance.sh --dmesg-audit`, then supervised `sudo bash wrn_maintenance.sh --dmesg-apply` only after authorization; no full maintenance rerun.


### dev.19.5 partition-backed archive lab qualification
An ext4 archive on a disk partition (e.g. /dev/sdb1) may be mounted at /mnt/sdb even when factory fstab references /dev/sdb. The multi-drive helper only accepts this exception if block-device metadata verifies /dev/sdb1 belongs directly to /dev/sdb, then proposes an ext4 UUID entry. Audit first; do not run apply on customer recorders until qualified.


### dev.19.6 archive reporting

`sudo bash wrn_maintenance.sh --diagnose` prints all currently mounted archive directories `/mnt/sda`–`/mnt/sdd`. The detailed report contains an **ALL ARCHIVES SUMMARY (READ-ONLY)** section. RW mount status is not a substitute for live recording and playback verification in WAVE. The archive repair helper and operating commands are unchanged.
