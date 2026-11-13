# Backup-Dev Module

Allowlist-based backup of the dev environment to a cloud-synced folder, with
package manifests and a weekly recovery zip. Added in v1.23.0, replacing the
old whole-folder robocopy backup.

## Table of Contents

- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Configuration](#configuration)
- [The allowlist](#the-allowlist)
- [Usage](#usage)
- [Backup layout](#backup-layout)
- [Restoring](#restoring)
- [Safety checks](#safety-checks)
- [Files in this module](#files-in-this-module)

## How it works

Backing up everything under the dev root is wasteful: most of it is code that
already lives in a Git remote, or regenerable data (`node_modules`, VHDs).
This module backs up only what Git does not protect:

1. Folders that are not Git repositories.
2. Gitignored local files (config, secrets, local state) inside repos that do
   have a remote.
3. Repos that have no remote yet (including their `.git` folder).
4. Machine configuration under the user profile.

Each run:

1. **Mirrors** the allowlisted paths with `robocopy /MIR` to
   `<destination>\files\`.
2. **Writes package manifests** (scoop, winget, npm globals, pip, VS Code
   extensions, PowerShell modules, .NET SDKs, Git repo list) to
   `<destination>\manifests\`.
3. **Saves unpushed work** for repos that have a remote: uncommitted changes
   (`uncommitted.patch`, plus small untracked files) and unpushed commits
   (`unpushed.bundle`) go to `<destination>\wip\`. Remotes matching
   `backupDev.wip.excludeRemotePatterns` are skipped (use it for an employer's org).
4. **Copies the restore playbook** to `<destination>\restore\`.
5. **Creates a weekly zip** of `files\` and `manifests\` in
   `<destination>\weekly\` when the newest one is older than
   `intervalDays`, keeping the newest `keep` zips.

The mirror propagates deletions, so the weekly zips are what allow recovering
an accidentally deleted or overwritten item.

## Requirements

- PowerShell 7+
- `robocopy` (built into Windows)
- A destination folder whose parent already exists, normally a cloud-drive
  folder. The script refuses to run if the parent is missing, so an unmounted
  drive never creates a stray local folder.
- Optional tools used for manifests (each is skipped if absent): `scoop`,
  `winget`, `npm`, `pip`, `code`, `dotnet`, `git`

## Configuration

`config.json` (see `config.example.json`):

```json
{
  "paths": {
    "devRoot": "C:\\path\\to\\dev",
    "backupDestination": "C:\\path\\to\\cloud-drive\\DevBackup"
  },
  "backupDev": {
    "includesFile": "backup-includes.txt",
    "weeklyZip": { "enabled": true, "intervalDays": 7, "keep": 8 },
    "excludeDirectories": ["node_modules", ".terraform", ".venv"],
    "excludeFiles": ["*.vhdx", "*.vsix"]
  }
}
```

| Setting | Meaning |
|---|---|
| `paths.devRoot` | Root of the dev folder. The `%DEV%` token in the allowlist |
| `paths.backupDestination` | Absolute path, or a path relative to the user profile |
| `backupDev.includesFile` | Allowlist file, relative to this module folder |
| `backupDev.wip.*` | Unpushed-work capture on/off, max untracked file size (MB), remote patterns to skip |
| `backupDev.weeklyZip.*` | Zip on/off, minimum days between zips, zips to keep |
| `backupDev.excludeDirectories` | Directory names skipped inside every mirrored folder |
| `backupDev.excludeFiles` | File patterns skipped inside every mirrored folder |

## The allowlist

`backup-includes.txt` is **local only and gitignored**, because it names your
own folders. Start from the tracked template:

```powershell
Copy-Item backup-includes.example.txt backup-includes.txt
```

Syntax, one entry per line:

| Entry | Meaning |
|---|---|
| `%DEV%\path` | File or folder under `paths.devRoot` |
| `%HOME%\path` | File or folder under the user profile |
| `!<path>` | Exclude a sub-path of an include above |
| `# text` | Comment |

Folders are mirrored (`/MIR`). Single files are copied without touching their
siblings.

## Usage

From the console: main menu, "Backup Dev Environment", which offers dry run,
count, full backup, refresh manifests, restore preview (WhatIf), and log viewers.

From a shell:

```powershell
pwsh -NoProfile -File modules\backup-dev\backup-dev.ps1 --dry-run
```

| Option | Effect |
|---|---|
| (none) | Full backup: mirror, manifests, weekly zip if due |
| `--dry-run` | Show per-item files to copy and delete; write nothing |
| `--count` | Show inventory of what the allowlist covers; write nothing |
| `--manifests-only` | Refresh the package manifests only |
| `--zip` | Force a weekly zip even if one is recent |
| `--no-zip` | Skip the weekly zip |
| `--help` | Show usage |

Exit codes: `0` success, `1` configuration or environment error, `2` completed
with failed or skipped items.

## Backup layout

```text
<destination>\
  files\dev\...      mirrored items from the dev root
  files\home\...     mirrored items from the user profile
  manifests\         scoop.json, winget.json, npm-global.json, pip.txt,
                     vscode-extensions.txt, psmodules.json, dotnet-sdks.txt,
                     repos.json, generated.txt
  wip\               per-repo unpushed work (patch, untracked files, bundle)
  weekly\            dev-YYYY-MM-DD.zip (newest N kept)
  restore\           restore-dev.md and restore-dev.ps1
```

## Restoring

See [restore-dev.md](restore-dev.md). The short version:

```powershell
pwsh -NoProfile -File "<backup>\restore\restore-dev.ps1" -BackupPath "<backup>" -WhatIf
```

## Safety checks

- The destination's parent folder must exist.
- A list-only pass runs before every mirror. If a source folder has no files
  but its mirror does, that item is skipped rather than purged.
- The weekly zip is built in the temp folder and moved into place, so a
  cloud-sync client never uploads a half-written zip.
- Locked sockets and lock files (for example GPG agent sockets) are excluded.
- A backup is only off-site once the cloud-drive app reports it as synced; the
  script warns if the drive app is not running.

## Files in this module

| File | Purpose |
|---|---|
| `backup-dev.ps1` | Backup script |
| `backup-includes.example.txt` | Allowlist template (tracked) |
| `backup-includes.txt` | Your allowlist (gitignored) |
| `restore-dev.ps1` | Restore script |
| `restore-dev.md` | Restore playbook |
| `backup-dev.log`, `backup-history.log` | Detailed log and last 10 runs (gitignored) |
