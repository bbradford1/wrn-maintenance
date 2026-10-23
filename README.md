# Hanwha WRN Maintenance

**Status: DEVELOPMENT / DIAGNOSTICS ONLY — NOT PRODUCTION-QUALIFIED**  
Current script version: `1.0.0-dev.1` (October 2026)

This repository contains tools for assessing Hanwha WRN systems, with separate scripts for Ubuntu 22.04 and legacy Ubuntu 18.04. The current scripts collect local diagnostic information; **they do not perform maintenance or repairs**.

> **For technicians:** Do not deploy or run these development scripts on customer production WRNs until the release has been approved and tested. The instructions below describe the intended workflow for authorized testing.

## 1. Download the correct script

Log in to the WRN desktop as the normal user (not root), open a terminal, and run:

```bash
wget -qO- https://raw.githubusercontent.com/bbradford1/wrn-maintenance/main/installer.sh | bash
```

The installer detects the Ubuntu release and downloads **one script** into `~/Downloads`:

| Ubuntu version | File downloaded |
| --- | --- |
| 22.04 | `wrn_maintenance.sh` |
| 18.04 | `wrn_legacy.sh` |
| Other | Unsupported; no script downloaded |

The installer verifies the downloaded script against an embedded SHA-256 checksum, checks Bash syntax, and rejects CRLF line endings. It never runs the downloaded script. **Check for the `DOWNLOAD VERIFIED` message before proceeding**; a pipeline alone may not reliably signal a failed download.

## 2. Run diagnostics (authorized test systems only)

```bash
cd ~/Downloads
sudo bash wrn_maintenance.sh --diagnose
```

For an Ubuntu 18.04 legacy WRN, use:

```bash
cd ~/Downloads
sudo bash wrn_legacy.sh --diagnose
```

To view the version without running diagnostics:

```bash
bash wrn_maintenance.sh --version
# Or on an Ubuntu 18.04 WRN:
bash wrn_legacy.sh --version
```

Running `sudo bash wrn_maintenance.sh` or `sudo bash wrn_legacy.sh` without arguments also selects diagnostics in this development release. **There is no enabled `--apply` mode.**

## 3. Retrieve the report

Each diagnostic run writes a timestamped text report to the invoking user's `~/Downloads` directory. Use the Cockpit file browser to retrieve it through the approved support workflow. Reports may include hostnames, network/device information, disk serial numbers, and WAVE event details: **do not upload reports to this public GitHub repository**.

A WAVE service that reports `active`, or an archive that appears mounted, is **not proof that recording and playback are working**. Verify recording through the WAVE client separately.

## Safety and scope

This development version:

- Does **not** stop/restart the WAVE Media Server, journald, Cockpit, or network services.
- Does **not** reboot, mount/unmount disks, edit `/etc/fstab`, run filesystem repair, or delete recordings.
- Does **not** clean logs, purge Snap applications, change APT configuration, or install scheduled jobs.
- May read WAVE event data, system logs, device metadata, and filesystem information to produce a local report.
- Has **not yet been qualified on production WRNs**; diagnostics are intended for supervised testing first.

If an archive is disconnected or the OS disk is full, **collect the diagnostic report before attempting a separate, approved repair**. Do not delete WAVE data merely because the OS drive is nearly full.

## Files

| File | Purpose |
| --- | --- |
| `installer.sh` | Download-only Ubuntu detection, verified script retrieval |
| `wrn_maintenance.sh` | Ubuntu 22.04 read-only WRN assessment |
| `wrn_legacy.sh` | Ubuntu 18.04 read-only WRN assessment |
| `README.md` | Technician instructions and current release limitations |

## Release and integrity policy

The installer currently downloads development builds from `main` and validates them against SHA-256 values embedded in `installer.sh`. **Do not update either script without updating and retesting the installer's corresponding checksum.** For production releases, the distribution process should move to immutable tagged releases with reviewed hashes.

To inspect a downloaded script without executing it:

```bash
bash -n ~/Downloads/wrn_maintenance.sh
sha256sum ~/Downloads/wrn_maintenance.sh
```

Use `wrn_legacy.sh` in those commands for a legacy WRN. `bash -n` checks syntax, not operational safety.

## Project status

This repository is a replacement development project for the older `WRN-V3` script collection. The previous deployment should remain in place until the new package completes qualification and an approved migration is communicated. No production maintenance release has been published yet.
