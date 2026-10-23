# Hanwha WRN Maintenance

**Status: controlled rollout testing — October 23, 2026**

- **Ubuntu 22.04 LTS:** `wrn_maintenance.sh` **1.0.0-dev.5**. Successfully applied on **two** 7 Brew production WRNs under supervision, with WAVE recording verified afterward. One WRN also passed a controlled reboot after a UUID-based archive fstab repair. **Not yet approved for unattended or fleet-wide deployment.**
- **Ubuntu 18.04 LTS:** `wrn_legacy.sh` **1.0.0-dev.1** is **diagnostics only**. Its maintenance/repair workflow has **not** been qualified. Do **not** use `--apply` on 18.04.
- **Installer:** `installer.sh` **1.0.0-dev.5** detects the Ubuntu release, downloads the corresponding script to the logged-in user's `~/Downloads`, checks SHA-256 and Bash syntax, and **does not run maintenance**.

> **Production safety:** This utility is intended for supervised, one-time service of WRN recorders. Always verify live recording and playback in the WAVE client after maintenance. Do not run a repair when the archive is missing, unidentified, or otherwise unhealthy; escalate instead. Keep the existing WRN-V3 workflow available until this replacement is formally accepted.

## Quick start — Ubuntu 22.04

Use the WRN's ordinary desktop account (normally `wave`) in Cockpit Terminal. **Do not use `sudo` for the installer.**

```bash
wget -qO- https://raw.githubusercontent.com/bbradford1/wrn-maintenance/main/installer.sh | bash
```

The installer verifies its download and reports `DOWNLOAD VERIFIED`. It does not execute the downloaded file. If verification fails, **stop**; do not bypass or ignore the error.

Verify the downloaded maintenance script:

```bash
cd ~/Downloads
bash -n wrn_maintenance.sh
sha256sum wrn_maintenance.sh
bash wrn_maintenance.sh --version
```

Expected modern script version: `1.0.0-dev.5`.

Expected SHA-256:

```text
3d37308693ab50f3bd84c69db177eee13dcd348c2342aad24662b667c6910a21
```

### 1. Inspect the read-only preview

```bash
cd ~/Downloads
sudo bash wrn_maintenance.sh --preview
```

Retrieve the timestamped `WRN-KB-Repair-Preview_*.txt` file from Downloads using Cockpit. Review all warnings and the proposed changes. The preview does **not** perform the repair; it is not a guarantee that a later apply will succeed.

**Do not apply** if WAVE/desktop/archive safety checks fail, if the archive is not mounted read/write at `/mnt/sda`, if its identity is ambiguous, or if the planned work doesn't match the machine. Escalate with the preview report.

### 2. Apply only on an approved supervised WRN

```bash
cd ~/Downloads
sudo bash wrn_maintenance.sh --apply
```

The script collects before/after diagnostics and writes a timestamped maintenance transcript in Downloads. It checks before repairing and skips already-satisfactory items where possible. **Do not reboot just to finish maintenance**; plan a reboot separately if one is needed for verification.

### 3. Verify the machine afterward

In Cockpit and the WAVE client, confirm:

1. WAVE Media Server is active and the system is accessible.
2. The archive is mounted read/write at `/mnt/sda`.
3. **New footage is actually being recorded and recent footage plays back.** An active service alone is not proof.
4. The maintenance log shows the expected KB results, and `snap refresh --time` reports `hold: forever` where that policy was applied.
5. Any warnings, missing drives or failed systemd services have been reviewed rather than assumed repaired.

Download the maintenance log and the before/after diagnostics before cleaning up. Treat any failed step or unexplained error as **incomplete maintenance**, even if some cleanup succeeded.

## Ubuntu 18.04 — diagnostics only

Run the same **non-sudo installer** command above. It downloads `wrn_legacy.sh` instead of the modern script.

```bash
cd ~/Downloads
bash -n wrn_legacy.sh
sudo bash wrn_legacy.sh --diagnose
```

