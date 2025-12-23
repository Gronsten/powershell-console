# Backup Exclusion Management Functions
# Part of the backup-dev module
# Dot-source this file from console.ps1 to enable exclusion management

function Edit-BackupExclusions {
    <#
    .SYNOPSIS
    Interactive unified exclusion management for backup-dev

    .DESCRIPTION
    Single interface to view, add, and remove all backup exclusions.
    Uses checkbox selection with enhanced controls:
    - Space: Toggle selection
    - A: Select all
    - N: Deselect all
    - +: Add new exclusion
    - Up/Down: Navigate
    - Enter: Confirm removal of selected items
    #>

    # Check if backupDev section exists
    if (-not ($script:Config.PSObject.Properties.Name -contains "backupDev")) {
        Write-Host "⚠️  No 'backupDev' section found in config.json" -ForegroundColor Yellow
        Write-Host "  Please add the backupDev section from config.example.json" -ForegroundColor Gray
        Invoke-StandardPause
        return
    }

    # Ensure exclusions structure exists (support both old and new formats)
    $backupDev = $script:Config.backupDev
    $dirExclusions = @()
    $fileExclusions = @()

    # New unified structure
    if ($backupDev.PSObject.Properties.Name -contains "exclusions") {
        if ($backupDev.exclusions.PSObject.Properties.Name -contains "directories") {
            $dirExclusions = @($backupDev.exclusions.directories)
        }
        if ($backupDev.exclusions.PSObject.Properties.Name -contains "files") {
            $fileExclusions = @($backupDev.exclusions.files)
        }
    }
    # Old structure (backward compatibility)
    else {
        if ($backupDev.PSObject.Properties.Name -contains "excludeDirectories") {
            $dirExclusions += @($backupDev.excludeDirectories)
        }
        if ($backupDev.PSObject.Properties.Name -contains "excludeFiles") {
            $fileExclusions += @($backupDev.excludeFiles)
        }
        if ($backupDev.PSObject.Properties.Name -contains "customExclusions") {
            if ($backupDev.customExclusions.PSObject.Properties.Name -contains "directories") {
                $dirExclusions += @($backupDev.customExclusions.directories)
            }
            if ($backupDev.customExclusions.PSObject.Properties.Name -contains "files") {
                $fileExclusions += @($backupDev.customExclusions.files)
            }
        }
        # Remove duplicates
        $dirExclusions = $dirExclusions | Select-Object -Unique
        $fileExclusions = $fileExclusions | Select-Object -Unique
    }

    do {
        Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║ BACKUP - MANAGE EXCLUSIONS                 ║" -ForegroundColor Cyan
        Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Cyan

        # Build exclusion list
        $exclusionList = @()

        foreach ($dir in ($dirExclusions | Sort-Object)) {
            $exclusionList += [PSCustomObject]@{
                Type = "Directory"
                Pattern = $dir
                DisplayText = "[DIR]  $dir"
            }
        }

        foreach ($file in ($fileExclusions | Sort-Object)) {
            $exclusionList += [PSCustomObject]@{
                Type = "File"
                Pattern = $file
                DisplayText = "[FILE] $file"
            }
        }

        if ($exclusionList.Count -eq 0) {
            Write-Host "No exclusions configured." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Press '+' to add an exclusion, or 'Q' to go back..." -ForegroundColor Gray
            $key = Read-Host

            if ($key -eq "Q" -or $key -eq "q") {
                return
            } elseif ($key -eq "+") {
                # Add new exclusion
                Add-NewExclusion -DirExclusions ([ref]$dirExclusions) -FileExclusions ([ref]$fileExclusions)
                continue
            }
            continue
        }

        Write-Host "Current exclusions: $($exclusionList.Count) total ($($dirExclusions.Count) directories + $($fileExclusions.Count) files)" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Controls:" -ForegroundColor Yellow
        Write-Host "  Space  = Toggle selection     A = Select all" -ForegroundColor Gray
        Write-Host "  N      = Deselect all         + = Add new exclusion" -ForegroundColor Gray
        Write-Host "  Enter  = Remove selected      Q = Back to menu" -ForegroundColor Gray
        Write-Host ""

        # Use a script-scoped variable to track custom actions
        $script:CustomAction = $null

        # Custom key handler for '+' to add new exclusions
        $customKeyHandler = {
            param($Key, $CurrentIndex, $SelectedIndexes, $Done, $Items)

            if ($Key.KeyChar -eq '+') {
                $script:CustomAction = "Add"
                $Done.Value = $true
                return $true
            }

            return $false
        }

        $selected = Show-CheckboxSelection -Items $exclusionList -Title " " `
            -Instructions "" -CustomKeyHandler $customKeyHandler -AllowAllItemsSelection

        # Check if custom action (Add) was triggered
        if ($script:CustomAction -eq "Add") {
            $script:CustomAction = $null
            Add-NewExclusion -DirExclusions ([ref]$dirExclusions) -FileExclusions ([ref]$fileExclusions)
            continue
        }

        if (-not $selected -or $selected.Count -eq 0) {
            # User pressed Q or no selection
            return
        }

        # Remove selected exclusions
        foreach ($item in $selected) {
            if ($item.Type -eq "Directory") {
                $dirExclusions = @($dirExclusions | Where-Object { $_ -ne $item.Pattern })
            } else {
                $fileExclusions = @($fileExclusions | Where-Object { $_ -ne $item.Pattern })
            }
            Write-Host "✓ Removed: $($item.Display)" -ForegroundColor Green
        }

        # Save to config
        Save-Exclusions -DirExclusions $dirExclusions -FileExclusions $fileExclusions

        Write-Host ""
        Write-Host "Removed $($selected.Count) exclusion(s)" -ForegroundColor Cyan
        Write-Host ""
        Start-Sleep -Seconds 1
    } while ($true)
}

function Add-NewExclusion {
    param(
        [ref]$DirExclusions,
        [ref]$FileExclusions
    )

    Write-Host ""
    Write-Host "Add New Exclusion:" -ForegroundColor Cyan
    Write-Host "  1. Directory (e.g., 'my-folder', 'temp_*')" -ForegroundColor Gray
    Write-Host "  2. File pattern (e.g., '*.bak', 'debug_*')" -ForegroundColor Gray
    Write-Host ""
    $choice = Read-Host "Enter choice (1-2, or Q to cancel)"

    if ($choice -eq "Q" -or $choice -eq "q") {
        return
    }

    $type = if ($choice -eq "1") { "directory" } elseif ($choice -eq "2") { "file" } else {
        Write-Host "Invalid choice." -ForegroundColor Red
        Start-Sleep -Seconds 1
        return
    }

    Write-Host ""
    Write-Host "TIP: Enter multiple patterns separated by commas" -ForegroundColor Gray
    $patterns = Read-Host "Enter $type pattern(s) to exclude"

    if ([string]::IsNullOrWhiteSpace($patterns)) {
        Write-Host "No pattern entered." -ForegroundColor Yellow
        Start-Sleep -Seconds 1
        return
    }

    # Split by comma and trim whitespace
    $patternList = $patterns -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    if ($patternList.Count -eq 0) {
        Write-Host "No valid patterns entered." -ForegroundColor Yellow
        Start-Sleep -Seconds 1
        return
    }

    # Add to appropriate list
    $addedCount = 0
    $skippedCount = 0

    if ($type -eq "directory") {
        foreach ($pattern in $patternList) {
            if ($DirExclusions.Value -contains $pattern) {
                Write-Host "  ⚠️  Skipping '$pattern' (already excluded)" -ForegroundColor Yellow
                $skippedCount++
            } else {
                $DirExclusions.Value = @($DirExclusions.Value + $pattern)
                Write-Host "  ✓ Added directory: $pattern" -ForegroundColor Green
                $addedCount++
            }
        }
    } else {
        foreach ($pattern in $patternList) {
            if ($FileExclusions.Value -contains $pattern) {
                Write-Host "  ⚠️  Skipping '$pattern' (already excluded)" -ForegroundColor Yellow
                $skippedCount++
            } else {
                $FileExclusions.Value = @($FileExclusions.Value + $pattern)
                Write-Host "  ✓ Added file pattern: $pattern" -ForegroundColor Green
                $addedCount++
            }
        }
    }

    # Save to config if any were added
    if ($addedCount -gt 0) {
        Save-Exclusions -DirExclusions $DirExclusions.Value -FileExclusions $FileExclusions.Value
        Write-Host ""
        Write-Host "✅ Added $addedCount $type exclusion(s)" -ForegroundColor Green
    }

    if ($skippedCount -gt 0) {
        Write-Host "ℹ️  Skipped $skippedCount duplicate(s)" -ForegroundColor Cyan
    }

    Start-Sleep -Seconds 2
}

function Save-Exclusions {
    param(
        [array]$DirExclusions,
        [array]$FileExclusions
    )

    # Migrate to new unified structure if needed
    if (-not $script:Config.backupDev.PSObject.Properties.Name -contains "exclusions") {
        # Create new structure
        $script:Config.backupDev | Add-Member -MemberType NoteProperty -Name "exclusions" -Value ([PSCustomObject]@{
            directories = @()
            files = @()
        }) -Force

        # Remove old structure if it exists
        $oldProps = @('excludeDirectories', 'excludeFiles', 'customExclusions')
        foreach ($prop in $oldProps) {
            if ($script:Config.backupDev.PSObject.Properties.Name -contains $prop) {
                $script:Config.backupDev.PSObject.Properties.Remove($prop)
            }
        }
    }

    # Save to unified structure
    $script:Config.backupDev.exclusions.directories = $DirExclusions
    $script:Config.backupDev.exclusions.files = $FileExclusions

    # Save config to root directory (not module directory)
    # Navigate from modules/backup-dev/ -> modules/ -> powershell-console/
    $modulesDir = Split-Path -Parent $PSScriptRoot
    $rootDir = Split-Path -Parent $modulesDir
    $configPath = Join-Path $rootDir "config.json"
    $script:Config | ConvertTo-Json -Depth 10 | Set-Content $configPath
}

function Start-BackupDryRun {
    <#
    .SYNOPSIS
    Run backup in dry-run mode (simulation without copying)

    .DESCRIPTION
    Executes backup-dev.ps1 with --dry-run flag to simulate backup without copying files
    Perfect for testing exclusions and seeing what would be backed up
    #>

    Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  BACKUP - DRY RUN (SIMULATION)             ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    $backupScriptPath = Get-BackupScriptPath
    if (-not $backupScriptPath) { return }

    Write-Host "This will simulate a full backup WITHOUT copying files." -ForegroundColor Cyan
    Write-Host "Perfect for testing exclusions and seeing what would be backed up." -ForegroundColor Gray
    Write-Host ""

    Invoke-BackupScript -Arguments "--dry-run" -Description "Dry-run simulation"
}
