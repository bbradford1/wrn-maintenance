# Changelog

All notable changes to the Hanwha WRN Maintenance toolkit will be documented here.

This changelog tracks **published releases**. Internal development notes and test history are maintained separately.

## [1.0.0] — 2026-11-01

**Initial production release.**

### Added
- A streamlined technician workflow for downloading the toolkit, running guarded maintenance, and confirming system operation before cleanup.
- Diagnostics and safety checks for WRN operating-system health, archive mounts, and WAVE service status.
- Guarded archive configuration repairs, including duplicate mount entries, persistent UUID-based mounts, and appropriate mount timeout settings.
- Support for multiple archive drives and partition-backed archive filesystems, with verification before configuration changes.
- Guarded recovery tools for archive mount issues and systemd service timeout conditions.
- OS maintenance procedures for approved package, Snap, logging, and temporary-file cleanup.
- Detection and guarded cleanup of orphaned Snap mount units, plus conditional recovery of a failed `dmesg.service`.
- Technician-readable multi-drive status reporting and a permanent WRN service-history record.
- A technician quick-start README and a separate technical guide.

### Safety and scope
- No automatic deletion or migration of customer recordings.
- No automatic removal of WAVE databases.
- Unexpected or ambiguous archive configurations stop for review rather than being modified automatically.
- Recording and playback must be checked in WAVE before finalizing maintenance.

### Compatibility
- Qualified on supported Gen 2 WRNs running Ubuntu 22.04; legacy systems require separate handling as documented in the README and technical guide.

---

For installation instructions, see [README.md](README.md). For detailed script behavior and safeguards, see [TECHNICAL-GUIDE.md](TECHNICAL-GUIDE.md).