Expected legacy SHA-256:

```text
9f2f878669fc741f1b18cf8e0001b8128c791191a8218fad50e76350b492e8e5
```

**Do not use `--apply`, or run the 22.04 maintenance script on Ubuntu 18.04.** Collect and review the diagnostics before designing and testing any legacy changes.

## What the Ubuntu 22.04 maintenance covers

| Area | Checks and conditional actions | Limits |
| --- | --- | --- |
| **Hanwha logging/no-boot KB** | Checks rsyslog syntax and service state, parses logrotate configuration, uses existing log rotation rules for selected oversized logs (100 MiB threshold), and performs bounded archived-journal cleanup. | Does not recursively change `/etc` ownership, indiscriminately delete logs, or automatically rewrite invalid rsyslog/logrotate configuration. Existing nonfatal rotation warnings may remain. |
| **Hanwha archive/fstab KB** | Verifies a mounted read/write ext4 recording archive and its UUID, checks `/mnt/sda` fstab entries, makes a verified UUID-based correction when needed, backs up fstab, validates the change and provides rollback safeguards. | Does not run `mount -a`, unmount/mount the archive, perform `fsck` or journal replay, or restart WAVE. Extra entries for missing `/dev/sdb`–`/dev/sdd` are flagged **without automatic removal**. |
| **Snap cleanup and policy** | Applies `snap refresh --hold=forever`, verifies the hold, removes approved **disabled** Snap revisions and clears the Snap download cache. | Retains active Snap applications, including Firefox and Snap Store. A refresh hold stops **automatic** refreshes, not manual installs or other package managers. It also postpones automatic Snap security updates; this is an explicit maintenance policy. |
| **Safety and reports** | Checks WAVE, desktop, OS and archive prerequisites; collects before/after diagnostics and a maintenance log. | No scripted WAVE restart, network reconfiguration, automatic reboot, filesystem repair, or recording deletion. |

An archive appearing `100%` utilized while maintaining approximately 30 GB of reserved free space can be normal for the configured WAVE recording policy; do **not** treat that percentage alone as a failure. Evaluate the actual archive mount and recording behavior. An OS drive becoming full is a separate issue.

## Reports: where to find them

Reports are written to the invoking desktop user's **Downloads** directory, normally `/home/wave/Downloads`:

- `WRN-KB-Repair-Preview_*.txt` — planned changes and warnings, read-only.
- `WRN-Maintenance_*.txt` — apply actions, skips, failures and final summary.
- `WRN-Diagnostics_*.txt` — detailed before/after system state.

The script attempts to make generated reports accessible to the operator. Reports can include serial numbers, filesystem IDs, storage paths and customer/site information. Transfer them through approved support channels. **Never upload reports or site identifiers to this public GitHub repository.**

### Cockpit shows “Forbidden” when downloading a report

First refresh Cockpit Files and try downloading the file again. If the report belongs to root or is not readable, use this targeted ownership/permission repair:

```bash
sudo find /home/wave/Downloads -maxdepth 1 -type f \( -name 'WRN-Maintenance_*.txt' -o -name 'WRN-Diagnostics_*.txt' -o -name 'WRN-KB-Repair-Preview_*.txt' \) -exec chown wave:wave {} + -exec chmod 644 {} +
```

If Cockpit still refuses the direct download, make one archive of the reports (this does not alter the originals):

```bash
cd /home/wave/Downloads
sudo tar -czf /tmp/WRN-Reports.tar.gz WRN-*.txt
sudo chown wave:wave /tmp/WRN-Reports.tar.gz
cp /tmp/WRN-Reports.tar.gz /home/wave/Downloads/
```

Then try downloading `WRN-Reports.tar.gz` through Cockpit. A persistent Forbidden error on the archive may indicate Cockpit configuration/session problems rather than file permissions. **Do not restart Cockpit or network services remotely just to retrieve a report**; escalate or use an approved alternate transfer method.

