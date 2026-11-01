# Hanwha WRN Maintenance

**Version 1.0.0 · Technician Quick Start**
For **Hanwha Gen 2 WRNs running Ubuntu 22.04**. Ubuntu 18.04 (Gen 1) is diagnostics-only and **must not** run this maintenance procedure.

> **Release status:** This documentation and version 1.0.0 are staged for PR review. Do not use the `main` commands below until the PR has been approved and merged. Do not deploy to a fleet without the required authorization.

## What does this do?

The WRN maintenance toolkit helps prevent common long-term recorder issues. During an approved maintenance session, it:

- Checks the system and archives before doing any work, and stops if it finds an unsafe condition.
- Corrects known archive mount configuration issues (including UUIDs and timeouts) on verified archive drives.
- Offers guarded repairs for duplicate archive entries and unusually short systemd timeouts when detected.
- Cleans up certain unnecessary OS packages, Snap leftovers, and old logs, while preserving required software.
- Checks WAVE service status and saves a service history for future visits.

**It does not automatically erase, move, or reindex recordings.** OS recording spillover is reported for review, not deleted. It does not format drives or automatically reboot the WRN. A successfully mounted archive does **not** prove that WAVE is recording; check in the client.

## Before you start

Make sure you have approval to maintain this recorder, access to its Ubuntu terminal (Cockpit terminal or SSH), working `sudo` credentials, and a maintenance window if needed. **Run as the normal `wave` user**. Use an interactive terminal: the maintenance script may ask you to answer **Y/N**.

If any archive expected at the site is offline, stop and escalate; don't assume an empty `/mnt/sd*` folder is an archive. Don't run the repair on an unknown or unsupported system.

## Step 1 — Download (no maintenance actions)

```bash
wget -qO- https://raw.githubusercontent.com/bbradford1/wrn-maintenance/main/installer.sh | bash
```

You should see **`INSTALL COMPLETE`** after the installer verifies and downloads the required scripts. **The installer does not run maintenance.** If it reports `STOP` or a checksum mismatch, do not continue.

## Step 2 — Run guided maintenance

```bash
cd /home/wave/Downloads/maintenance && sudo bash wrn_maintenance.sh --apply
```

Read each prompt and review proposed repairs. Answer **Y** only when the displayed correction matches the recorder and you are authorized to proceed. The script may stop on disk or configuration problems; **a STOP is a safeguard, not a reason to force a repair**. Record the message and contact engineering/support.

During the run, you may see notes about **optional archive bays that have no drives installed**. Those entries are preserved and are not automatically treated as failed physical drives; confirm the site's expected drive count.

## Step 3 — Verify WAVE, then finish

Before cleaning up reports, confirm all three:

- The **Ubuntu desktop** is working.
- The **WAVE client** connects and shows the server normally.
- **Live recording and recorded playback** both work on an actual camera.

If any check cannot be completed, answer **N** at the final prompt and leave the files for review. If all checks pass, answer **Y** when asked to finalize. If you previously answered N, you may finalize later:

```bash
cd /home/wave/Downloads/maintenance && sudo bash wrn_maintenance.sh --finalize
```

Finalization retains **`/home/wave/Downloads/maintenance/WRN-Service-History.txt`** and removes the temporary scripts and reports in that directory. **Save any reports needed for troubleshooting before finalizing.** Protected system backups, such as fstab backups, are stored separately.

## Need help?

| What you see | What to do |
|---|---|
| `STOP` or an unexpected archive/device | **Do not force it**; save the terminal output and contact engineering/support. |
| Missing primary archive | Don't run normal maintenance; use supervised recovery/diagnostics. |
| Missing optional bay message | Confirm whether the recorder actually has a drive in that bay. |
| WAVE active but no video/playback | Keep reports (**N** at final prompt); investigate in WAVE. |
| Need a diagnostic report only | Run `cd /home/wave/Downloads/maintenance && sudo bash wrn_maintenance.sh --diagnose` after installing. |
| Need to retain reports | Answer **N**; do not run `--finalize` yet. |

**More technical detail:** see [TECHNICAL-GUIDE.md](TECHNICAL-GUIDE.md). Release and test evidence is in [TEST-PLAN.md](TEST-PLAN.md) and [CHANGELOG.md](CHANGELOG.md).
