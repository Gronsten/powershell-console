# Line Counter Exclusion Management Functions

function Edit-LineCounterExclusions {
    # Check if lineCounter section exists
    if (-not ($script:Config.PSObject.Properties.Name -contains "lineCounter")) {
        Write-Host "⚠️  No 'lineCounter' section found in config.json" -ForegroundColor Yellow
        Invoke-StandardPause
        return
    }

    # Load exclusions
    $lineCounter = $script:Config.lineCounter
    $extensions = @()
    $pathPatterns = @()

    if ($lineCounter.PSObject.Properties.Name -contains "globalExclusions") {
        $globalEx = $lineCounter.globalExclusions
        if ($globalEx.PSObject.Properties.Name -contains "extensions") {
            $extensions = @($globalEx.extensions)
        }
        if ($globalEx.PSObject.Properties.Name -contains "pathPatterns") {
            $pathPatterns = @($globalEx.pathPatterns)
        }
    }

    do {
        Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║ CODE COUNT - MANAGE EXCLUSIONS             ║" -ForegroundColor Cyan
        Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Cyan

        # Build exclusion list for display
        $exclusionList = @()

        foreach ($ext in ($extensions | Sort-Object)) {
            $exclusionList += [PSCustomObject]@{
                Type = "Extension"
                Pattern = $ext
                DisplayText = "[EXT]  $ext"
            }
        }

        foreach ($pattern in ($pathPatterns | Sort-Object)) {
            $exclusionList += [PSCustomObject]@{
                Type = "PathPattern"
                Pattern = $pattern
                DisplayText = "[PATH] $pattern"
            }
        }

        Write-Host "Current exclusions: $($exclusionList.Count) total ($($extensions.Count) extensions + $($pathPatterns.Count) patterns)" -ForegroundColor Cyan
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
            Add-NewLineCounterExclusion -Extensions ([ref]$extensions) -PathPatterns ([ref]$pathPatterns)
            continue
        }

        if (-not $selected -or $selected.Count -eq 0) {
            return
        }

        # Remove selected exclusions
        foreach ($item in $selected) {
            if ($item.Type -eq "Extension") {
                $extensions = @($extensions | Where-Object { $_ -ne $item.Pattern })
            } else {
                $pathPatterns = @($pathPatterns | Where-Object { $_ -ne $item.Pattern })
            }
        }

        Save-LineCounterExclusions -Extensions $extensions -PathPatterns $pathPatterns

    } while ($true)
}

