# Pull Request Review — WRN Maintenance 1.0.0

**Target branch:** `main`  
**Source:** proposed `technician-workflow-pilot` promotion (or a dedicated release branch copied from it).  
**Status:** DRAFT — local package prepared; no GitHub PR has been created or merged by this work.

## Purpose

Promote the lab-qualified two-command Gen 2 Ubuntu 22.04 workflow from the test branch into `main`, with technician-first documentation and a corrected optional-bay status message. The detailed engineering guide is deliberately separate from the README.

## Three final release adjustments

1. Replace the outdated README with the short technician guide: what it does, two commands, Y/N decision points, when to stop, independent video checks, and optional finalization.
2. Replace the misleading `WARNING KB2` text with `NOTICE KB2` only for **configured but not mounted optional** `/mnt/sdb`–`/mnt/sdd` bays. Mounted second drives no longer trigger that message. **No change** to the tested `wrn_archive_multidrive.sh` helper or archive repair path.
3. Use release version **1.0.0** (formerly `1.0.0-dev.19.6-tech-pilot`) and point the production installer to **`main`**, not `technician-workflow-pilot`. Update the installer SHA-256 pin and `SHA256SUMS.txt`.

## Technical review items before merge

- [ ] Confirm PR diff is limited to expected documentation, release identifiers, the optional-bay message, installer source branch and checksum.
- [ ] Confirm all eight Ubuntu 22.04 script checksums in installer match committed files and run `bash -n` on all shell scripts.
- [ ] Confirm live `main` has the complete new script set in the **same commit** as installer; missing or mixed-version helper files must not be released.
- [ ] Perform a dry-run **offline-bundle installer smoke test** for the staged package. The staged online installer points at `main` and therefore MUST NOT be used before merge (it would pull old main files or fail checksum verification).
- [ ] Retest the brief optional-bay output and displayed 1.0.0 version on the lab or isolated mocks. Main maintenance was tested as dev.19.6, but these release-label and reporting changes have not yet been rerun on the recorder.
- [ ] Confirm Ubuntu 18.04 path remains diagnostics-only, not an implicit `--apply`.
- [ ] Use approved GitHub PR review, merge only after sign-off, then smoke-test the real production URL on a controlled lab system before fleet rollout.
- [ ] Document scope and limitations: full three-/four-drive fault repair and customer reboot persistence are not qualified; preserve video; no auto spillover deletion/migration.

## Proven checks before release edits

- Tests 077–085: two physical archives configured and mounted; partition-backed repair and reboot persistence; WAVE service active.
- Tests 086–090: main workflow integration, supervised `--apply`, desktop/recording/playback, and finalization.
- Tests 091–093: upgraded archive status display and intentional second-archive misconfiguration fixed automatically by main `--apply`, followed by clean reboot persistence.
- Test 094: user confirmed desktop, client, recording and playback, and ran finalization. The final directory listing was not independently supplied for Test 094.

## Post-merge instructions

Use the first two commands in the README **only after** the main-branch PR is merged and verified. Keep a rollback commit/branch. Begin with a controlled supervised deployment; do not silently start a nationwide fleet rollout on merge alone.
