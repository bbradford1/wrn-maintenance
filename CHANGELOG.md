# WRN Maintenance Changelog

## 2026-10-31 — 1.0.0-dev.17-tech-pilot (test branch candidate; NOT field-qualified)
- Begin guarded Y/N technician workflow in existing Ubuntu 22.04 maintenance engine.
- Detect exact global systemd 3s/3s override; preview/apply validated timeout helper only after Y, then verify 90s/90s before proceeding.
- Detect multiple active `/mnt/sda` fstab entries; preview/apply existing guarded dedup helper only after Y; recheck single entry.
- For unmounted `/mnt/sda`, offer read-only archive inspection and STOP. No automatic archive recovery.
- Offer cleanup after a successful core maintenance run. Interactive finalization now requires personal confirmation of desktop, new recording and playback, and rejects repeat finalization without a new successful visit.
- Preserve core archive UUID/60s device/120s mount, Snap, logging, OS cleanup, and package-guard logic from dev.11.
- Update offline-capable installer with test-branch source URL and pinned SHA-256 for six Ubuntu 22.04 files; Ubuntu 18.04 diagnostic-only retained.
- Retire obsolete `wrn_downloads_cleanup.sh` from new package; no changes made to GitHub `main`.
- Known limitation: physical WRN and GitHub branch end-to-end tests still required.

## Earlier development
See the uploaded October 27, 2026 `CHANGELOG.md` for historical pilot notes. This candidate does not rewrite those previously validated helper scripts.