## Common warnings and what to do

| Finding | Meaning / technician action |
| --- | --- |
| `DOWNLOAD VERIFIED` | Installer downloaded the correct script and verified checksum/syntax. No maintenance ran. |
| Checksum mismatch or download failure | **STOP.** Do not run an unverified file. Confirm GitHub `main` contains the matching installer and scripts, network access, and OS version; escalate if unresolved. |
| `SKIP: archive already has a UUID-based ext4 fstab entry` | Normal: it may already be correctly configured. |
| Missing `/dev/sdb`, `/dev/sdc`, `/dev/sdd` | Additional fstab entries reference absent devices. Script **reports** these; it does not delete them. Check the hardware/bay configuration before any separate correction. |
| Archive not mounted, read-only, unknown UUID or duplicate `/mnt/sda` entries | **STOP / escalate.** Do not run `fsck` on a mounted archive or manually modify fstab without an approved recovery plan. |
| `size overrides daily/hourly` in logrotate output | Configuration parses, but the specified `size` rule overrides the schedule. Review if recurring or problematic; it is not automatically rewritten. |
| Failed `dmesg.service` or `isc-dhcp-server6.service` | Observed on test units, but **not evidence of a Snap mount problem**. Treat as separate service findings. |
| Failed `snap-*.mount` units | Record the units and investigate; do not delete mount units, reset failures or modify Snap state indiscriminately. |
| Snap `hold: forever` | Automatic Snap refreshes are blocked. This does **not** protect against manual reinstallation. |
| Historical `systemStorageFull` WAVE events | May predate cleanup. Compare timestamps and current OS free space; don't assume they indicate an active failure. |
| WAVE recording-file rename warnings around shutdown | Have been seen during controlled WRN shutdowns; check new recordings and playback after boot instead of assuming an archive defect. Escalate if errors continue while running. |

## Cleanup after successful verification (optional)

**Only after** you have collected needed reports and verified WAVE recording/playback, run this single command to remove just the downloaded WRN scripts and generated WRN text reports from Downloads:

```bash
sudo find /home/wave/Downloads -maxdepth 1 -type f \( -name 'wrn_maintenance.sh' -o -name 'wrn_legacy.sh' -o -name 'WRN-Diagnostics_*.txt' -o -name 'WRN-Maintenance_*.txt' -o -name 'WRN-KB-Repair-Preview_*.txt' -o -name 'WRN-Reports.tar.gz' \) -delete
```

This **permanently removes** matching files only from Downloads. It does not delete WAVE recordings or affect the archive. Do not run this command before saving reports needed for an active support case. If you used a TAR workaround, note that its temporary `/tmp/WRN-Reports.tar.gz` copy is outside this cleanup scope.

## Maintainer notes / release controls

- The installer has **hardcoded SHA-256 fingerprints**. Any change to either distributed `.sh` file requires updating the corresponding installer hash in the **same commit**. A README-only edit requires no installer hash change.
- Do not publish a script change to `main` without reviewing the installer hash, Bash syntax, LF line endings and downloaded copy. The production technician must never bypass checksum rejection.
- Continue **supervised** testing on additional Ubuntu 22.04 WRNs, including systems requiring conditional repairs. Validate Ubuntu 18.04 independently before enabling any maintenance behavior there.
- Retain backup copies of fstab produced by maintenance and do not delete them as part of Downloads cleanup.
- Keep the older WRN-V3 tooling available until the replacement is fully accepted. For a stable rollout, prefer an immutable version tag/commit-pinned installation source rather than relying indefinitely on changing `main`.

**Support escalation:** If the archive is unavailable, WAVE is not recording, there is a disk I/O/ext4 error, or a safety guard fails, stop applying fixes and provide the preview/diagnostic reports to the responsible Hanwha support or integrator contact. Do not restart WAVE, reconfigure networking, run filesystem repairs, or reboot an inaccessible machine without an approved recovery plan.
