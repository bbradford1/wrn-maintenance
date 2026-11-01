# Hanwha WRN Maintenance — dev.19 technician workflow pilot

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
