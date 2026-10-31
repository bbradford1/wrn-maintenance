# Hanwha WRN Maintenance — technician workflow pilot (dev.17)

**LAB / TEST BRANCH ONLY. NOT YET FIELD-QUALIFIED.** Ubuntu 22.04 maintenance; Ubuntu 18.04 diagnostic-only.

This is a candidate based on the 12 scripts/documentation files supplied October 31, 2026. The existing guarded maintenance engine and supporting helper logic are retained; the primary changes are an interactive preflight and a prompted finalizer. The lab previously passed fresh-image maintenance and reboot tests with dev.11, **not yet with this dev.17 candidate**.

## Target technician workflow after test-branch upload

Run the installer as the normal `wave` user (not sudo):

```bash
wget -qO- https://raw.githubusercontent.com/bbradford1/wrn-maintenance/technician-workflow-pilot/installer.sh | bash
```

Then run maintenance:

```bash
cd /home/wave/Downloads/maintenance
sudo bash wrn_maintenance.sh --apply
```

The installer downloads and checksum-verifies six scripts on Ubuntu 22.04, but **does not run maintenance**. The maintenance script checks effective global systemd timeouts. If the exact factory 3s/3s values are present, the technician can select Y to preview/apply the existing guarded restoration helper. After verifying 90s/90s, maintenance continues. If duplicate active `/mnt/sda` entries are present, it offers the guarded dedup helper and checks the result. The core maintenance engine then executes its existing guarded archive UUID/timeouts, logging, Snap and package routines.

After successful maintenance, the technician is asked whether the Ubuntu desktop, new WAVE recording and playback have all been verified and whether to clean the maintenance folder. If Y, finalization proceeds without another prompt; a separately invoked `--finalize` asks for its own explicit attestation. N preserves scripts/reports; later manual cleanup remains available:

```bash
cd /home/wave/Downloads/maintenance
sudo bash wrn_maintenance.sh --finalize
```

If the archive is not mounted, the script **does not automatically recover**. It may offer a **read-only** inspection through `wrn_archive_recovery.sh --inspect` and then stops. Recovery (`--recover`) requires a separate supervised decision after reviewing disk identity, filesystem and WAVE recording state. OS fallback video deletion is never automated. Do not delete WAVE SQLite databases, metadata, recordings or archives via routine maintenance.

If the script is run without a controlling terminal and an interactive decision is needed, it stops safely rather than guessing. Use `--diagnose` or `--preview` to collect read-only information without prompts. A Y/N answer is not a substitute for actually observing new video recording and playback; if there are no cameras, decline finalization.

## Test offline, before GitHub

Upload/extract this candidate into a **separate directory** on the lab WRN (not the production maintenance directory). Check `SHA256SUMS.txt`, then install via:

```bash
cd /home/wave/Downloads/WRN-Technician-Workflow-Pilot-20261031
sha256sum -c SHA256SUMS.txt
bash installer.sh --local-source "$PWD" --target-dir /home/wave/Downloads/WRN-Tech-Pilot-Test
```

This verifies local installation without replacing production maintenance scripts. **Do not execute `--apply` from the isolated test folder**: the production script intentionally expects `/home/wave/Downloads/maintenance`. Once the candidate is reviewed and prior evidence is backed up, perform the live lab test with `--offline-bundle "$PWD"` to publish to that standard directory, then run `sudo bash wrn_maintenance.sh --apply` from there.

## Guardrails

- Production GitHub `main` is not updated by this package.
- No automatic WAVE restart, reboot, archive format, fsck, journal replay or recording deletion.
- Archive helpers retain their independent safeguards.
- The known `isc-dhcp-server6.service` no-subnet failure is reported but not disabled or modified.
- Review the WAVE Storage Management configuration: analytics and motion metadata must not unintentionally use the small OS filesystem. The script cannot confirm the client/UI setting.
- Source and checksum updates must be committed **together** on the test branch; any mismatch causes installation failure.
- Do not publish customer/device reports, serial numbers, service histories or test files in the public repository.

See `TEST-PLAN.md` and `DEPLOYMENT-NOTES.txt`.
