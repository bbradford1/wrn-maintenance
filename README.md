# Hanwha WRN Maintenance

**Status:** Supervised pilot — October 27, 2026  
**Supported for maintenance:** Ubuntu 22.04 LTS WRN servers  
**Current pilot:** `wrn_maintenance.sh` v1.0.0-dev.10-pilot

This toolkit helps technicians maintain Hanwha WAVE recording servers, reclaim space on the operating-system drive, and document what was done. It is intended to be simple to run while keeping recording and the local desktop working.

> **Supervised testing only.** The combined workflow has been tested on a WRN that was already cleaned. Test the full installation and cleanup sequence on another WRN before approving wider rollout.

## What it does

- Checks the WRN's condition, including the WAVE service and recording archive.
- Cleans up selected old logs, unused Snap revisions, and temporary files.
- Checks the archive's startup configuration and makes only guarded, approved corrections.
- Removes approved, unnecessary Thunderbird and LibreOffice packages and their leftover dependencies **only when safety checks allow it**.
- Records the work and before/after OS usage in a permanent service-history file.
- Preserves the existing automatic-update settings. **It does not install updates.**

The maintenance script does **not** intentionally restart WAVE, reboot the WRN, remove recordings, or remove the Ubuntu desktop. If the system differs from the tested configuration or a safety check fails, the script should stop rather than force a change.

## Technician quick start — Ubuntu 22.04

Open the terminal as the normal `wave` user. **Do not use `sudo` for the installer.**

**1. Download the verified maintenance script:**

```bash
wget -qO- https://raw.githubusercontent.com/bbradford1/wrn-maintenance/main/installer.sh | bash
```

The installer places the script in `/home/wave/Downloads/maintenance/` and checks its integrity. It does not run maintenance automatically. If the download or verification fails, stop and report the error.

**2. Run maintenance:**

```bash
cd /home/wave/Downloads/maintenance
sudo bash wrn_maintenance.sh --apply
```

The script performs its approved tasks automatically, without asking technicians to confirm each package removal. It still checks for unexpected conditions and may stop to protect the WRN.

**3. Verify the WRN:**

Confirm that the Ubuntu desktop works, WAVE is accessible, **new video is recording**, and **recent video plays back**. Check the maintenance report for any warnings. Do not finalize if something is wrong.

**4. Finalize the visit:**

```bash
sudo bash wrn_maintenance.sh --finalize
```

Run this command **only after** verifying the desktop, recording, and playback. It records the technician's confirmation and removes temporary files from the maintenance folder, leaving:

```text
/home/wave/Downloads/maintenance/WRN-Service-History.txt
```

This history stays on the WRN for the next service visit and includes previous visits. If a run fails, **leave its reports in place** for troubleshooting.

## Optional: Check before making changes

For a read-only check, use:

```bash
cd /home/wave/Downloads/maintenance
sudo bash wrn_maintenance.sh --preview
```

You can also use `--diagnose` to collect system information without applying maintenance.

## Important precautions

- **Never assume an active WAVE service proves video is recording.** Verify actual footage and playback.
- If an archive drive is disconnected, missing, or unhealthy, stop and investigate separately; routine maintenance will not repair an unmounted archive automatically.
- Some WRNs have different installed applications. Package cleanup is guarded and may be skipped or stopped when the proposed removals differ.
- Ubuntu automatic-update settings are **left as found**. The script does not enable updates or perform package upgrades. The Snap refresh hold is part of the existing maintenance policy.
- Do not reboot or delete recording files just to finish routine maintenance.

## Other tools and older WRNs

**Ubuntu 18.04:** Not supported by the dev.10 pilot installer. The separate `wrn_legacy.sh` utility is for **diagnostics only**; do not run maintenance `--apply` on Ubuntu 18.04.

**OS recording cleanup:** The separate `wrn_os_archive_cleanup.sh` utility can permanently delete recordings that ended up on the OS drive. **It is not part of routine maintenance and is never run automatically.** Use it only with explicit approval after reviewing the footage and confirming the correct archive is recording.

## For the person updating GitHub

Publish matching versions of `installer.sh` and `wrn_maintenance.sh` together: the installer verifies the maintenance script's SHA-256 checksum. If the script changes, the installer checksum must be updated as well. The README may be updated independently.

**Do not upload WRN reports, serial numbers, customer details, or service histories to this public repository.**
