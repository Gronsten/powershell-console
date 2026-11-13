#Requires -Version 7.0
<#
.SYNOPSIS
    Rebuilds a dev environment from a backup-dev backup (see restore-dev.md).

.DESCRIPTION
    Runs these steps in order, each optional:
      1. Files     - copy <BackupPath>\files\dev -> DevRoot and files\home -> user profile
      2. Packages  - install scoop, winget, npm, pip, VS Code and PowerShell packages
                     from <BackupPath>\manifests
      3. Repos     - re-clone Git repositories listed in manifests\repos.json that
                     are not already present
    Then prints the manual steps that cannot be automated (GPG, sign-ins).

    Use -WhatIf first: it shows every step without changing anything.

.PARAMETER BackupPath
    The backup folder (the one containing files\, manifests\ and weekly\).
    To restore from a weekly zip instead, extract it and point this at the
    extracted folder (it contains files\ and manifests\).

.PARAMETER DevRoot
    Where the dev folder is restored. Defaults to C:\dev.

.PARAMETER OverwriteExisting
    By default restored dev files never overwrite files already on disk, so freshly
    cloned repos stay exactly as on the remote and only missing (gitignored or
    non-repo) files are added. Pass this to let the backup copy win, for example to
    recover work that was never pushed.

.PARAMETER ScoopRoot
    Scoop install location (sets SCOOP for the session) if scoop must be installed.

.EXAMPLE
    .\restore-dev.ps1 -BackupPath "D:\path\to\DevBackup" -WhatIf

.EXAMPLE
    .\restore-dev.ps1 -BackupPath "D:\path\to\DevBackup" -SkipRepos
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$BackupPath,
    [string]$DevRoot = "C:\dev",
    [string]$ScoopRoot,
    [switch]$OverwriteExisting,
    [switch]$SkipFiles,
    [switch]$SkipPackages,
    [switch]$SkipRepos
)

$ErrorActionPreference = "Stop"
$filesDir = Join-Path $BackupPath "files"
$manifestDir = Join-Path $BackupPath "manifests"

function Write-Step { param([string]$Text) Write-Host "`n== $Text" -ForegroundColor Cyan }
function Test-Tool { param([string]$Name) return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

# Run a command only when not in -WhatIf; failures are reported but do not stop later steps
function Invoke-RestoreAction {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Description, [scriptblock]$Action)
    if ($PSCmdlet.ShouldProcess($Description)) {
        try { & $Action } catch { Write-Warning "$Description failed: $($_.Exception.Message)" }
    }
}

# --- Preflight ---------------------------------------------------------------
Write-Step "Preflight"
if (-not (Test-Path $filesDir) -and -not (Test-Path $manifestDir)) {
    throw "No files\ or manifests\ under '$BackupPath'. Point -BackupPath at the DevBackup folder (or an extracted weekly zip)."
}
foreach ($tool in "git", "robocopy") {
    $state = if (Test-Tool $tool) { "found" } else { "MISSING" }
    Write-Host ("  {0,-10} {1}" -f $tool, $state)
}
if (-not (Test-Tool git)) { Write-Warning "git is missing: install it first (winget install Git.Git), then re-run for repo cloning." }

# --- 1. Repositories (cloned first so restored files overlay them) ----------
if (-not $SkipRepos) {
    Write-Step "Re-cloning Git repositories"
    $reposJson = Join-Path $manifestDir "repos.json"
    if ((Test-Path $reposJson) -and (Test-Tool git)) {
        foreach ($repo in @(Get-Content $reposJson -Raw | ConvertFrom-Json)) {
            $target = Join-Path $DevRoot $repo.path
            if (Test-Path (Join-Path $target ".git")) {
                Write-Host "  present: $($repo.path)" -ForegroundColor DarkGray
            } elseif (-not $repo.remote) {
                Write-Host "  no remote: $($repo.path) (restored from the files backup)" -ForegroundColor DarkGray
            } else {
                Invoke-RestoreAction "git clone $($repo.remote) -> $($repo.path)" {
                    git clone $repo.remote $target
                    if ($repo.branch) { git -C $target checkout $repo.branch 2>$null }
                }
            }
        }
    } else {
        Write-Host "  (no repos.json or git missing)" -ForegroundColor DarkGray
    }
}

# --- 2. Files ----------------------------------------------------------------
if (-not $SkipFiles) {
    Write-Step "Restoring files"
    # /E copies subfolders.
    # Dev files: by default only ADD files that are missing (/XC /XN /XO skip any file that
    # already exists), so a fresh clone from the remote is never overwritten by an older
    # backup copy; only gitignored and non-repo files are filled in. -OverwriteExisting
    # lets the backup win (use it to recover work that was never pushed).
    # Home files: /XO only protects files newer than the backup.
    $devFlags = if ($OverwriteExisting) { @() } else { @("/XC", "/XN", "/XO") }
    $maps = @(
        @{ From = (Join-Path $filesDir "dev");  To = $DevRoot;         Flags = $devFlags },
        @{ From = (Join-Path $filesDir "home"); To = $env:USERPROFILE; Flags = @("/XO") }
    )
    foreach ($m in $maps) {
        if (-not (Test-Path $m.From)) { Write-Host "  (nothing at $($m.From))" -ForegroundColor DarkGray; continue }
        # Typed array: a bare one-element result would unroll to a string and splat as characters
        [string[]]$listOnly = if ($WhatIfPreference) { "/L" } else { @() }
        Write-Host "  $($m.From) -> $($m.To)"
        $null = robocopy $m.From $m.To /E @($m.Flags) /XJ /R:2 /W:2 /NP /NDL /NJH @listOnly
        if ($LASTEXITCODE -ge 8) { Write-Warning "robocopy reported errors (exit $LASTEXITCODE) for $($m.From)" }
    }
}

