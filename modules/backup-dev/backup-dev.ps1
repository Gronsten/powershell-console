#Requires -Version 7.0
<#
.SYNOPSIS
    Allowlist-based backup of the dev environment to a cloud-synced folder.

.DESCRIPTION
    Replaces the old whole-dev-folder robocopy approach (v1.x) with a
    small, allowlisted backup:

      1. Mirrors only the paths listed in backup-includes.txt (robocopy /MIR) to
         <destination>\files\dev\... and <destination>\files\home\...
      2. Writes package-manager manifests (scoop, winget, npm, pip, VS Code,
         PowerShell modules, dotnet, Git repo list) to <destination>\manifests\
      3. Creates a weekly dated zip of files + manifests in <destination>\weekly\
         so accidentally deleted or overwritten items can be recovered (the
         mirror itself propagates deletions).

    Code that already lives in a Git remote is NOT backed up; the allowlist covers
    only what Git does not: non-repo folders, gitignored config/secrets, and
    repos that have no remote yet. See restore-dev.md for the restore playbook.

    The allowlist (backup-includes.txt) is local-only and gitignored because it
    names personal folders. backup-includes.example.txt documents the syntax.

.NOTES
    Options (GNU style, kept for console.ps1 compatibility):
      --dry-run          List what would be copied/deleted; write nothing
      --count            Show the inventory of what the allowlist covers; write nothing
      --manifests-only   Refresh package manifests only
      --zip              Force a weekly zip even if one was made in the last 7 days
      --no-zip           Skip the weekly zip
      --help             Show usage
#>

$dryRun = $false
$countOnly = $false
$manifestsOnly = $false
$forceZip = $false
$noZip = $false

function Show-Usage {
    Write-Host "Usage: backup-dev.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  --dry-run         List what would be copied/deleted (writes nothing)"
    Write-Host "  --count           Show inventory of what the allowlist covers (writes nothing)"
    Write-Host "  --manifests-only  Refresh package manifests only"
    Write-Host "  --zip             Force a weekly zip even if one is recent"
    Write-Host "  --no-zip          Skip the weekly zip"
    Write-Host "  --help            Show this help message"
    Write-Host ""
    Write-Host "With no options a full backup runs: mirror + manifests + weekly zip (if due)."
}

foreach ($arg in $args) {
    switch ($arg) {
        "--dry-run"        { $dryRun = $true }
        "--count"          { $countOnly = $true }
        "--manifests-only" { $manifestsOnly = $true }
        "--zip"            { $forceZip = $true }
        "--no-zip"         { $noZip = $true }
        "--help"           { Show-Usage; exit 0 }
        default {
            Write-Error "Unknown option: $arg"
            Show-Usage
            exit 1
        }
    }
}

