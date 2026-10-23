# Hanwha WRN Maintenance — controlled testing

**Status (2026-10-23): Ubuntu 22.04 `1.0.0-dev.5` is qualified on one 7 Brew production WRN under supervision, including a live fstab UUID repair, reboot, and successful WAVE recording/playback checks. It is NOT yet fleet-qualified. Ubuntu 18.04 `1.0.0-dev.1` is DIAGNOSTICS ONLY and not maintenance-qualified.**

## Scope

- `wrn_maintenance.sh` — Ubuntu **22.04**: `--diagnose` (default), `--preview`, `--apply`, `--version`, `--help`. The conditional `--apply` checks the Hanwha logging and archive-fstab KB topics, applies an indefinite Snap automatic-refresh hold, removes approved disabled Snap revisions, and cleans the Snap download cache. An unmounted, ambiguous, or unverified archive blocks apply. No WAVE restart, networking change, mount/unmount, filesystem repair, video deletion, or reboot is requested.
- `wrn_legacy.sh` — Ubuntu **18.04**: `--diagnose` only. No cleanup or repair operations. **Do not pass `--apply`.**
- `installer.sh` — checks OS version, downloads exactly one corresponding file into `~/Downloads`, verifies hardcoded SHA-256 and Bash syntax, then exits. **Never executes the downloaded script.**

## Onsite technician procedure — supervised testing

Log in as the ordinary WRN desktop user (usually `wave`) and run:

```bash
wget -qO- https://raw.githubusercontent.com/bbradford1/wrn-maintenance/main/installer.sh | bash
```

**Do not run the one-liner until all four files have been committed to `main` with matching hashes.** The installer does not change the WRN itself, but an incomplete repository update will lead to checksum rejection.

On Ubuntu 22.04:

```bash
cd ~/Downloads
bash -n wrn_maintenance.sh
sha256sum wrn_maintenance.sh
sudo bash wrn_maintenance.sh --preview
# Review WRN-KB-Repair-Preview_*.txt before continuing.
# Only on an explicitly approved supervised test machine:
sudo bash wrn_maintenance.sh --apply
```

On Ubuntu 18.04 (diagnostics only):

```bash
cd ~/Downloads
sudo bash wrn_legacy.sh --diagnose
```

Diagnostics, previews, and maintenance transcripts are saved in the invoking operator's Downloads folder. Use Cockpit to download reports; if the browser rejects direct downloads, bundle reports as a `.tar.gz` file. Reports may contain device identifiers and sensitive customer information; **never put WRN reports in this public repository.**

## KB coverage and safety boundaries

**Logging KB:** checks rsyslog syntax/activity, parses logrotate configuration, conditionally invokes existing logrotate rules when approved logs exceed 100 MiB, and vacuums archived journals conservatively. An invalid rsyslog/logrotate configuration blocks apply instead of auto-rewriting it. The legacy KB's recursive `/etc` ownership changes and indiscriminate deletions are expressly excluded. Existing logrotate warnings may remain.

**fstab KB:** requires exactly one `/mnt/sda` fstab entry and a confidently identified mounted read/write ext4 disk. Where needed, stages a UUID-based corrected entry, validates, backs up `/etc/fstab`, installs, and checks/rolls back on validation failure. Missing extra `/dev/sdb`–`/dev/sdd` fstab entries are reported, **not automatically removed**. No `mount -a`, WAVE restart, `fsck`, or automatic reboot.

**Snap policy:** `snap refresh --hold=forever` intentionally blocks automatic Snap refresh, including Snap security refreshes. It does **not** prevent manual installs, non-Snap software updates or other installers. Approved disabled revision removal and cache cleaning are distinct from removing active applications; active Snaps remain installed.

Check actual WAVE recording and playback manually after any apply. A successful service/mount check does not prove recording. If systemd reports other failed services, review separately; do not assume Snap failures.

## Release controls

Versions and SHA-256 fingerprints are pinned in `installer.sh`. When updating a distributed script, update its corresponding installer hash in the same GitHub commit. Do not promote to fleet use until an additional Ubuntu 22.04 WRN with needed corrective work is successfully tested; qualify Ubuntu 18.04 separately. Keep the older WRN-V3 scripts operational until the replacement is accepted. A later stable release should use immutable GitHub tags/commit-pinned sources.