# --- 3. Packages -------------------------------------------------------------
if (-not $SkipPackages) {
    Write-Step "Installing packages from manifests"

    # scoop
    $scoopJson = Join-Path $manifestDir "scoop.json"
    if (Test-Path $scoopJson) {
        if (-not (Test-Tool scoop)) {
            Invoke-RestoreAction "Install scoop" {
                if ($ScoopRoot) { $env:SCOOP = $ScoopRoot; [Environment]::SetEnvironmentVariable("SCOOP", $ScoopRoot, "User") }
                Invoke-RestMethod https://get.scoop.sh | Invoke-Expression
            }
        }
        Invoke-RestoreAction "scoop import (apps, buckets, versions)" { scoop import $scoopJson }
    }

    # winget (packages with no source are skipped)
    $wingetJson = Join-Path $manifestDir "winget.json"
    if ((Test-Path $wingetJson) -and (Test-Tool winget)) {
        Invoke-RestoreAction "winget import" {
            winget import -i $wingetJson --accept-package-agreements --accept-source-agreements --ignore-unavailable
        }
    }

    # npm globals (npm itself comes with node)
    $npmJson = Join-Path $manifestDir "npm-global.json"
    if ((Test-Path $npmJson) -and (Test-Tool npm)) {
        $deps = (Get-Content $npmJson -Raw | ConvertFrom-Json).dependencies
        foreach ($prop in $deps.PSObject.Properties | Where-Object { $_.Name -ne "npm" }) {
            Invoke-RestoreAction "npm install -g $($prop.Name)@$($prop.Value.version)" {
                npm install -g "$($prop.Name)@$($prop.Value.version)"
            }
        }
    }

    # pip
    $pipTxt = Join-Path $manifestDir "pip.txt"
    if ((Test-Path $pipTxt) -and (Test-Tool pip)) {
        Invoke-RestoreAction "pip install -r pip.txt" { pip install -r $pipTxt }
    }

    # VS Code extensions (lines look like publisher.name@1.2.3)
    $extTxt = Join-Path $manifestDir "vscode-extensions.txt"
    if ((Test-Path $extTxt) -and (Test-Tool code)) {
        foreach ($ext in Get-Content $extTxt | Where-Object { $_.Trim() }) {
            Invoke-RestoreAction "code --install-extension $ext" { code --install-extension $ext --force }
        }
    }

    # PowerShell modules
    $modJson = Join-Path $manifestDir "psmodules.json"
    if (Test-Path $modJson) {
        foreach ($mod in @(Get-Content $modJson -Raw | ConvertFrom-Json)) {
            Invoke-RestoreAction "Install-Module $($mod.Name) $($mod.Version)" {
                Install-Module -Name $mod.Name -RequiredVersion $mod.Version -Scope CurrentUser -Force -AllowClobber
            }
        }
    }

    $dotnetTxt = Join-Path $manifestDir "dotnet-sdks.txt"
    if (Test-Path $dotnetTxt) {
        Write-Host "`n  .NET SDKs that were installed (install manually if still needed):" -ForegroundColor Gray
        Get-Content $dotnetTxt | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
    }
}

# --- Unpushed work captured by the backup -----------------------------------
$wipDir = Join-Path $BackupPath "wip"
if (Test-Path $wipDir) {
    Write-Step "Unpushed work saved by the backup (review before discarding)"
    foreach ($w in Get-ChildItem $wipDir -Directory) {
        Write-Host "  $($w.Name)" -ForegroundColor Yellow
        $info = Join-Path $w.FullName "info.txt"
        if (Test-Path $info) { Get-Content $info | Where-Object { $_ -match '^(remote|changed|unpushed)' } | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray } }
    }
    Write-Host "  Apply inside the matching repo, after cloning:" -ForegroundColor Gray
    Write-Host "    git fetch <wip>\<repo>\unpushed.bundle '<branch>:<branch>'   # unpushed commits" -ForegroundColor Gray
    Write-Host "    git apply <wip>\<repo>\uncommitted.patch                      # uncommitted changes" -ForegroundColor Gray
    Write-Host "    copy <wip>\<repo>\untracked\* back into the repo              # new files" -ForegroundColor Gray
}

# --- Manual steps ------------------------------------------------------------
Write-Step "Manual steps (cannot be automated)"
@(
    "Import the GPG signing key from the restored key-backup folder (see its README), then run: gpg-connect-agent reloadagent /bye",
    "Check git signing config: git config --get gpg.program ; git config --get user.signingkey",
    "Sign in to CLIs: gh auth login ; aws sso login (or restore ~/.aws) ; any cloud-drive or password-manager apps",
    "Restore app settings that are not in the backup (editor sync, browser profiles)",
    "Run the dev console from the restored repo and confirm: console.ps1 --version"
) | ForEach-Object { Write-Host "  [ ] $_" }
Write-Host ""