function Add-NewLineCounterExclusion {
    param(
        [ref]$Extensions,
        [ref]$PathPatterns
    )

    Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  ADD NEW EXCLUSION                         ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    Write-Host "1. Extension (e.g., .log, .zip)" -ForegroundColor White
    Write-Host "2. Path Pattern (e.g., backup, logs)" -ForegroundColor White
    Write-Host "Q. Cancel" -ForegroundColor Gray
    Write-Host ""

    $choice = Read-Host "Select type"

    if ($choice -eq "1") {
        Write-Host ""
        Write-Host "TIP: Enter multiple extensions separated by commas" -ForegroundColor Gray
        $newExtensions = Read-Host "Enter extension(s) (e.g., .log or log1, log2, log3)"
        if ([string]::IsNullOrWhiteSpace($newExtensions)) {
            Write-Host "Cancelled." -ForegroundColor Yellow
            Start-Sleep -Seconds 1
            return
        }

        # Split by comma and trim whitespace
        $extList = $newExtensions -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

        $addedCount = 0
        $skippedCount = 0

        foreach ($ext in $extList) {
            # Normalize extension
            if (-not $ext.StartsWith(".")) {
                $ext = ".$ext"
            }
            $ext = $ext.ToLower()

            if ($Extensions.Value -contains $ext) {
                Write-Host "  ⚠️  Skipping '$ext' (already excluded)" -ForegroundColor Yellow
                $skippedCount++
            } else {
                $Extensions.Value += $ext
                Write-Host "  ✓ Added extension: $ext" -ForegroundColor Green
                $addedCount++
            }
        }

        if ($addedCount -gt 0) {
            Save-LineCounterExclusions -Extensions $Extensions.Value -PathPatterns $PathPatterns.Value
            Write-Host ""
            Write-Host "✅ Added $addedCount extension(s)" -ForegroundColor Green
        }

        if ($skippedCount -gt 0) {
            Write-Host "ℹ️  Skipped $skippedCount duplicate(s)" -ForegroundColor Cyan
        }

        Start-Sleep -Seconds 2
    }
    elseif ($choice -eq "2") {
        Write-Host ""
        Write-Host "TIP: Enter multiple patterns separated by commas" -ForegroundColor Gray
        $newPatterns = Read-Host "Enter path pattern(s) (e.g., backup, logs, temp)"
        if ([string]::IsNullOrWhiteSpace($newPatterns)) {
            Write-Host "Cancelled." -ForegroundColor Yellow
            Start-Sleep -Seconds 1
            return
        }

        # Split by comma and trim whitespace
        $patternList = $newPatterns -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

        $addedCount = 0
        $skippedCount = 0

        foreach ($pattern in $patternList) {
            if ($PathPatterns.Value -contains $pattern) {
                Write-Host "  ⚠️  Skipping '$pattern' (already excluded)" -ForegroundColor Yellow
                $skippedCount++
            } else {
                $PathPatterns.Value += $pattern
                Write-Host "  ✓ Added path pattern: $pattern" -ForegroundColor Green
                $addedCount++
            }
        }

        if ($addedCount -gt 0) {
            Save-LineCounterExclusions -Extensions $Extensions.Value -PathPatterns $PathPatterns.Value
            Write-Host ""
            Write-Host "✅ Added $addedCount path pattern(s)" -ForegroundColor Green
        }

        if ($skippedCount -gt 0) {
            Write-Host "ℹ️  Skipped $skippedCount duplicate(s)" -ForegroundColor Cyan
        }

        Start-Sleep -Seconds 2
    }
    else {
        Write-Host "Cancelled." -ForegroundColor Yellow
        Start-Sleep -Seconds 1
    }
}

function Save-LineCounterExclusions {
    param(
        [array]$Extensions,
        [array]$PathPatterns
    )

    try {
        # Ensure structure exists
        if (-not ($script:Config.PSObject.Properties.Name -contains "lineCounter")) {
            $script:Config | Add-Member -MemberType NoteProperty -Name "lineCounter" -Value ([PSCustomObject]@{
                globalExclusions = [PSCustomObject]@{
                    extensions = @()
                    pathPatterns = @()
                }
            }) -Force
        }

        if (-not ($script:Config.lineCounter.PSObject.Properties.Name -contains "globalExclusions")) {
            $script:Config.lineCounter | Add-Member -MemberType NoteProperty -Name "globalExclusions" -Value ([PSCustomObject]@{
                extensions = @()
                pathPatterns = @()
            }) -Force
        }

        # Update config in memory
        $script:Config.lineCounter.globalExclusions.extensions = $Extensions
        $script:Config.lineCounter.globalExclusions.pathPatterns = $PathPatterns

        # Save to root directory config.json (not module directory)
        # Navigate from modules/line-counter/ -> modules/ -> powershell-console/
        $modulesDir = Split-Path -Parent $PSScriptRoot
        $rootDir = Split-Path -Parent $modulesDir
        $configPath = Join-Path $rootDir "config.json"
        $script:Config | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Encoding UTF8

        Write-Host "`n✅ Exclusions saved successfully!" -ForegroundColor Green
        Start-Sleep -Seconds 1
    }
    catch {
        Write-Host "`n❌ Error saving exclusions: $($_.Exception.Message)" -ForegroundColor Red
        Start-Sleep -Seconds 2
    }
}
