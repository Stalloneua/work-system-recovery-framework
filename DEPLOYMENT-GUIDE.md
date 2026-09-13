# Work System Recovery Framework

## Purpose

This framework deploys and recovers a cloud-first work environment built around Codex, Obsidian, a central Google Sheets tracker, Google Drive artifacts, Git source repositories and reconstructable chat records. It is organization-agnostic: client-specific directories, IDs, access rules and source inventories are supplied through local configuration and are never committed to the reusable source repository.

The target outcome is one technical command plus unavoidable secure account confirmations. No recovery design should bypass Google OAuth, MFA, Codex sign-in, Syncthing device approval or the independently stored backup passphrase.

## Sources of truth

| Data class | Canonical source | Recovery role |
|---|---|---|
| Tasks, statuses, files and activity | Central Google Sheet | Online operational state |
| Knowledge, decisions and reconstructable chat records | Obsidian Vault | Versioned knowledge layer, live-replicated and backed up |
| Google Docs, Sheets and Slides | Google Drive native files | Cloud-first documents |
| PDF, DOCX, XLSX, ZIP and media deliverables | Google Drive file IDs | Durable binary artifacts after QA |
| Source code | Git remote | Version control and clean-machine checkout |
| Disaster recovery | Encrypted restic repository in Google Drive through rclone | Historical, independent snapshots |
| Chat and project organization | Tracker, Obsidian and chat-organization manifest | Reconstructs context even when sidebar UI differs |

## Security model

- The restic passphrase is never stored in Git, Obsidian, the tracker or a Drive document.
- The scheduled task receives a Windows DPAPI-encrypted local copy, which works only for the same Windows user and machine.
- A separate recovery copy must exist in a password manager or another controlled offline location.
- OAuth tokens stay in the local rclone configuration and are recreated by sign-in on a replacement machine.
- Reconstructable records avoid unnecessary personal data and secrets.

## Initial deployment on the source machine

1. Ensure Windows is current and at least 10 GB is free.
2. Place the framework in `Documents\Codex\work-system-recovery`.
3. Copy `backup-sources.example.json` to `backup-sources.json` and replace example paths with the approved portable foundation.
4. Run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Initialize-GoogleDriveFoundation.ps1 -RegisterSchedule
```

5. Approve Google OAuth in the browser.
6. Enter a restic passphrase of at least 16 characters and store its recovery copy outside the computer.
7. Verify:

```powershell
.\Test-WorkSystemBackupHealth.ps1
.\Test-DisasterRecovery.ps1
.\Repair-WorkSystem.ps1
```

The deployment is accepted only when all three checks pass and a clean-directory restore contains the operating notes, direction register and chat manifest.

## Optional remote Windows host bootstrap

To make a Windows workstation manageable from Codex without exposing credentials, generate an ED25519 key on the controlling machine and run the following from the framework directory on the target:

```cmd
set "WORKSYSTEM_SSH_PUBLIC_KEY=ssh-ed25519 AAAA..." && Enable-WorkSystemSsh.cmd
```

The launcher requests Administrator elevation, installs Windows OpenSSH Server if needed, starts `sshd` automatically, enables inbound TCP 22, appends the key to the correct administrator or user key store, applies restrictive ACLs and returns a JSON verification report. Prefer a private Tailscale address for machines on different networks; do not expose TCP 22 through the public router. Keep password authentication available until a real external key login has passed.

## Scheduled operation

| Task | Default | Result |
|---|---|---|
| Work System Encrypted Backup | Daily 02:00 | Encrypted Foundation snapshot |
| Work System Verified Scratch Cleanup | Daily 03:00 | Removes only published and remotely verified scratch artifacts after retention |
| Work System Backup Health | Daily 06:00 | Fails if the newest snapshot is unavailable or older than 30 hours |
| Work System Backup Maintenance | Sunday 04:00 | Keeps 14 daily, 8 weekly and 12 monthly snapshots, prunes and checks the repository |

## Clean-machine recovery

Prerequisites: Windows, network access, the repository path and the independently stored restic passphrase.

After downloading and verifying the pinned release package, run one command from its extracted directory:

```cmd
Install-WorkSystem.cmd
```

The launcher calls the pinned `bootstrap.ps1` with the canonical Google Drive restic repository. Account sign-ins, MFA, Syncthing device approval and the independently stored passphrase are secure confirmations, not extra deployment commands.

From the framework directory run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\bootstrap.ps1 -Repository "rclone:work-drive:Work System/00 Recovery/restic-foundation" -Apply
```

The script installs Git, Codex, Obsidian, Syncthing, restic and rclone when missing; requests Google OAuth; restores the latest snapshot to staging; validates required recovery markers; and applies the restored Documents tree only after validation.

After the command:

1. Sign in to Codex or ChatGPT.
2. Open the restored Obsidian Vault.
3. Approve the replacement Syncthing device.
4. Open the portfolio dashboard and central tracker.
5. Re-clone source repositories whose working trees are intentionally not stored in Drive.
6. Recreate local secrets from the password manager.
7. Run `Repair-WorkSystem.ps1 -RepairSchedules -RunBackup -RunRestoreTest`.

## Repair playbook

### Backup did not run

```powershell
.\Repair-WorkSystem.ps1 -RepairSchedules
.\Invoke-WorkSystemBackup.ps1 -Check
```

### Repository is unavailable

```powershell
rclone listremotes
rclone lsd work-drive:
restic snapshots
```

If OAuth expired, reconnect the `work-drive` remote. Do not recreate or delete the repository.

### Vault replication is stale

Confirm that Syncthing reports `idle`, zero needed files and a connected peer. Syncthing is a live replica, not the historical backup.

### Local disk is full

Only purge reinstallable dependencies, caches, crash dumps and files inside `%LOCALAPPDATA%\WorkSystemScratch` that have a verified publication marker. Never automatically delete the Vault, `.git`, uncommitted work, raw chat history or evidence without remote readback.

### Accidental deletion or corruption

Restore into a new staging directory first:

```powershell
.\Restore-WorkSystem.ps1 -Repository "rclone:work-drive:Work System/00 Recovery/restic-foundation"
```

Compare and validate before using `-Apply`. Never overwrite the live environment directly from an unverified snapshot.

## Client adaptation checklist

1. Create the client's canonical Drive root and direction/project hierarchy.
2. Define the central tracker schema and ID rules.
3. Define the Obsidian information architecture, access levels and current-state notes.
4. Inventory portable source directories and exclude caches, dependencies and bulk source datasets.
5. Create reconstructable chat-capture rules and a chat/project manifest.
6. Assign backup-account owner, passphrase custodian, restore tester and approval owner.
7. Run the first snapshot and clean-directory restore.
8. Run a clean-machine drill before claiming production readiness.
9. Record every deployment version, test result and exception in tracker Activity and Files.

## Acceptance criteria

- The latest snapshot is no more than 30 hours old.
- At least three historical snapshots exist after the initial operating period.
- `restic check` passes.
- A clean-directory restore contains every required operating note and a non-empty chat manifest.
- A replacement machine can restore the Vault and continue one selected task from its last checkpoint.
- Google-native documents remain linked by stable Drive ID.
- Source code is recoverable from Git.
- No secret is present in Git, Obsidian, the tracker or the public framework release.
