# Restore Dev Environment Playbook

How to rebuild the dev environment on a new or wiped machine from a
`backup-dev` backup. A copy of this file and `restore-dev.ps1` is kept inside
the backup itself (`<backup>\restore\`) because the repo is not available yet
on a rebuilt machine.

## What the backup contains

| Folder | Contents |
|---|---|
| `files\dev\` | Allowlisted files and folders from the dev root (non-repo folders, gitignored config, repos with no remote) |
| `files\home\` | Allowlisted files from the user profile (for example SSH, GPG and Git config) |
| `manifests\` | Package lists: scoop, winget, npm globals, pip, VS Code extensions, PowerShell modules, .NET SDKs, and `repos.json` (Git remotes) |
| `wip\` | Unpushed work for repos that have a remote: `uncommitted.patch`, `untracked\`, `unpushed.bundle`, `info.txt` per repo |
| `weekly\` | Dated zips (`dev-YYYY-MM-DD.zip`) of `files\` and `manifests\` for point-in-time recovery |
| `restore\` | This playbook and `restore-dev.ps1` |

Code that lives in a Git remote is **not** in the backup. It is re-cloned from
`repos.json` during restore.

## Before you start

1. A signed-in cloud-drive app (or any way to get the backup folder onto the
   machine). Let the backup folder finish syncing, or copy it locally.
2. Your password manager, for logins and any recovery keys.
3. Admin rights for installing Git and winget packages.

## Restore steps

1. **Get the backup folder** onto the machine and note its path, called
   `<backup>` below.
2. **Install Git and PowerShell 7** if missing:

   ```powershell
   winget install Git.Git Microsoft.PowerShell
   ```

3. **Preview the restore** (changes nothing):

   ```powershell
   pwsh -NoProfile -File "<backup>\restore\restore-dev.ps1" -BackupPath "<backup>" -WhatIf
   ```

4. **Run it for real.** Restored dev files never overwrite files that already
   exist, so freshly cloned repos stay exactly as on the remote and only missing
   files (gitignored config, non-repo folders) are added. Add `-OverwriteExisting`
   only to recover work that was never pushed. Use `-DevRoot` if the dev folder is not at the default
   `C:\dev`, and `-ScoopRoot` if scoop should install somewhere
   other than the default.

   ```powershell
   pwsh -NoProfile -File "<backup>\restore\restore-dev.ps1" -BackupPath "<backup>"
   ```

   The script runs, in order: repo clones, files (laid over the clones, so gitignored config lands inside them), then packages. Each step can be
   skipped with `-SkipFiles`, `-SkipPackages` or `-SkipRepos`. A failure in one
   package is reported and the script carries on.

5. **Recover unpushed work.** If the script lists entries under `wip\`, apply them inside the freshly cloned repo: `git fetch <bundle> <branch>:<branch>` for commits, `git apply uncommitted.patch` for changes, and copy `untracked\` back in.
6. **Complete the manual steps** the script prints at the end:
   - Import the GPG signing key, then run `gpg-connect-agent reloadagent /bye`.
   - Check Git signing: `git config --get gpg.program` and
     `git config --get user.signingkey`.
   - Sign in to the CLIs you use (`gh auth login`, `aws sso login`, and so on).
   - Re-apply app settings that are not backed up (editor sync, browser profiles).

7. **Verify.** Open the restored console project and run `console.ps1 --version`,
   run `git status` in a restored repo, and spot-check that restored
   config files are present.

## Recovering a deleted or overwritten file

The mirror propagates deletions, so recover from a weekly zip:

1. Pick a zip in `<backup>\weekly\` from before the loss.
2. Extract it to an empty folder:

   ```powershell
   Expand-Archive "<backup>\weekly\dev-YYYY-MM-DD.zip" -DestinationPath "<empty-folder>"
   ```

3. Copy the item you need from `<empty-folder>\files\...`, or restore everything
   by passing `-BackupPath "<empty-folder>"` to `restore-dev.ps1`.

Cloud drives also keep recent file versions and a trash for a limited time.

## Refreshing the backup

- Full backup: the console menu, "Backup Dev Environment", then "Full Backup",
  or `pwsh -NoProfile -File modules\backup-dev\backup-dev.ps1`.
- Preview: add `--dry-run`. Inventory: add `--count`.
- Manifests only: `--manifests-only`.

## Quarterly restore test

Restore into an empty folder to prove the backup works:

```powershell
pwsh -NoProfile -File "<backup>\restore\restore-dev.ps1" -BackupPath "<backup>" `
  -DevRoot "$env:TEMP\restore-test" -SkipPackages -SkipRepos
```

(That run also copies `files\home\` into the real user profile, so test with
`-WhatIf`, or use a throwaway VM, to avoid overwriting current settings. `/XO`
protects files that are newer than the backup.)

Record the date of each successful test in `TODO.md` or your own notes.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| "Destination parent not found" when backing up | The cloud drive is not mounted. Start the drive app and check `paths.backupDestination` in `config.json`. |
| An item is skipped with "source empty, destination not" | Safety check: the source folder has no files but the mirror does. Check the source, then delete the mirror folder if the emptiness is intentional. |
| winget import skips packages | Packages with no source (store apps, retired packages) cannot be reinstalled automatically. Install them by hand. |
| `Compress-Archive` fails on the weekly zip | A file is locked or a path is too long. See `backup-dev.log`, close the program holding the file, and re-run with `--zip`. |