function Write-Separator {
    Write-Host "==============================================" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# $scriptDir = modules/backup-dev/ ; $rootDir = project root (holds config.json)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent (Split-Path -Parent $scriptDir)
$configPath = Join-Path $rootDir "config.json"

if (-not (Test-Path $configPath)) {
    Write-Error "Config file not found at: $configPath (create it from config.example.json)"
    exit 1
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json
$bd = if ($config.PSObject.Properties.Name -contains "backupDev") { $config.backupDev } else { $null }

# Helper: read an optional setting with a default
function Get-BackupSetting {
    param($Object, [string]$Name, $Default)
    if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name -and $null -ne $Object.$Name) {
        return $Object.$Name
    }
    return $Default
}

$devRoot = ([string]$config.paths.devRoot).TrimEnd('\')
$homeDir = $env:USERPROFILE.TrimEnd('\')

# Destination may be absolute (e.g. a cloud-drive folder) or relative to the user profile
$destRaw = [string]$config.paths.backupDestination
$destination = if ([System.IO.Path]::IsPathRooted($destRaw)) { $destRaw } else { Join-Path $env:USERPROFILE $destRaw }
$destination = $destination.TrimEnd('\')
$filesRoot = Join-Path $destination "files"
$manifestRoot = Join-Path $destination "manifests"
$weeklyRoot = Join-Path $destination "weekly"
$wipRoot = Join-Path $destination "wip"

$includesFile = Join-Path $scriptDir (Get-BackupSetting $bd "includesFile" "backup-includes.txt")
$zipEnabled = [bool](Get-BackupSetting (Get-BackupSetting $bd "weeklyZip" $null) "enabled" $true)
$zipKeep = [int](Get-BackupSetting (Get-BackupSetting $bd "weeklyZip" $null) "keep" 8)
$zipIntervalDays = [int](Get-BackupSetting (Get-BackupSetting $bd "weeklyZip" $null) "intervalDays" 7)

# Default excludes apply to every mirrored folder (regenerable or unsafe to copy)
$defaultExcludeDirs = @(Get-BackupSetting $bd "excludeDirectories" @(
        "node_modules", ".terraform", ".venv", "venv", "__pycache__", ".pytest_cache"))
$defaultExcludeFiles = @(Get-BackupSetting $bd "excludeFiles" @(
        "*.vhd", "*.vhdx", "*.vsix", "*.pyc", "*.pyo", "*.db.lock",
        "S.gpg-agent*", "S.dirmngr", "S.keyboxd", "S.scdaemon", "gnupg_spawn_agent_sentinel*"))

$detailedLog = Join-Path $scriptDir "backup-dev.log"
$summaryLog = Join-Path $scriptDir "backup-history.log"

# ---------------------------------------------------------------------------
# Allowlist parsing
# ---------------------------------------------------------------------------
function Resolve-BackupToken {
    param([string]$Text)
    return $Text.Replace('%DEV%', $devRoot).Replace('%HOME%', $homeDir)
}

# Map a source path to its location under <destination>\files
function Get-MirrorTarget {
    param([string]$FullPath)
    if ($FullPath.StartsWith("$devRoot\", [System.StringComparison]::OrdinalIgnoreCase)) {
        return Join-Path $filesRoot ("dev\" + $FullPath.Substring($devRoot.Length + 1))
    }
    if ($FullPath.StartsWith("$homeDir\", [System.StringComparison]::OrdinalIgnoreCase)) {
        return Join-Path $filesRoot ("home\" + $FullPath.Substring($homeDir.Length + 1))
    }
    return $null
}

function Get-BackupItems {
    if (-not (Test-Path $includesFile)) {
        Write-Host "Allowlist not found: $includesFile" -ForegroundColor Red
        Write-Host "Copy backup-includes.example.txt to backup-includes.txt and edit it." -ForegroundColor Yellow
        return $null
    }

    $includes = [System.Collections.Generic.List[string]]::new()
    $excludes = [System.Collections.Generic.List[string]]::new()
    foreach ($line in Get-Content $includesFile) {
        $text = $line.Trim()
        if ($text -eq "" -or $text.StartsWith("#")) { continue }
        if ($text.StartsWith("!")) {
            $excludes.Add((Resolve-BackupToken $text.Substring(1).Trim()).TrimEnd('\'))
        } else {
            $includes.Add((Resolve-BackupToken $text).TrimEnd('\'))
        }
    }

    $items = @()
    foreach ($src in $includes) {
        $target = Get-MirrorTarget $src
        if (-not $target) {
            Write-Host "  Skipping (not under DEV or HOME): $src" -ForegroundColor Yellow
            continue
        }
        if (-not (Test-Path -LiteralPath $src)) {
            Write-Host "  Skipping (not found): $src" -ForegroundColor Yellow
            continue
        }
        $isDir = (Get-Item -LiteralPath $src -Force).PSIsContainer
        # Excludes that fall inside this include
        $under = @($excludes | Where-Object { $_.StartsWith("$src\", [System.StringComparison]::OrdinalIgnoreCase) })
        $items += [pscustomobject]@{
            Source = $src
            Dest   = $target
            IsDir  = $isDir
            XDirs  = @($under | Where-Object { Test-Path -LiteralPath $_ -PathType Container })
            XFiles = @($under | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
        }
    }
    return $items
}

# ---------------------------------------------------------------------------
# Mirror (robocopy)
# ---------------------------------------------------------------------------
function Invoke-ItemMirror {
    param($Item, [switch]$ListOnly)

    if ($Item.IsDir) {
        $rcArgs = @($Item.Source, $Item.Dest, "/MIR", "/XD") + $defaultExcludeDirs + $Item.XDirs +
                  @("/XF") + $defaultExcludeFiles + $Item.XFiles
    } else {
        # Single file: copy only that file (no /MIR, so siblings are untouched)
        $rcArgs = @((Split-Path $Item.Source -Parent), (Split-Path $Item.Dest -Parent), (Split-Path $Item.Source -Leaf))
    }
    $rcArgs += @("/XJ", "/R:2", "/W:2", "/NP", "/BYTES", "/NDL", "/NJH")
    if ($ListOnly) { $rcArgs += "/L" }

    $out = & robocopy @rcArgs 2>&1
    $rc = $LASTEXITCODE
    $text = ($out | ForEach-Object { "$_" }) -join "`n"

    $files = @(0, 0, 0, 0, 0, 0)
    if ($text -match '(?m)^\s*Files\s*:\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)') {
        $files = 1..6 | ForEach-Object { [int64]$Matches[$_] }
    }
    $bytes = @(0, 0, 0, 0, 0, 0)
    if ($text -match '(?m)^\s*Bytes\s*:\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)') {
        $bytes = 1..6 | ForEach-Object { [int64]$Matches[$_] }
    }

    if (-not $ListOnly) { Add-Content -Path $detailedLog -Value "--- $($Item.Source)`n$text" }

    [pscustomobject]@{
        Name        = $Item.Source
        Total       = $files[0]
        Copied      = $files[1]
        Failed      = $files[4]
        Extras      = $files[5]
        Bytes       = $bytes[0]
        BytesCopied = $bytes[1]
        ExitCode    = $rc
        # robocopy exit codes of 8 or higher mean at least one failure
        HadError    = ($rc -ge 8)
        # Source has no files but destination does: refuse to purge it with /MIR
        EmptySource = ($Item.IsDir -and $files[0] -eq 0 -and $files[5] -gt 0)
    }
}

# ---------------------------------------------------------------------------
# Package manifests
# ---------------------------------------------------------------------------
function Test-Tool { param([string]$Name) return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

function Export-PackageManifests {
    param([string]$OutDir)

    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    $results = [ordered]@{}

    # Each exporter is isolated so one missing tool never blocks the rest
    $exporters = [ordered]@{
        "scoop.json" = { if (Test-Tool scoop) { scoop export 2>$null } }
        "npm-global.json" = { if (Test-Tool npm) { npm ls -g --depth=0 --json 2>$null } }
        "pip.txt" = { if (Test-Tool pip) { pip freeze 2>$null } }
        "vscode-extensions.txt" = { if (Test-Tool code) { code --list-extensions --show-versions 2>$null } }
        "dotnet-sdks.txt" = { if (Test-Tool dotnet) { dotnet --list-sdks 2>$null } }
        "psmodules.json" = {
            Get-InstalledModule -ErrorAction SilentlyContinue |
                Select-Object Name, Version, Repository | ConvertTo-Json
        }
    }
    foreach ($name in $exporters.Keys) {
        try {
            $content = & $exporters[$name]
            if ($content) {
                Set-Content -Path (Join-Path $OutDir $name) -Value $content -Encoding utf8
                $results[$name] = "ok"
            } else {
                $results[$name] = "skipped (tool missing or empty)"
            }
        } catch {
            $results[$name] = "failed: $($_.Exception.Message)"
        }
    }

    # winget writes its own file; it exits non-zero when some packages have no source
    if (Test-Tool winget) {
        $wingetFile = Join-Path $OutDir "winget.json"
        $null = winget export -o $wingetFile --accept-source-agreements --disable-interactivity 2>&1
        $results["winget.json"] = if (Test-Path $wingetFile) { "ok" } else { "failed" }
    } else {
        $results["winget.json"] = "skipped (tool missing)"
    }

    # Git repo list (relative to devRoot) so restore can re-clone code that lives on a remote
    try {
        $repos = Get-ChildItem -Path $devRoot -Directory -Recurse -Depth 2 -Force -Filter ".git" -ErrorAction SilentlyContinue |
            ForEach-Object {
                $repoDir = $_.Parent.FullName
                [pscustomobject]@{
                    path   = $repoDir.Substring($devRoot.Length).TrimStart('\')
                    remote = (git -C $repoDir remote get-url origin 2>$null)
                    branch = (git -C $repoDir branch --show-current 2>$null)
                }
            }
        $script:RepoList = @($repos)
        $repos | ConvertTo-Json | Set-Content -Path (Join-Path $OutDir "repos.json") -Encoding utf8
        $results["repos.json"] = "ok ($(@($repos).Count) repos)"
    } catch {
        $results["repos.json"] = "failed: $($_.Exception.Message)"
    }

    Set-Content -Path (Join-Path $OutDir "generated.txt") -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Encoding utf8
    return $results
}

# ---------------------------------------------------------------------------
# Unpushed work (WIP) snapshots
# ---------------------------------------------------------------------------
# Repos that have a remote are not mirrored, so uncommitted changes and unpushed
# commits would be lost with the machine. For each such repo that has either, save:
#   uncommitted.patch  tracked changes (git apply)
#   untracked\         untracked, non-ignored files (small ones)
#   unpushed.bundle    commits not on any remote (git fetch/pull from the bundle)
#   info.txt           remote, branch and counts
# Remotes matching backupDev.wip.excludeRemotePatterns are skipped (for example an
# employer's org, whose code must not be copied to personal storage).
function Export-WipSnapshots {
    param([string]$OutDir)

    $wip = Get-BackupSetting $bd "wip" $null
    if (-not [bool](Get-BackupSetting $wip "enabled" $true)) { return "disabled" }
    $skipPatterns = @(Get-BackupSetting $wip "excludeRemotePatterns" @())
    $maxUntrackedBytes = [int64](Get-BackupSetting $wip "maxUntrackedFileMB" 5) * 1MB

    if (Test-Path -LiteralPath $OutDir) { Remove-Item -LiteralPath $OutDir -Recurse -Force }

    $saved = 0
    $skipped = 0
    foreach ($repo in @($script:RepoList)) {
        if (-not $repo.remote) { continue }   # no remote: already mirrored in full
        if (@($skipPatterns | Where-Object { $_ -and $repo.remote -like "*$_*" }).Count -gt 0) { $skipped++; continue }

        $dir = Join-Path $devRoot $repo.path
        $dirty = @(git -C $dir status --porcelain 2>$null)
        $unpushed = @(git -C $dir log --branches --not --remotes --oneline 2>$null)
        if ($dirty.Count -eq 0 -and $unpushed.Count -eq 0) { continue }

        $target = Join-Path $OutDir ($repo.path -replace '[\\/]', '__')
        New-Item -ItemType Directory -Path $target -Force | Out-Null

        if ($dirty.Count -gt 0) {
            # --output writes the bytes directly (no PowerShell pipeline re-encoding)
            git -C $dir diff HEAD --binary --output="$(Join-Path $target 'uncommitted.patch')" 2>$null
            foreach ($rel in @(git -C $dir ls-files --others --exclude-standard 2>$null)) {
                $srcFile = Join-Path $dir $rel
                if ((Test-Path -LiteralPath $srcFile -PathType Leaf) -and (Get-Item -LiteralPath $srcFile).Length -le $maxUntrackedBytes) {
                    $dst = Join-Path (Join-Path $target "untracked") $rel
                    New-Item -ItemType Directory -Path (Split-Path $dst -Parent) -Force | Out-Null
                    Copy-Item -LiteralPath $srcFile -Destination $dst -Force
                }
            }
        }
        if ($unpushed.Count -gt 0) {
            git -C $dir bundle create (Join-Path $target "unpushed.bundle") --branches --not --remotes 2>$null | Out-Null
        }
        @(
            "path:      $($repo.path)",
            "remote:    $($repo.remote)",
            "branch:    $($repo.branch)",
            "changed:   $($dirty.Count) file(s) with uncommitted changes",
            "unpushed:  $($unpushed.Count) commit(s) not on any remote",
            "captured:  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        ) | Set-Content -Path (Join-Path $target "info.txt") -Encoding utf8
        $saved++
    }
    return "$saved repo(s) with unpushed work saved, $skipped skipped by remote pattern"
}

# ---------------------------------------------------------------------------
# Weekly zip
# ---------------------------------------------------------------------------
function Get-ZipDecision {
    if ($noZip -or -not $zipEnabled) { return "disabled" }
    if ($forceZip) { return "due" }
    $latest = Get-ChildItem -Path $weeklyRoot -Filter "dev-*.zip" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest -and ((Get-Date) - $latest.LastWriteTime).TotalDays -lt $zipIntervalDays) { return "recent" }
    return "due"
}

function New-WeeklyZip {
    New-Item -ItemType Directory -Path $weeklyRoot -Force | Out-Null
    $stamp = Get-Date -Format "yyyy-MM-dd"
    $zipName = "dev-$stamp.zip"
    # Build in TEMP first so the cloud-sync client never uploads a half-written zip
    $tmpZip = Join-Path $env:TEMP $zipName
    Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
    $zipSources = @($filesRoot, $manifestRoot)
    if (Test-Path -LiteralPath $wipRoot) { $zipSources += $wipRoot }
    Compress-Archive -Path $zipSources -DestinationPath $tmpZip -CompressionLevel Optimal
    Move-Item -Path $tmpZip -Destination (Join-Path $weeklyRoot $zipName) -Force

    # Rotate: keep the newest N zips
    Get-ChildItem -Path $weeklyRoot -Filter "dev-*.zip" -File | Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $zipKeep | Remove-Item -Force
    return $zipName
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
$scriptStart = Get-Date
$timestamp = $scriptStart.ToString("yyyy-MM-dd HH:mm:ss")
$mode = if ($countOnly) { "COUNT" } elseif ($dryRun) { "DRY-RUN" } elseif ($manifestsOnly) { "MANIFESTS" } else { "FULL" }

Write-Host ""
Write-Separator
Write-Host "  DEV BACKUP - $mode" -ForegroundColor Cyan
Write-Host "  Destination: $destination" -ForegroundColor Gray
Write-Separator
Write-Host ""

# The cloud-drive parent must exist (guards against an unmounted drive creating a stray local folder)
$destParent = Split-Path $destination -Parent
if (-not $destParent -or -not (Test-Path $destParent)) {
    Write-Host "Destination parent not found: $destParent" -ForegroundColor Red
    Write-Host "Is the cloud drive mounted? Check config.json paths.backupDestination." -ForegroundColor Yellow
    exit 1
}
if (-not $devRoot -or -not (Test-Path $devRoot)) {
    Write-Host "paths.devRoot is not set or does not exist in config.json: '$devRoot'" -ForegroundColor Red
    exit 1
}

# Manifests-only shortcut
if ($manifestsOnly) {
    $res = Export-PackageManifests -OutDir $manifestRoot
    $res.GetEnumerator() | ForEach-Object { Write-Host ("  {0,-24} {1}" -f $_.Key, $_.Value) -ForegroundColor Gray }
    Write-Host ""
    Write-Host "Manifests written to: $manifestRoot" -ForegroundColor Green
    exit 0
}

$items = Get-BackupItems
if ($null -eq $items) { exit 1 }
if ($items.Count -eq 0) { Write-Host "Allowlist is empty; nothing to back up." -ForegroundColor Yellow; exit 1 }

# Pass 1: list-only (also the safety check before any /MIR)
Write-Host "Scanning $($items.Count) allowlisted items..." -ForegroundColor Cyan
$plan = foreach ($item in $items) { Invoke-ItemMirror -Item $item -ListOnly }

Write-Host ""
Write-Host ("  {0,-62} {1,7} {2,7} {3,7} {4,9}" -f "Item", "Files", "To copy", "Delete", "MB") -ForegroundColor White
foreach ($p in $plan) {
    $label = $p.Name.Replace($devRoot, "%DEV%").Replace($homeDir, "%HOME%")
    if ($label.Length -gt 62) { $label = "..." + $label.Substring($label.Length - 59) }
    $color = if ($p.HadError -or $p.EmptySource) { "Red" } elseif ($p.Copied -gt 0 -or $p.Extras -gt 0) { "Yellow" } else { "Gray" }
    Write-Host ("  {0,-62} {1,7:N0} {2,7:N0} {3,7:N0} {4,9:N1}" -f $label, $p.Total, $p.Copied, $p.Extras, ($p.Bytes / 1MB)) -ForegroundColor $color
}
$totFiles = ($plan | Measure-Object Total -Sum).Sum
$totCopy = ($plan | Measure-Object Copied -Sum).Sum
$totExtra = ($plan | Measure-Object Extras -Sum).Sum
$totMB = (($plan | Measure-Object Bytes -Sum).Sum) / 1MB
Write-Host ("  {0,-62} {1,7:N0} {2,7:N0} {3,7:N0} {4,9:N1}" -f "TOTAL", $totFiles, $totCopy, $totExtra, $totMB) -ForegroundColor Cyan
Write-Host ""

if ($countOnly) { exit 0 }

$zipDecision = Get-ZipDecision
if ($dryRun) {
    Write-Host "Dry run: nothing was written." -ForegroundColor Cyan
    Write-Host "  Manifests that would be refreshed: $manifestRoot" -ForegroundColor Gray
    Write-Host "  Weekly zip: $zipDecision" -ForegroundColor Gray
    $bad = @($plan | Where-Object { $_.EmptySource -or $_.HadError })
    if ($bad.Count -gt 0) { Write-Host "  $($bad.Count) item(s) would be skipped or fail (red above)." -ForegroundColor Red }
    exit 0
}

# Pass 2: real mirror
New-Item -ItemType Directory -Path $destination -Force | Out-Null
Set-Content -Path $detailedLog -Value "=== Backup started: $timestamp | Mode: $mode ==="
Write-Host "Mirroring..." -ForegroundColor Cyan
$failures = 0
$skipped = 0
$copied = 0
$removed = 0
for ($i = 0; $i -lt $items.Count; $i++) {
    if ($plan[$i].EmptySource) {
        Write-Host "  SKIPPED (source empty, destination not): $($items[$i].Source)" -ForegroundColor Red
        $skipped++
        continue
    }
    $r = Invoke-ItemMirror -Item $items[$i]
    $copied += $r.Copied
    $removed += $r.Extras
    if ($r.HadError -or $r.Failed -gt 0) {
        $failures++
        Write-Host "  FAILED (robocopy exit $($r.ExitCode)): $($items[$i].Source)" -ForegroundColor Red
    }
}
Write-Host "  Files copied: $copied | Removed from mirror: $removed | Failed items: $failures | Skipped: $skipped" -ForegroundColor Green

Write-Host ""
Write-Host "Writing package manifests..." -ForegroundColor Cyan
$manifestResults = Export-PackageManifests -OutDir $manifestRoot
$manifestResults.GetEnumerator() | ForEach-Object { Write-Host ("  {0,-24} {1}" -f $_.Key, $_.Value) -ForegroundColor Gray }

Write-Host ""
Write-Host "Capturing unpushed work..." -ForegroundColor Cyan
$wipResult = Export-WipSnapshots -OutDir $wipRoot
Write-Host "  $wipResult" -ForegroundColor Gray

# Keep a copy of the restore playbook next to the data: on a rebuilt machine the
# repo is not cloned yet, so the instructions must travel with the backup.
$restoreDir = Join-Path $destination "restore"
New-Item -ItemType Directory -Path $restoreDir -Force | Out-Null
foreach ($name in "restore-dev.md", "restore-dev.ps1") {
    $src = Join-Path $scriptDir $name
    if (Test-Path $src) { Copy-Item -Path $src -Destination $restoreDir -Force }
}

$zipResult = "not due ($zipDecision)"
if ($zipDecision -eq "due") {
    Write-Host ""
    Write-Host "Creating weekly zip..." -ForegroundColor Cyan
    try {
        $zipResult = New-WeeklyZip
        Write-Host "  $zipResult" -ForegroundColor Green
    } catch {
        $zipResult = "failed: $($_.Exception.Message)"
        Write-Host "  Zip failed: $($_.Exception.Message)" -ForegroundColor Red
        $failures++
    }
}

# History log (newest first, last 10 kept; header format is parsed by console.ps1)
$endTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add-Content -Path $detailedLog -Value "`n=== Backup completed: $endTime ==="
$entry = "=== Backup: $timestamp | Mode: $mode ===`n" +
         "Items: $($items.Count) | Copied: $copied | Removed: $removed | Failed: $failures | Skipped: $skipped | WIP: $wipResult | Zip: $zipResult`n" +
         "=== Backup completed: $endTime ==="
$existing = if (Test-Path $summaryLog) { Get-Content $summaryLog -Raw } else { "" }
$entries = @($entry) + @(($existing -split '(?:\r?\n){2,}') | Where-Object { $_.Trim() -ne "" })
Set-Content -Path $summaryLog -Value (($entries | Select-Object -First 10) -join "`n`n")

Write-Host ""
if (-not (Get-Process GoogleDriveFS -ErrorAction SilentlyContinue)) {
    Write-Host "Note: the Google Drive app is not running, so nothing is uploading yet." -ForegroundColor Yellow
} else {
    Write-Host "Local copy complete. The Drive app uploads in the background; the backup is off-site once it reports 'synced'." -ForegroundColor Gray
}
if ($failures -gt 0 -or $skipped -gt 0) {
    Write-Host "Completed with problems; see $detailedLog" -ForegroundColor Red
    exit 2
}
Write-Host "Backup complete in $(((Get-Date) - $scriptStart).ToString('mm\:ss'))." -ForegroundColor Green
exit 0
