# Handle command-line parameters
param(
    [switch]$Version,
    [switch]$v,
    [switch]$Help,
    [switch]$h
)

# Version constant
$script:ConsoleVersion = "1.20.1"

# Detect environment based on script path
$scriptPath = $PSScriptRoot
if ($scriptPath -match '[\\/]_dev[\\/]?$') {
    $script:Environment = "DEV"
    $script:EnvColor = "Yellow"
} elseif ($scriptPath -match '[\\/]_prod[\\/]?$') {
    $script:Environment = "PROD"
    $script:EnvColor = "Green"
} else {
    # Regular users don't need environment indicator
    $script:Environment = ""
    $script:EnvColor = "Gray"
}

# Handle double-dash arguments (--version, --help) by checking $MyInvocation
if ($MyInvocation.Line -match '--version') {
    # Load config to get configVersion
    $configPath = Join-Path $PSScriptRoot "config.json"
    $configVersion = "unknown"
    if (Test-Path $configPath) {
        try {
            $config = Get-Content $configPath -Raw | ConvertFrom-Json
            $configVersion = $config.configVersion
        } catch {
            $configVersion = "error"
        }
    }

    Write-Host ""
    if ($script:Environment) {
        Write-Host "[$script:Environment] " -ForegroundColor $script:EnvColor -NoNewline
    }
    Write-Host "powershell-console" -ForegroundColor Cyan
    Write-Host "  Console version: " -ForegroundColor Gray -NoNewline
    Write-Host $script:ConsoleVersion -ForegroundColor Cyan
    Write-Host "  Config version:  " -ForegroundColor Gray -NoNewline
    Write-Host $configVersion -ForegroundColor Cyan
    Write-Host ""
    exit 0
}

if ($MyInvocation.Line -match '--help') {
    Write-Host ""
    Write-Host "PowerShell Console" -ForegroundColor Cyan
    Write-Host "==================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  .\console.ps1                Run the interactive console menu"
    Write-Host "  .\console.ps1 --version      Display version information"
    Write-Host "  .\console.ps1 --help         Display this help message"
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  --version, -Version, -v      Show version number"
    Write-Host "  --help, -Help, -h            Show this help message"
    Write-Host ""
    Write-Host "Sponsor: " -ForegroundColor Magenta -NoNewline
    Write-Host "https://github.com/sponsors/Gronsten" -ForegroundColor Blue
    Write-Host ""
    exit 0
}

# Handle -Version or -v flag
if ($Version -or $v) {
    if ($script:Environment) {
        Write-Host "[$script:Environment] " -ForegroundColor $script:EnvColor -NoNewline
    }
    Write-Host "powershell-console version $script:ConsoleVersion" -ForegroundColor Cyan
    exit 0
}

# Handle -Help or -h flag
if ($Help -or $h) {
    Write-Host ""
    Write-Host "PowerShell Console" -ForegroundColor Cyan
    Write-Host "==================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  .\console.ps1                Run the interactive console menu"
    Write-Host "  .\console.ps1 --version      Display version information"
    Write-Host "  .\console.ps1 --help         Display this help message"
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  --version, -Version, -v      Show version number"
    Write-Host "  --help, -Help, -h            Show this help message"
    Write-Host ""
    Write-Host "Sponsor: " -ForegroundColor Magenta -NoNewline
    Write-Host "https://github.com/sponsors/Gronsten" -ForegroundColor Blue
    Write-Host ""
    exit 0
}

# ==========================================
# CONSOLE INITIALIZATION
# ==========================================

# Save original console state
$script:OriginalOutputEncoding = [Console]::OutputEncoding
$script:OriginalInputEncoding = [Console]::InputEncoding
$script:OriginalPSOutputEncoding = $OutputEncoding

# Set console encoding to UTF-8 for proper character rendering
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

# Set PowerShell output encoding
$OutputEncoding = [System.Text.Encoding]::UTF8

# Don't modify PSStyle.OutputRendering - let it stay as ANSI for Oh-My-Posh compatibility

# Set window title with environment indicator
if ($script:Environment) {
    $host.UI.RawUI.WindowTitle = "Console [$script:Environment] v$script:ConsoleVersion"
} else {
    $host.UI.RawUI.WindowTitle = "Console v$script:ConsoleVersion"
}

# Display startup banner with environment indicator
Write-Host ""
if ($script:Environment) {
    Write-Host "[$script:Environment] " -ForegroundColor $script:EnvColor -NoNewline
}
Write-Host "PowerShell Console " -ForegroundColor Cyan -NoNewline
Write-Host "v$script:ConsoleVersion" -ForegroundColor Gray
Write-Host ""

# Function to restore console state on exit
function Restore-ConsoleState {
    # Restore original encoding settings
    [Console]::OutputEncoding = $script:OriginalOutputEncoding
    [Console]::InputEncoding = $script:OriginalInputEncoding
    $global:OutputEncoding = $script:OriginalPSOutputEncoding

    # Clear any lingering keyboard buffer
    while ([Console]::KeyAvailable) {
        [Console]::ReadKey($true) | Out-Null
    }

    # Reset console cursor visibility
    [Console]::CursorVisible = $true

    # Write a newline to ensure clean prompt rendering
    Write-Host ""
}

# ==========================================
# CONFIGURATION LOADING
# ==========================================

function Import-Configuration {
    $configPath = Join-Path $PSScriptRoot "config.json"
    if (-not (Test-Path $configPath)) {
        throw "Configuration file not found: $configPath"
    }

    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        return $config
    }
    catch {
        throw "Error loading configuration: $($_.Exception.Message)"
    }
}

function Update-ScriptConfiguration {
    Write-Host "Reloading configuration..." -ForegroundColor Gray
    $script:Config = Import-Configuration
    Write-Host "✓ Configuration reloaded" -ForegroundColor Green
}

function Save-Menu {
    param(
        [string]$MenuTitle,
        [array]$MenuItems
    )

    $configPath = Join-Path $PSScriptRoot "config.json"
    $config = Get-Content $configPath -Raw | ConvertFrom-Json

    # Initialize menus section if it doesn't exist
    if (-not $config.PSObject.Properties['menus']) {
        $config | Add-Member -NotePropertyName 'menus' -NotePropertyValue @{} -Force
    }

    # Convert menu items to saveable format
    $menuData = @()
    foreach ($item in $MenuItems) {
        $text = if ($item -is [string]) { $item } else { $item.Text }
        $action = if ($item -is [hashtable] -and $item.Action) {
            # Store the action as a string representation
            $item.Action.ToString()
        } else {
            ""
        }

        $menuData += @{
            text = $text
            action = $action
        }
    }

    # Save menu to config
    if ($config.menus.PSObject.Properties[$MenuTitle]) {
        $config.menus.$MenuTitle = $menuData
    } else {
        $config.menus | Add-Member -NotePropertyName $MenuTitle -NotePropertyValue $menuData -Force
    }

    # Save back to file
    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
}

function Get-MenuFromConfig {
    param(
        [string]$MenuTitle,
        [array]$DefaultMenuItems
    )

    # Check if menu exists in config
    if ($script:Config.PSObject.Properties['menus'] -and
        $script:Config.menus.PSObject.Properties[$MenuTitle]) {

        # Load menu from config
        $savedMenu = $script:Config.menus.$MenuTitle
        $menuItems = @()

        foreach ($item in $savedMenu) {
            # Reconstruct menu item with action
            if ($item.action -and $item.action -ne "") {
                $menuItems += New-MenuAction $item.text ([scriptblock]::Create($item.action))
            } else {
                $menuItems += $item.text
            }
        }

        # Check if default menu has new items not in saved config
        # This handles cases where code updates add new menu options
        foreach ($defaultItem in $DefaultMenuItems) {
            $defaultText = $defaultItem.Text
            $existsInSaved = $false

            foreach ($savedItem in $savedMenu) {
                if ($savedItem.text -eq $defaultText) {
                    $existsInSaved = $true
                    break
                }
            }

            # If default item doesn't exist in saved menu, append it
            if (-not $existsInSaved) {
                $menuItems += $defaultItem
            }
        }

        return $menuItems
    }

    # Return default menu if not in config
    return $DefaultMenuItems
}

function Get-AwsAccountMenuOrder {
    <#
    .SYNOPSIS
    Gets the saved menu order for AWS accounts, or returns null if not saved
    #>
    if ($script:Config.PSObject.Properties['awsAccountMenuOrder']) {
        return $script:Config.awsAccountMenuOrder
    }
    return $null
}

function Save-AwsAccountMenuOrder {
    <#
    .SYNOPSIS
    Saves the AWS account menu order to config.json
    .PARAMETER MenuItems
    Array of menu item hashtables with Environment and Role properties
    #>
    param(
        [array]$MenuItems
    )

    $configPath = Join-Path $PSScriptRoot "config.json"
    $config = Get-Content $configPath -Raw | ConvertFrom-Json

    # Build order array from menu items
    # Format: "envKey" or "envKey:Role" for role-specific items
    $orderArray = @()
    foreach ($item in $MenuItems) {
        if ($item.Environment -eq "sync" -or $item.Environment -eq "manual") {
            # Skip special items - they're always added at the end
            continue
        }

        if ($item.Role) {
            $orderArray += "$($item.Environment):$($item.Role)"
        } else {
            $orderArray += $item.Environment
        }
    }

    # Save to config
    if ($config.PSObject.Properties['awsAccountMenuOrder']) {
        $config.awsAccountMenuOrder = $orderArray
    } else {
        $config | Add-Member -NotePropertyName 'awsAccountMenuOrder' -NotePropertyValue $orderArray -Force
    }

    # Save back to file
    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8

    # Reload config
    $script:Config = Import-Configuration
}

function Save-AwsAccountCustomName {
    <#
    .SYNOPSIS
    Saves a custom display name for an AWS account menu item
    .PARAMETER Environment
    The environment key
    .PARAMETER Role
    The role (optional)
    .PARAMETER CustomName
    The custom display text
    #>
    param(
        [string]$Environment,
        [string]$Role,
        [string]$CustomName
    )

    $configPath = Join-Path $PSScriptRoot "config.json"
    $config = Get-Content $configPath -Raw | ConvertFrom-Json

    # Find the environment
    if (-not $config.environments.PSObject.Properties[$Environment]) {
        Write-Warning "Environment '$Environment' not found in config"
        return
    }

    # Initialize customMenuNames if it doesn't exist
    if (-not $config.environments.$Environment.PSObject.Properties['customMenuNames']) {
        $config.environments.$Environment | Add-Member -NotePropertyName 'customMenuNames' -NotePropertyValue @{} -Force
    }

    # Save the custom name
    $key = if ($Role) { $Role } else { "default" }

    if ($config.environments.$Environment.customMenuNames.PSObject.Properties[$key]) {
        $config.environments.$Environment.customMenuNames.$key = $CustomName
    } else {
        $config.environments.$Environment.customMenuNames | Add-Member -NotePropertyName $key -NotePropertyValue $CustomName -Force
    }

    # Save back to file
    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8

    # Reload config
    $script:Config = Import-Configuration
}

function Get-AwsAccountCustomName {
    <#
    .SYNOPSIS
    Gets the custom display name for an AWS account menu item if it exists
    .PARAMETER Environment
    The environment key
    .PARAMETER Role
    The role (optional)
    .RETURNS
    Custom name if exists, otherwise $null
    #>
    param(
        [string]$Environment,
        [string]$Role
    )

    if (-not $script:Config.environments.PSObject.Properties[$Environment]) {
        return $null
    }

    $env = $script:Config.environments.$Environment

    if (-not $env.PSObject.Properties['customMenuNames']) {
        return $null
    }

    $key = if ($Role) { $Role } else { "default" }

    if ($env.customMenuNames.PSObject.Properties[$key]) {
        return $env.customMenuNames.$key
    }

    return $null
}

$script:Config = Import-Configuration

# Dot-source backup exclusion management functions
$backupExclusionsPath = Join-Path $PSScriptRoot "modules\backup-dev\backup-exclusions.ps1"
if (Test-Path $backupExclusionsPath) {
    . $backupExclusionsPath
}

# Dot-source line counter exclusion management functions
$lineCounterExclusionsPath = Join-Path $PSScriptRoot "modules\line-counter\line-counter-exclusions.ps1"
if (Test-Path $lineCounterExclusionsPath) {
    . $lineCounterExclusionsPath
}

# Global variables for connection state
$global:awsInstance = ""
$global:remoteIP = ""
$global:localPort = ""
$global:remotePort = ""
$global:currentAwsEnvironment = ""
$global:currentAwsRegion = ""
# Hashtable to store per-account default instance IDs
$global:accountDefaultInstances = @{}
# Hashtable to store menu position memory (remembers last selected item per menu)
$global:MenuPositionMemory = @{}

# ==========================================
# PACKAGE MANAGER UPDATE AUTOMATION
# ==========================================

function Get-NpmInstallInfo {
    <#
    .SYNOPSIS
    Detects how npm/nodejs is installed and whether npm package updates should be managed.

    .DESCRIPTION
    Returns information about npm installation:
    - IsScoopManaged: Whether npm is installed via Scoop
    - CliVersion: Version from 'npm --version'
    - GlobalVersion: Version from 'npm list -g npm' (if npm is globally installed)
    - ShouldManageNpmPackage: Whether npm package itself should appear in updates

    .EXAMPLE
    $npmInfo = Get-NpmInstallInfo
    if (-not $npmInfo.ShouldManageNpmPackage) {
        # Skip npm package in update list
    }
    #>
    [CmdletBinding()]
    param()

    $result = @{
        IsScoopManaged = $false
        CliVersion = $null
        GlobalVersion = $null
        ShouldManageNpmPackage = $false
        NpmPath = $null
    }

    try {
        # Get npm executable path
        $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
        if (-not $npmCmd) {
            return $result
        }

        $result.NpmPath = $npmCmd.Path

        # Check if npm is installed via Scoop (path contains 'scoop')
        if ($result.NpmPath -match '\\scoop\\') {
            $result.IsScoopManaged = $true
        }

        # Get CLI version (the npm that runs when you type 'npm')
        $result.CliVersion = (npm --version 2>&1).Trim()

        # Check if npm is globally installed as a package
        $npmListOutput = npm list -g npm --depth=0 2>&1 | Out-String
        if ($npmListOutput -match 'npm@([\d\.]+)') {
            $result.GlobalVersion = $matches[1]
        }

        # Determine if we should manage npm package updates
        # Only manage if:
        # 1. NOT Scoop-managed, OR
        # 2. Scoop-managed BUT there's a global override (GlobalVersion exists and differs from CliVersion)
        if (-not $result.IsScoopManaged) {
            # Standalone npm installation - we should manage it
            $result.ShouldManageNpmPackage = $true
        } elseif ($result.GlobalVersion -and $result.GlobalVersion -ne $result.CliVersion) {
            # Scoop-managed but has global override - we should manage the override
            $result.ShouldManageNpmPackage = $true
        } else {
            # Scoop-managed with no override - let Scoop handle it
            $result.ShouldManageNpmPackage = $false
        }

    } catch {
        Write-Host "  ⚠️  Error detecting npm installation: $_" -ForegroundColor Red
    }

    return $result
}

function Invoke-PackageUninstall {
    <#
    .SYNOPSIS
    Uninstalls packages across multiple package managers.

    .PARAMETER Packages
    Array of package objects with Manager, Name, and Version properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Packages
    )

    $results = @{ Uninstalled = 0; Failed = 0; Errors = @() }

    foreach ($pkg in $Packages) {
        Write-Host "  → $($pkg.Name)..." -ForegroundColor Yellow -NoNewline
        try {
            $output = switch ($pkg.Manager) {
                "scoop" { scoop uninstall $pkg.Name 2>&1 }
                "npm" { npm uninstall -g $pkg.Name 2>&1 }
                "pip" { pip uninstall -y $pkg.Name 2>&1 }
                "winget" {
                    # Include --version if available to handle multiple installed versions
                    $uninstallArgs = @("uninstall", "--id", $pkg.Name, "--exact")
                    if ($pkg.Version) {
                        $uninstallArgs += @("--version", $pkg.Version)
                    }
                    & winget $uninstallArgs 2>&1
                }
            }
            if ($LASTEXITCODE -eq 0) {
                Write-Host " ✅" -ForegroundColor Green
                $results.Uninstalled++
            } else {
                Write-Host " ❌" -ForegroundColor Red
                $results.Failed++
                $results.Errors += "$($pkg.Manager): $($pkg.Name) - $output"
            }
        } catch {
            Write-Host " ❌" -ForegroundColor Red
            $results.Failed++
            $results.Errors += "$($pkg.Manager): $($pkg.Name) - $_"
        }
    }

    return $results
}

function Get-InstalledPackages {
    [CmdletBinding()]
    param()

    Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  INSTALLED PACKAGES                        ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    Write-Host "Select packages to uninstall (or press ESC/Q to exit without changes)`n" -ForegroundColor Gray

    # Collection for uninstall selections
    $allPackagesToUninstall = @()

    # Scoop packages
    Write-Host "📦 Scoop packages:" -ForegroundColor Yellow
    Write-Host ""
    try {
        $scoopList = scoop list 2>&1 | Out-String
        $scoopLines = $scoopList -split "`n"
        $scoopPackages = @()
        $inData = $false

        foreach ($line in $scoopLines) {
            if ($line -match 'Name.*Version.*Source') {
                $inData = $true
                continue
            }
            if ($line -match '^-+') {
                continue
            }
            if ($inData -and $line.Trim().Length -gt 0) {
                $parts = $line -split '\s+' | Where-Object { $_.Trim() -ne '' }
                if ($parts.Count -ge 2) {
                    $scoopPackages += @{
                        Manager = "scoop"
                        Name = $parts[0]
                        Version = $parts[1]
                        Source = if ($parts.Count -ge 3) { $parts[2] } else { "" }
                        DisplayText = "$($parts[0]) - $($parts[1])"
                    }
                }
            }
        }

        if ($scoopPackages.Count -eq 0) {
            Write-Host "  No Scoop packages installed" -ForegroundColor Gray
        } else {
            Write-Host "  Found $($scoopPackages.Count) package(s)" -ForegroundColor Cyan

            # Use pagination for large lists
            $batchSize = 20
            $allSelections = @()
            $allSelectionsRef = [ref]$allSelections

            if ($scoopPackages.Count -gt $batchSize) {
                $startIndex = 0
                $batchNumber = 1
                $continueSelecting = $true

                while ($continueSelecting -and $startIndex -lt $scoopPackages.Count) {
                    $endIndex = [Math]::Min($startIndex + $batchSize, $scoopPackages.Count)
                    $currentBatch = $scoopPackages[$startIndex..($endIndex - 1)]

                    $result = Show-InlineBatchSelection `
                        -CurrentBatch $currentBatch `
                        -AllSelections $allSelectionsRef `
                        -Title "SCOOP PACKAGES (BATCH $batchNumber)" `
                        -BatchNumber $batchNumber `
                        -TotalShown $endIndex `
                        -TotalAvailable $scoopPackages.Count

                    if ($result.Cancelled) {
                        $continueSelecting = $false
                    } elseif (-not $result.FetchMore) {
                        $continueSelecting = $false
                    }

                    $startIndex = $endIndex
                    $batchNumber++
                }
            } else {
                $selectedPackages = Show-CheckboxSelection -Items $scoopPackages -Title "SELECT SCOOP PACKAGES TO UNINSTALL"
                if ($selectedPackages) { $allSelections = $selectedPackages }
            }

            if ($allSelections.Count -gt 0) {
                $allPackagesToUninstall += $allSelections
                Write-Host "`n  ✅ Added $($allSelections.Count) Scoop package(s) to uninstall queue" -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "  ⚠️  Scoop not found" -ForegroundColor Red
    }

    # npm global packages
    Write-Host "`n📦 npm global packages:" -ForegroundColor Yellow
    Write-Host ""
    try {
        $npmList = npm list -g --depth=0 --json 2>&1 | Out-String
        $npmPackages = @()

        try {
            $npmData = $npmList | ConvertFrom-Json
            if ($npmData.dependencies) {
                foreach ($pkg in $npmData.dependencies.PSObject.Properties) {
                    $npmPackages += @{
                        Manager = "npm"
                        Name = $pkg.Name
                        Version = $pkg.Value.version
                        DisplayText = "$($pkg.Name) - $($pkg.Value.version)"
                    }
                }
            }
        } catch {
            # JSON parse failed, npm might not be available
        }

        if ($npmPackages.Count -eq 0) {
            Write-Host "  No npm global packages installed" -ForegroundColor Gray
        } else {
            Write-Host "  Found $($npmPackages.Count) package(s)" -ForegroundColor Cyan

            $batchSize = 20
            $allSelections = @()
            $allSelectionsRef = [ref]$allSelections

            if ($npmPackages.Count -gt $batchSize) {
                $startIndex = 0
                $batchNumber = 1
                $continueSelecting = $true

                while ($continueSelecting -and $startIndex -lt $npmPackages.Count) {
                    $endIndex = [Math]::Min($startIndex + $batchSize, $npmPackages.Count)
                    $currentBatch = $npmPackages[$startIndex..($endIndex - 1)]

                    $result = Show-InlineBatchSelection `
                        -CurrentBatch $currentBatch `
                        -AllSelections $allSelectionsRef `
                        -Title "NPM PACKAGES (BATCH $batchNumber)" `
                        -BatchNumber $batchNumber `
                        -TotalShown $endIndex `
                        -TotalAvailable $npmPackages.Count

                    if ($result.Cancelled) {
                        $continueSelecting = $false
                    } elseif (-not $result.FetchMore) {
                        $continueSelecting = $false
                    }

                    $startIndex = $endIndex
                    $batchNumber++
                }
            } else {
                $selectedPackages = Show-CheckboxSelection -Items $npmPackages -Title "SELECT NPM PACKAGES TO UNINSTALL"
                if ($selectedPackages) { $allSelections = $selectedPackages }
            }

            if ($allSelections.Count -gt 0) {
                $allPackagesToUninstall += $allSelections
                Write-Host "`n  ✅ Added $($allSelections.Count) npm package(s) to uninstall queue" -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "  ⚠️  npm not found" -ForegroundColor Red
    }

    # pip packages
    Write-Host "`n📦 pip packages:" -ForegroundColor Yellow
    Write-Host ""
    try {
        $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
        if (-not $pythonCmd) {
            Write-Host "  ⚠️  Python not found" -ForegroundColor Red
        } else {
            $pipList = pip list 2>&1 | Out-String
            $pipLines = $pipList -split "`n"
            $pipPackages = @()
            $inData = $false

            foreach ($line in $pipLines) {
                if ($line -match '^Package\s+Version') {
                    $inData = $true
                    continue
                }
                if ($line -match '^-+\s+-+') {
                    continue
                }
                if ($inData -and $line.Trim().Length -gt 0) {
                    $parts = $line -split '\s+' | Where-Object { $_.Trim() -ne '' }
                    if ($parts.Count -ge 2) {
                        $pipPackages += @{
                            Manager = "pip"
                            Name = $parts[0]
                            Version = $parts[1]
                            DisplayText = "$($parts[0]) - $($parts[1])"
                        }
                    }
                }
            }

            if ($pipPackages.Count -eq 0) {
                Write-Host "  No pip packages installed" -ForegroundColor Gray
            } else {
                Write-Host "  Found $($pipPackages.Count) package(s)" -ForegroundColor Cyan

                $batchSize = 20
                $allSelections = @()
                $allSelectionsRef = [ref]$allSelections

                if ($pipPackages.Count -gt $batchSize) {
                    $startIndex = 0
                    $batchNumber = 1
                    $continueSelecting = $true

                    while ($continueSelecting -and $startIndex -lt $pipPackages.Count) {
                        $endIndex = [Math]::Min($startIndex + $batchSize, $pipPackages.Count)
                        $currentBatch = $pipPackages[$startIndex..($endIndex - 1)]

                        $result = Show-InlineBatchSelection `
                            -CurrentBatch $currentBatch `
                            -AllSelections $allSelectionsRef `
                            -Title "PIP PACKAGES (BATCH $batchNumber)" `
                            -BatchNumber $batchNumber `
                            -TotalShown $endIndex `
                            -TotalAvailable $pipPackages.Count

                        if ($result.Cancelled) {
                            $continueSelecting = $false
                        } elseif (-not $result.FetchMore) {
                            $continueSelecting = $false
                        }

                        $startIndex = $endIndex
                        $batchNumber++
                    }
                } else {
                    $selectedPackages = Show-CheckboxSelection -Items $pipPackages -Title "SELECT PIP PACKAGES TO UNINSTALL"
                    if ($selectedPackages) { $allSelections = $selectedPackages }
                }

                if ($allSelections.Count -gt 0) {
                    $allPackagesToUninstall += $allSelections
                    Write-Host "`n  ✅ Added $($allSelections.Count) pip package(s) to uninstall queue" -ForegroundColor Green
                }
            }
        }
    } catch {
        Write-Host "  ⚠️  pip not found" -ForegroundColor Red
    }

    # winget packages
    Write-Host "`n📦 winget packages:" -ForegroundColor Yellow
    Write-Host ""
    try {
        $wingetOutput = winget list 2>&1 | Out-String

        $cleanedLines = $wingetOutput -split "`n" | Where-Object {
            $line = $_
            if (-not $line.Trim()) { return $false }
            if ($line -match '^\s*[\-\\/\|]\s*$') { return $false }
            if ($line.Trim() -match '^[\-\\/\|]$') { return $false }
            return $true
        }

        $headerLine = $null
        $separatorLine = $null
        $dataLines = @()
        $inData = $false

        foreach ($line in $cleanedLines) {
            if ($line -match 'Name.*Id.*Version' -and -not $headerLine) {
                $headerLine = $line
                continue
            }
            elseif ($line -match '^-+' -and $headerLine -and -not $separatorLine) {
                $separatorLine = $line
                $inData = $true
                continue
            }
            elseif ($line -match '^\d+\s+(package|upgrade|installed)' -or $line -match 'The following packages') {
                $inData = $false
            }
            elseif ($inData) {
                $dataLines += $line
            }
        }

        # Parse into structured objects
        $wingetPackages = @()
        if ($headerLine) {
            $namePos = $headerLine.IndexOf("Name")
            $idPos = $headerLine.IndexOf("Id")
            $versionPos = $headerLine.IndexOf("Version")

            foreach ($line in $dataLines) {
                try {
                    $packageName = if ($idPos -gt $namePos) {
                        $line.Substring($namePos, $idPos - $namePos).Trim()
                    } else { "" }

                    $packageId = if ($versionPos -gt $idPos) {
                        $line.Substring($idPos, $versionPos - $idPos).Trim()
                    } else { "" }

                    $sourcePos = $headerLine.IndexOf("Source")
                    $versionEndPos = if ($sourcePos -gt $versionPos) { $sourcePos } else { $line.Length }
                    $packageVersion = if ($versionEndPos -gt $versionPos -and $versionPos -lt $line.Length) {
                        $line.Substring($versionPos, [Math]::Min($versionEndPos - $versionPos, $line.Length - $versionPos)).Trim()
                    } else { "" }

                    if ($packageId -ne "") {
                        $wingetPackages += @{
                            Manager = "winget"
                            Name = $packageId
                            DisplayName = $packageName
                            Version = $packageVersion
                            DisplayText = "$packageName - $packageId ($packageVersion)"
                        }
                    }
                } catch {
                    continue
                }
            }
        }

        if ($wingetPackages.Count -eq 0) {
            Write-Host "  No winget packages found" -ForegroundColor Gray
        } else {
            Write-Host "  Found $($wingetPackages.Count) package(s)" -ForegroundColor Cyan

            $batchSize = 20
            $allSelections = @()
            $allSelectionsRef = [ref]$allSelections

            if ($wingetPackages.Count -gt $batchSize) {
                $startIndex = 0
                $batchNumber = 1
                $continueSelecting = $true

                while ($continueSelecting -and $startIndex -lt $wingetPackages.Count) {
                    $endIndex = [Math]::Min($startIndex + $batchSize, $wingetPackages.Count)
                    $currentBatch = $wingetPackages[$startIndex..($endIndex - 1)]

                    $result = Show-InlineBatchSelection `
                        -CurrentBatch $currentBatch `
                        -AllSelections $allSelectionsRef `
                        -Title "WINGET PACKAGES (BATCH $batchNumber)" `
                        -BatchNumber $batchNumber `
                        -TotalShown $endIndex `
                        -TotalAvailable $wingetPackages.Count

                    if ($result.Cancelled) {
                        $continueSelecting = $false
                    } elseif (-not $result.FetchMore) {
                        $continueSelecting = $false
                    }

                    $startIndex = $endIndex
                    $batchNumber++
                }
            } else {
                $selectedPackages = Show-CheckboxSelection -Items $wingetPackages -Title "SELECT WINGET PACKAGES TO UNINSTALL"
                if ($selectedPackages) { $allSelections = $selectedPackages }
            }

            if ($allSelections.Count -gt 0) {
                $allPackagesToUninstall += $allSelections
                Write-Host "`n  ✅ Added $($allSelections.Count) winget package(s) to uninstall queue" -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "  ⚠️  winget not found" -ForegroundColor Red
    }

    # Process uninstallations
    if ($allPackagesToUninstall.Count -gt 0) {
        Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Red
        Write-Host "║  ⚠️  WARNING: PACKAGES TO UNINSTALL         ║" -ForegroundColor Red
        Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Red

        $byManager = $allPackagesToUninstall | Group-Object Manager
        Write-Host "Total: $($allPackagesToUninstall.Count) package(s) selected for removal`n" -ForegroundColor White

        foreach ($group in $byManager) {
            $managerName = $group.Name.ToUpper()
            Write-Host "  $managerName ($($group.Count) package(s)):" -ForegroundColor Yellow
            foreach ($pkg in $group.Group) {
                Write-Host "    • $($pkg.Name) ($($pkg.Version))" -ForegroundColor White
            }
            Write-Host ""
        }

        Write-Host "⚠️  This action CANNOT be undone!" -ForegroundColor Red
        Write-Host ""

        # First confirmation
        Write-Host "Are you sure you want to uninstall these packages? (y/N): " -ForegroundColor Yellow -NoNewline
        $confirm1 = Read-Host
        if ($confirm1.ToLower() -ne "y") {
            Write-Host "`nUninstallation cancelled." -ForegroundColor Cyan
            return
        }

        # Second confirmation - type UNINSTALL
        Write-Host ""
        Write-Host "Type 'UNINSTALL' to confirm: " -ForegroundColor Red -NoNewline
        $confirm2 = Read-Host
        if ($confirm2 -ne "UNINSTALL") {
            Write-Host "`nUninstallation cancelled." -ForegroundColor Cyan
            return
        }

        Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Red
        Write-Host "║  UNINSTALLING PACKAGES                     ║" -ForegroundColor Red
        Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Red

        $results = Invoke-PackageUninstall -Packages $allPackagesToUninstall

        Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║  COMPLETE                                  ║" -ForegroundColor Cyan
        Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Cyan

        Write-Host "  ✅ Successfully uninstalled: $($results.Uninstalled)" -ForegroundColor Green
        if ($results.Failed -gt 0) {
            Write-Host "  ❌ Failed: $($results.Failed)" -ForegroundColor Red
            Write-Host "`nErrors:" -ForegroundColor Red
            foreach ($errorMsg in $results.Errors) {
                Write-Host "  • $errorMsg" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "`nNo packages selected for uninstallation." -ForegroundColor Gray
    }
}

function Select-PackagesToUpdate {
    [CmdletBinding()]
    param()

    Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  MANAGE PACKAGE UPDATES                    ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    # Collect available updates
    $availableUpdates = @()

    # Check Scoop
    Write-Host "Checking Scoop for updates..." -ForegroundColor Gray
    try {
        # First, refresh bucket metadata (this is required for accurate status)
        Write-Host "  → Refreshing bucket metadata..." -ForegroundColor Gray
        scoop update

        Write-Host "  → Checking package status..." -ForegroundColor Gray
        $scoopStatus = scoop status *>&1 | Out-String
        Write-Host $scoopStatus

        if ($scoopStatus -notmatch "Latest versions for all apps are installed") {
            # Parse scoop status output for outdated packages
            # Format: Name Installed Version Latest Version Missing Dependencies Info
            #         ---- ----------------- -------------- -------------------- ----
            #         aws  2.31.16           2.31.18
            $scoopLines = $scoopStatus -split "`n"
            $inTable = $false

            foreach ($line in $scoopLines) {
                # Find the header line
                if ($line -match 'Name\s+Installed Version\s+Latest Version') {
                    $inTable = $true
                    continue
                }

                # Skip separator line
                if ($line -match '^-+') {
                    continue
                }

                # Parse table rows - only lines that have package data
                if ($inTable -and $line.Trim().Length -gt 0) {
                    # Split by whitespace, filtering empty entries
                    $parts = $line -split '\s+' | Where-Object { $_.Trim() -ne '' }

                    # Need at least 3 parts: Name, InstalledVersion, LatestVersion
                    if ($parts.Count -ge 3) {
                        $name = $parts[0]
                        $currentVer = $parts[1]
                        $newVer = $parts[2]

                        $availableUpdates += @{
                            Manager = "Scoop"
                            Name = $name
                            CurrentVersion = $currentVer
                            NewVersion = $newVer
                            DisplayText = "[$name] Scoop: $currentVer -> $newVer"
                        }
                    }
                }
            }
        }
    } catch {
        Write-Host "  ⚠️  Error checking Scoop" -ForegroundColor Red
    }

    # Check npm
    Write-Host "Checking npm for updates..." -ForegroundColor Gray
    try {
        # Get npm installation info to determine if we should manage npm package
        $npmInfo = Get-NpmInstallInfo

        # Capture npm output (includes both stderr and stdout)
        $npmRawOutput = npm outdated -g --json 2>&1 | Out-String

        # Extract JSON from output (npm outputs error text, then JSON, then more error text)
        # Find lines that form valid JSON (between first { and last })
        $lines = $npmRawOutput -split "`n"
        $jsonLines = @()
        $inJson = $false
        $braceCount = 0

        foreach ($line in $lines) {
            # Start capturing when we see opening brace
            if ($line.Trim() -match '^[\{\[]') {
                $inJson = $true
            }

            if ($inJson) {
                $jsonLines += $line

                # Count braces to find where JSON ends
                $braceCount += ($line.ToCharArray() | Where-Object { $_ -eq '{' -or $_ -eq '[' }).Count
                $braceCount -= ($line.ToCharArray() | Where-Object { $_ -eq '}' -or $_ -eq ']' }).Count

                # When braces are balanced, JSON object is complete
                if ($braceCount -eq 0) {
                    break
                }
            }
        }

        $npmOutdated = $null
        if ($jsonLines.Count -gt 0) {
            $jsonString = $jsonLines -join "`n"
            try {
                $npmOutdated = $jsonString | ConvertFrom-Json
            } catch {
                # JSON parsing failed, likely not valid JSON
                $npmOutdated = $null
            }
        }

        # Check if response contains authentication error (E401)
        if ($npmOutdated -and $npmOutdated.error -and $npmOutdated.error.code -eq "E401") {
            Write-Host "  ⚠️  npm authentication required (corporate registry)" -ForegroundColor Yellow
            $loginResponse = Read-Host "  Would you like to login now? (Y/n)"

            if ($loginResponse -notmatch '^[Nn]') {
                Write-Host "  Starting npm web authentication..." -ForegroundColor Cyan
                npm login --auth-type=web

                # Retry the outdated check after login
                Write-Host "  Retrying npm update check..." -ForegroundColor Gray
                $npmRawOutput = npm outdated -g --json 2>&1 | Out-String

                # Extract JSON from retry output
                $lines = $npmRawOutput -split "`n"
                $jsonLines = @()
                $inJson = $false
                $braceCount = 0

                foreach ($line in $lines) {
                    if ($line.Trim() -match '^[\{\[]') {
                        $inJson = $true
                    }

                    if ($inJson) {
                        $jsonLines += $line
                        $braceCount += ($line.ToCharArray() | Where-Object { $_ -eq '{' -or $_ -eq '[' }).Count
                        $braceCount -= ($line.ToCharArray() | Where-Object { $_ -eq '}' -or $_ -eq ']' }).Count

                        if ($braceCount -eq 0) {
                            break
                        }
                    }
                }

                $npmOutdated = $null
                if ($jsonLines.Count -gt 0) {
                    $jsonString = $jsonLines -join "`n"
                    try {
                        $npmOutdated = $jsonString | ConvertFrom-Json
                    } catch {
                        $npmOutdated = $null
                    }
                }

                # Check if retry still has error
                if ($npmOutdated -and $npmOutdated.error) {
                    Write-Host "  ⚠️  Still unable to check npm updates" -ForegroundColor Red
                    $npmOutdated = $null
                }
            } else {
                Write-Host "  Skipping npm update check" -ForegroundColor Gray
                $npmOutdated = $null
            }
        }

        if ($npmOutdated) {
            foreach ($pkg in $npmOutdated.PSObject.Properties) {
                # Skip error property if present
                if ($pkg.Name -eq "error") {
                    continue
                }

                # Skip npm package itself if it's Scoop-managed (let Scoop handle nodejs-lts updates)
                if ($pkg.Name -eq "npm" -and -not $npmInfo.ShouldManageNpmPackage) {
                    Write-Host "  → Skipping npm (managed by Scoop nodejs-lts)" -ForegroundColor DarkGray
                    continue
                }

                $availableUpdates += @{
                    Manager = "npm"
                    Name = $pkg.Name
                    CurrentVersion = $pkg.Value.current
                    NewVersion = $pkg.Value.latest
                    DisplayText = "[$($pkg.Name)] npm: $($pkg.Value.current) -> $($pkg.Value.latest)"
                }
            }
        }
    } catch {
        Write-Host "  ⚠️  Error checking npm" -ForegroundColor Red
    }

    # Check pip
    Write-Host "Checking pip for updates..." -ForegroundColor Gray
    try {
        # Check if Python is available
        $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
        if ($pythonCmd) {
            $pipOutdated = pip list --outdated 2>&1 | Out-String
            if ($pipOutdated -match "Package\s+Version\s+Latest") {
                # Parse pip list output
                # Format: Package    Version    Latest    Type
                #         -------    -------    ------    ----
                #         requests   2.28.0     2.31.0    wheel
                $pipLines = $pipOutdated -split "`n"
                $inTable = $false

                foreach ($line in $pipLines) {
                    # Skip notice lines
                    if ($line -match '^\[notice\]') {
                        continue
                    }

                    # Find the header line
                    if ($line -match 'Package\s+Version\s+Latest') {
                        $inTable = $true
                        continue
                    }

                    # Skip separator line
                    if ($line -match '^-+') {
                        continue
                    }

                    # Parse table rows - only lines that have package data
                    if ($inTable -and $line.Trim().Length -gt 0) {
                        # Split by whitespace, filtering empty entries
                        $parts = $line -split '\s+' | Where-Object { $_.Trim() -ne '' }

                        # Need at least 3 parts: Package, Version, Latest (Type is optional)
                        # Also verify the first part doesn't start with special characters
                        if ($parts.Count -ge 3 -and $parts[0] -notmatch '^\[') {
                            $name = $parts[0]
                            $currentVer = $parts[1]
                            $newVer = $parts[2]

                            $availableUpdates += @{
                                Manager = "pip"
                                Name = $name
                                CurrentVersion = $currentVer
                                NewVersion = $newVer
                                DisplayText = "[$name] pip: $currentVer -> $newVer"
                            }
                        }
                    }
                }

                # Filter out packages with strict dependency constraints using pipdeptree
                Write-Host "  → Checking dependency constraints..." -ForegroundColor Gray
                try {
                    $pipdeptreeCmd = Get-Command pipdeptree -ErrorAction SilentlyContinue
                    if ($pipdeptreeCmd) {
                        $depTree = pipdeptree --json 2>&1 | ConvertFrom-Json

                        # Build a map of packages that are dependencies with version constraints
                        $constrainedPackages = @{}
                        foreach ($pkg in $depTree) {
                            foreach ($dep in $pkg.dependencies) {
                                $depName = $dep.package_name.ToLower()
                                $reqVer = $dep.required_version

                                # Check if there's an upper bound constraint (e.g., <79.0.0)
                                if ($reqVer -match '<' -or $reqVer -match '==') {
                                    if (-not $constrainedPackages.ContainsKey($depName)) {
                                        $constrainedPackages[$depName] = @()
                                    }
                                    $constrainedPackages[$depName] += @{
                                        Parent = $pkg.package.package_name
                                        Constraint = $reqVer
                                    }
                                }
                            }
                        }

                        # Filter out constrained packages from available updates
                        $filteredUpdates = @()
                        foreach ($update in $availableUpdates) {
                            if ($update.Manager -eq "pip") {
                                $pkgNameLower = $update.Name.ToLower()
                                if ($constrainedPackages.ContainsKey($pkgNameLower)) {
                                    # Check if the new version would violate constraints
                                    $constraints = $constrainedPackages[$pkgNameLower]
                                    $wouldBreak = $false

                                    foreach ($constraint in $constraints) {
                                        # Simple check: if there's a < constraint, the update might break it
                                        if ($constraint.Constraint -match '<') {
                                            Write-Host "    ⚠️  Skipping $($update.Name): constrained by $($constraint.Parent) ($($constraint.Constraint))" -ForegroundColor Yellow
                                            $wouldBreak = $true
                                            break
                                        }
                                    }

                                    if (-not $wouldBreak) {
                                        $filteredUpdates += $update
                                    }
                                } else {
                                    $filteredUpdates += $update
                                }
                            } else {
                                $filteredUpdates += $update
                            }
                        }

                        # Replace available updates with filtered list
                        $availableUpdates = $filteredUpdates
                    } else {
                        Write-Host "    ℹ️  pipdeptree not found - install with 'pip install pipdeptree' for dependency checking" -ForegroundColor Gray
                    }
                } catch {
                    Write-Host "    ⚠️  Error checking dependencies: $_" -ForegroundColor Yellow
                }
            }
        }
    } catch {
        Write-Host "  ⚠️  Error checking pip" -ForegroundColor Red
    }

    # Check winget
    Write-Host "Checking winget for updates..." -ForegroundColor Gray
    try {
        $wingetOutput = winget upgrade 2>&1 | Out-String
        $wingetLines = $wingetOutput -split "`n"

        $inTable = $false

        foreach ($line in $wingetLines) {
            # Find the header line (contains "Name" and "Id" and "Version" and "Available")
            if ($line -match 'Name.*Id.*Version.*Available') {
                $inTable = $true
                continue
            }

            # Skip the separator line (dashes)
            if ($line -match '^-+$') {
                continue
            }

            # Stop parsing when we hit the summary line
            if ($line -match '^\d+\s+upgrade') {
                break
            }

            # Parse table rows - only lines that are in the table and not empty
            if ($inTable -and $line.Trim().Length -gt 0) {
                # winget uses fixed-width columns with single spaces
                # Split by single or multiple spaces
                $parts = $line -split '\s+' | Where-Object { $_.Trim() -ne '' }

                # We need at least 4 parts: Name, Id, Version, Available (Source is optional 5th)
                if ($parts.Count -ge 4) {
                    # Name might be multiple words, so we need to be smart about this
                    # The last part is Source (if present), before that is Available, before that is Version, before that is Id
                    # Everything before Id is the Name

                    if ($parts.Count -eq 5) {
                        # Has Source column: Name Id Version Available Source
                        # But Name might be multiple words, so check if last item looks like a source
                        # $parts[-1] is source (not used)
                        $newVer = $parts[-2]
                        $currentVer = $parts[-3]
                        $id = $parts[-4]
                        # Everything else is the name
                        $name = ($parts[0..($parts.Count - 5)] -join ' ').Trim()
                    } elseif ($parts.Count -eq 4) {
                        # No Source or Name is single word: Name Id Version Available
                        $newVer = $parts[-1]
                        $currentVer = $parts[-2]
                        $id = $parts[-3]
                        $name = $parts[0]
                    } else {
                        # More than 5 parts means Name has multiple words
                        # Assume format: Name(multi-word) Id Version Available Source
                        # $parts[-1] is source (not used)
                        $newVer = $parts[-2]
                        $currentVer = $parts[-3]
                        $id = $parts[-4]
                        $name = ($parts[0..($parts.Count - 5)] -join ' ').Trim()
                    }

                    # Validate this is actually a data row (not a header or separator)
                    # Check that ID looks like a real package ID (contains a dot usually)
                    if ($id -and $id -match '\.' -and
                        $currentVer -notmatch '^(Version|-+)$' -and
                        $newVer -notmatch '^(Available|Source|-+)$' -and
                        $newVer -ne $currentVer) {

                        $availableUpdates += @{
                            Manager = "winget"
                            Name = $id
                            DisplayName = $name
                            CurrentVersion = $currentVer
                            NewVersion = $newVer
                            DisplayText = "[$name] winget: $currentVer -> $newVer"
                        }
                    }
                }
            }
        }
    } catch {
        Write-Host "  ⚠️  Error checking winget" -ForegroundColor Red
    }

    if ($availableUpdates.Count -eq 0) {
        Write-Host "`n✅ All packages are up to date!" -ForegroundColor Green
        return
    }

    # Display available updates with checkboxes using centralized function
    Write-Host "`nAvailable updates:" -ForegroundColor Yellow

    $selectedPackages = Show-CheckboxSelection `
        -Items $availableUpdates `
        -Title "MANAGE PACKAGE UPDATES" `
        -Instructions "Use Up/Down arrows to navigate, Space to select/deselect, Enter to install" `
        -UseClearHost `
        -AllowAllItemsSelection

    if (-not $selectedPackages -or $selectedPackages.Count -eq 0) {
        if ($null -eq $selectedPackages) {
            Write-Host "`nCancelled." -ForegroundColor Yellow
        } else {
            Write-Host "`nNo packages selected." -ForegroundColor Yellow
        }
        return
    }

    Clear-Host
    Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "║  INSTALLING SELECTED UPDATES               ║" -ForegroundColor Magenta
    Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Magenta

    Write-Host "Installing $($selectedPackages.Count) package(s)...`n" -ForegroundColor Cyan

    foreach ($pkg in $selectedPackages) {
        Write-Host "→ Updating $($pkg.Name) ($($pkg.Manager))..." -ForegroundColor Yellow

        try {
            if ($pkg.Manager -eq "Scoop") {
                scoop update $pkg.Name
                Write-Host "  ✅ $($pkg.Name) updated successfully" -ForegroundColor Green
            } elseif ($pkg.Manager -eq "npm") {
                npm install -g "$($pkg.Name)@$($pkg.NewVersion)"
                Write-Host "  ✅ $($pkg.Name) updated successfully" -ForegroundColor Green
            } elseif ($pkg.Manager -eq "winget") {
                winget upgrade --id $pkg.Name --accept-package-agreements --accept-source-agreements
                Write-Host "  ✅ $($pkg.Name) updated successfully" -ForegroundColor Green
            } elseif ($pkg.Manager -eq "pip") {
                # pip itself requires special update command
                if ($pkg.Name -eq "pip") {
                    python.exe -m pip install --upgrade pip
                } else {
                    pip install --upgrade --upgrade-strategy only-if-needed $pkg.Name
                }
                Write-Host "  ✅ $($pkg.Name) updated successfully" -ForegroundColor Green
            }
        } catch {
            Write-Host "  ❌ Error updating $($pkg.Name): $_" -ForegroundColor Red
        }
        Write-Host ""
    }

    Write-Host "✅ Update process complete!" -ForegroundColor Green
}

function Show-CheckboxSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Items,

        [Parameter(Mandatory=$true)]
        [string]$Title,

        [Parameter(Mandatory=$false)]
        [string]$Instructions = "Use Up/Down arrows to navigate, Space to select/deselect, Enter to confirm",

        [Parameter(Mandatory=$false)]
        [switch]$UseClearHost = $false,

        [Parameter(Mandatory=$false)]
        [scriptblock]$CustomKeyHandler = $null,

        [Parameter(Mandatory=$false)]
        [hashtable]$CustomInstructions = @{},

        [Parameter(Mandatory=$false)]
        [switch]$AllowAllItemsSelection = $false
    )

    if ($Items.Count -eq 0) {
        return @()
    }

    $selectedIndexes = @()
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $selectedIndexes += $false
    }

    $currentIndex = 0
    $done = $false
    $startLine = 0

    # Function to draw the UI (for Clear-Host mode only in loop)
    $drawUI = {
        Clear-Host

        # Draw header (skip if title is blank/whitespace - caller is providing their own header)
        if (-not [string]::IsNullOrWhiteSpace($Title)) {
            Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Cyan
            Write-Host "║ $($Title.PadRight(42)) ║" -ForegroundColor Cyan
            Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Cyan

            Write-Host $Instructions -ForegroundColor Gray

            # Show custom instructions if provided
            if ($CustomInstructions.Count -gt 0) {
                foreach ($key in $CustomInstructions.Keys) {
                    Write-Host $CustomInstructions[$key] -ForegroundColor Gray
                }
            } else {
                Write-Host "Press A to select all, N to deselect all, Q to cancel`n" -ForegroundColor Gray
            }
        }

        # Draw items
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $item = $Items[$i]
            $isInstalled = if ($item -is [hashtable] -and $item.ContainsKey('Installed')) { $item.Installed } else { $false }
            $displayText = if ($item.DisplayText) { $item.DisplayText } else { $item.ToString() }

            # Truncate to console width
            $maxWidth = [Console]::WindowWidth - 10
            if ($displayText.Length -gt $maxWidth) {
                $displayText = $displayText.Substring(0, $maxWidth - 3) + "..."
            }

            $checkbox = if ($selectedIndexes[$i]) { "[x]" } else { "[ ]" }
            $arrow = if ($i -eq $currentIndex) { ">" } else { " " }
            $line = "$arrow $checkbox $displayText"

            # Simple color output for Clear-Host mode
            $color = if ($i -eq $currentIndex) { "Green" } else { "White" }
            if ($isInstalled) { $color = "DarkGray" }
            Write-Host $line -ForegroundColor $color
        }
    }

    # Initial draw based on mode
    if ($UseClearHost) {
        & $drawUI
    } else {
        # Draw header once for cursor positioning mode (skip if title is blank/whitespace)
        if (-not [string]::IsNullOrWhiteSpace($Title)) {
            Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Cyan
            Write-Host "║ $($Title.PadRight(42)) ║" -ForegroundColor Cyan
            Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Cyan

            Write-Host $Instructions -ForegroundColor Gray

            # Show custom instructions if provided
            if ($CustomInstructions.Count -gt 0) {
                foreach ($key in $CustomInstructions.Keys) {
                    Write-Host $CustomInstructions[$key] -ForegroundColor Gray
                }
            } else {
                Write-Host "Press A to select all, N to deselect all, Q to cancel`n" -ForegroundColor Gray
            }
        }

        $startLine = [Console]::CursorTop

        # Draw initial list once (let console scroll naturally)
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $item = $Items[$i]
            $isInstalled = if ($item -is [hashtable] -and $item.ContainsKey('Installed')) { $item.Installed } else { $false }
            $displayText = if ($item.DisplayText) { $item.DisplayText } else { $item.ToString() }

            # Truncate to console width
            $maxWidth = [Console]::WindowWidth - 10
            if ($displayText.Length -gt $maxWidth) {
                $displayText = $displayText.Substring(0, $maxWidth - 3) + "..."
            }

            # Use same format as redraw: arrow space checkbox space text
            $line = "  [ ] $displayText"
            if ($isInstalled) {
                Write-Host $line -ForegroundColor DarkGray
            } else {
                Write-Host $line
            }
        }

        # After drawing, recalculate startLine (window may have scrolled)
        $endLine = [Console]::CursorTop
        $startLine = $endLine - $Items.Count
    }

    while (-not $done) {
        # Redraw UI based on mode
        if ($UseClearHost) {
            & $drawUI
        } else {
            # Redraw selection list using cursor positioning
            for ($i = 0; $i -lt $Items.Count; $i++) {
                try {
                    [Console]::SetCursorPosition(0, $startLine + $i)
                } catch {
                    # If we can't set position, we're likely at buffer limit
                    continue
                }

                $item = $Items[$i]
                $isInstalled = if ($item -is [hashtable] -and $item.ContainsKey('Installed')) { $item.Installed } else { $false }
                $checkbox = if ($selectedIndexes[$i]) { "[x]" } else { "[ ]" }
                $arrow = if ($i -eq $currentIndex) { ">" } else { " " }

                $displayText = if ($item.DisplayText) { $item.DisplayText } else { $item.ToString() }

                # Truncate to console width to prevent wrapping
                $maxWidth = [Console]::WindowWidth - 10
                if ($displayText.Length -gt $maxWidth) {
                    $displayText = $displayText.Substring(0, $maxWidth - 3) + "..."
                }

                # Build line with padding to clear entire line
                $line = "$arrow $checkbox $displayText"
                # Ensure we pad to full console width to clear any previous content
                $line = $line.PadRight([Console]::WindowWidth - 1)

                # Write with color based on current selection and installed status
                if ($isInstalled) {
                    [Console]::ForegroundColor = [ConsoleColor]::DarkGray
                } elseif ($i -eq $currentIndex) {
                    [Console]::ForegroundColor = [ConsoleColor]::Green
                } else {
                    [Console]::ForegroundColor = [ConsoleColor]::White
                }
                [Console]::Write($line)
                [Console]::ResetColor()
            }
        }

        $key = [Console]::ReadKey($true)

        # Try custom key handler first
        $customHandled = $false
        if ($CustomKeyHandler) {
            $customResult = & $CustomKeyHandler -Key $key -CurrentIndex ([ref]$currentIndex) -SelectedIndexes ([ref]$selectedIndexes) -Done ([ref]$done) -Items $Items
            if ($customResult -eq $true) {
                $customHandled = $true
            }
        }

        # Standard key handling if not handled by custom handler
        if (-not $customHandled) {
            switch ($key.Key) {
                'UpArrow' {
                    $currentIndex = ($currentIndex - 1 + $Items.Count) % $Items.Count
                }
                'DownArrow' {
                    $currentIndex = ($currentIndex + 1) % $Items.Count
                }
                'Spacebar' {
                    # Allow selection based on installed status
                    $item = $Items[$currentIndex]
                    $isInstalled = if ($item -is [hashtable] -and $item.ContainsKey('Installed')) { $item.Installed } else { $false }
                    if ($AllowAllItemsSelection -or -not $isInstalled) {
                        $selectedIndexes[$currentIndex] = -not $selectedIndexes[$currentIndex]
                    }
                }
                'A' {
                    # Select all items based on AllowAllItemsSelection parameter
                    for ($i = 0; $i -lt $selectedIndexes.Count; $i++) {
                        $item = $Items[$i]
                        $isInstalled = if ($item -is [hashtable] -and $item.ContainsKey('Installed')) { $item.Installed } else { $false }
                        if ($AllowAllItemsSelection -or -not $isInstalled) {
                            $selectedIndexes[$i] = $true
                        }
                    }
                }
                'N' {
                    for ($i = 0; $i -lt $selectedIndexes.Count; $i++) {
                        $selectedIndexes[$i] = $false
                    }
                }
                'Enter' {
                    $done = $true
                }
                'Q' {
                    # Clean up based on mode
                    if (-not $UseClearHost) {
                        [Console]::SetCursorPosition(0, $startLine + $Items.Count)
                        Write-Host ""
                    } else {
                        Write-Host "`nCancelled." -ForegroundColor Yellow
                    }
                    return $null  # Return null to indicate cancellation
                }
            }
        }
    }

    # Clean up based on mode
    if (-not $UseClearHost) {
        [Console]::SetCursorPosition(0, $startLine + $Items.Count)
        Write-Host ""
    }

    # Return selected items
    $selected = @()
    for ($i = 0; $i -lt $Items.Count; $i++) {
        if ($selectedIndexes[$i]) {
            $selected += $Items[$i]
        }
    }

    return $selected
}

function Show-InlineBatchSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$CurrentBatch,

        [Parameter(Mandatory=$true)]
        [ref]$AllSelections,

        [Parameter(Mandatory=$true)]
        [string]$Title,

        [Parameter(Mandatory=$false)]
        [int]$BatchNumber = 1,

        [Parameter(Mandatory=$false)]
        [int]$TotalShown = 0,

        [Parameter(Mandatory=$false)]
        [int]$TotalAvailable = 0
    )

    if ($CurrentBatch.Count -eq 0) {
        return @{
            Continue = $false
            FetchMore = $false
        }
    }

    $selectedIndexes = @()
    for ($i = 0; $i -lt $CurrentBatch.Count; $i++) {
        $selectedIndexes += $false
    }

    $currentIndex = 0
    $done = $false

    # Draw initial UI
    Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║ $($Title.PadRight(42)) ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════╝" -ForegroundColor Cyan

    $moreAvailable = $TotalShown -lt $TotalAvailable
    Write-Host "Showing $TotalShown of $TotalAvailable | Selected: $($AllSelections.Value.Count)" -ForegroundColor Yellow
    Write-Host "Use Up/Down arrows, Space to select, Enter when done" -ForegroundColor Gray
    if ($moreAvailable) {
        Write-Host "Press M to save selections and fetch More, A for all, N for none, Q to cancel" -ForegroundColor Cyan
    } else {
        Write-Host "Press A to select all, N to deselect all, Q to cancel" -ForegroundColor Gray
    }
    Write-Host ""

    $startLine = [Console]::CursorTop

    # Draw initial list once (let console scroll naturally)
    for ($i = 0; $i -lt $CurrentBatch.Count; $i++) {
        $item = $CurrentBatch[$i]
        $isInstalled = if ($item -is [hashtable] -and $item.ContainsKey('Installed')) { $item.Installed } else { $false }
        $displayText = if ($item.DisplayText) { $item.DisplayText } else { $item.ToString() }

        # Truncate to console width
        $maxWidth = [Console]::WindowWidth - 10
        if ($displayText.Length -gt $maxWidth) {
            $displayText = $displayText.Substring(0, $maxWidth - 3) + "..."
        }

        $line = "  [ ] $displayText"
        if ($isInstalled) {
            Write-Host $line -ForegroundColor DarkGray
        } else {
            Write-Host $line
        }
    }

    # After drawing, recalculate startLine (window may have scrolled)
    $endLine = [Console]::CursorTop
    $startLine = $endLine - $CurrentBatch.Count

    while (-not $done) {
        # Redraw selection list
        for ($i = 0; $i -lt $CurrentBatch.Count; $i++) {
            try {
                [Console]::SetCursorPosition(0, $startLine + $i)
            } catch {
                # If we can't set position, we're likely at buffer limit
                continue
            }

            $item = $CurrentBatch[$i]
            $isInstalled = if ($item -is [hashtable] -and $item.ContainsKey('Installed')) { $item.Installed } else { $false }
            $checkbox = if ($selectedIndexes[$i]) { "[x]" } else { "[ ]" }
            $arrow = if ($i -eq $currentIndex) { ">" } else { " " }

            $displayText = if ($item.DisplayText) { $item.DisplayText } else { $item.ToString() }

            # Truncate to console width to prevent wrapping
            $maxWidth = [Console]::WindowWidth - 10
            if ($displayText.Length -gt $maxWidth) {
                $displayText = $displayText.Substring(0, $maxWidth - 3) + "..."
            }

            # Build line
            $line = "$arrow $checkbox $displayText"

            # Pad to clear any previous longer content
            $lineWidth = [Math]::Min($line.Length + 5, [Console]::WindowWidth - 1)
            $line = $line.PadRight($lineWidth)

            # Write with color based on current selection and installed status
            if ($isInstalled) {
                [Console]::ForegroundColor = [ConsoleColor]::DarkGray
            } elseif ($i -eq $currentIndex) {
                [Console]::ForegroundColor = [ConsoleColor]::Green
            } else {
                [Console]::ForegroundColor = [ConsoleColor]::White
            }
            [Console]::Write($line)
            [Console]::ResetColor()
        }

        $key = [Console]::ReadKey($true)

        switch ($key.Key) {
            'UpArrow' {
                $currentIndex = ($currentIndex - 1 + $CurrentBatch.Count) % $CurrentBatch.Count
            }
            'DownArrow' {
                $currentIndex = ($currentIndex + 1) % $CurrentBatch.Count
            }
            'Spacebar' {
                # Only allow selection of non-installed packages
                $item = $CurrentBatch[$currentIndex]
                $isInstalled = if ($item -is [hashtable] -and $item.ContainsKey('Installed')) { $item.Installed } else { $false }
                if (-not $isInstalled) {
                    $selectedIndexes[$currentIndex] = -not $selectedIndexes[$currentIndex]
                }
            }
            'A' {
                # Select all non-installed packages only
                for ($i = 0; $i -lt $selectedIndexes.Count; $i++) {
                    $item = $CurrentBatch[$i]
                    $isInstalled = if ($item -is [hashtable] -and $item.ContainsKey('Installed')) { $item.Installed } else { $false }
                    if (-not $isInstalled) {
                        $selectedIndexes[$i] = $true
                    }
                }
            }
            'N' {
                for ($i = 0; $i -lt $selectedIndexes.Count; $i++) {
                    $selectedIndexes[$i] = $false
                }
            }
            'M' {
                if ($moreAvailable) {
                    # Move cursor past the selection list to continue normal output
                    [Console]::SetCursorPosition(0, $startLine + $CurrentBatch.Count)
                    Write-Host ""  # Add blank line after selection

                    # Add selections from this batch
                    for ($i = 0; $i -lt $CurrentBatch.Count; $i++) {
                        if ($selectedIndexes[$i]) {
                            $AllSelections.Value += $CurrentBatch[$i]
                        }
                    }
                    return @{
                        Continue = $true
                        FetchMore = $true
                    }
                }
            }
            'Enter' {
                $done = $true
            }
            'Q' {
                # Move cursor past the selection list to continue normal output
                [Console]::SetCursorPosition(0, $startLine + $CurrentBatch.Count)
                Write-Host ""  # Add blank line after selection

                return @{
                    Continue = $false
                    FetchMore = $false
                    Cancelled = $true
                }
            }
        }
    }

    # Move cursor past the selection list to continue normal output
    [Console]::SetCursorPosition(0, $startLine + $CurrentBatch.Count)
    Write-Host ""  # Add blank line after selection

    # Add final selections from this batch
    for ($i = 0; $i -lt $CurrentBatch.Count; $i++) {
        if ($selectedIndexes[$i]) {
            $AllSelections.Value += $CurrentBatch[$i]
        }
    }

    return @{
        Continue = $true
        FetchMore = $false
    }
}

function Search-Packages {
    [CmdletBinding()]
    param()

    Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  SEARCH PACKAGES                           ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    $searchTerm = Read-Host "Enter search term"

    if ([string]::IsNullOrWhiteSpace($searchTerm)) {
        Write-Host "Search cancelled - no search term provided." -ForegroundColor Yellow
        return
    }

    $searchScope = Read-Host "Search (I)nstalled or (G)lobally available packages? (I/g)"
    $searchInstalled = $true
    if ($searchScope.ToLower() -eq "g") {
        $searchInstalled = $false
        Write-Host "`nSearching globally for '$searchTerm' (installed packages highlighted in green)...`n" -ForegroundColor Cyan
    } else {
        Write-Host "`nSearching installed packages for '$searchTerm'...`n" -ForegroundColor Cyan
    }

    # Master collection for ALL package manager selections
    $script:AllPackageSelections = @()

    # Get list of installed packages for highlighting when searching globally
    $installedScoop = @()
    $installedNpm = @()
    $installedPip = @()
    $installedWinget = @()

    if (-not $searchInstalled) {
        Write-Host "  Loading installed packages for highlighting..." -ForegroundColor Gray -NoNewline

        # Get installed Scoop packages using JSON export (silent)
        try {
            # Use scoop export which outputs JSON without console headers
            $scoopExportJson = scoop export 2>&1 | Out-String | ConvertFrom-Json
            $installedScoop = @()

            # Extract package names from JSON
            if ($scoopExportJson.apps) {
                foreach ($app in $scoopExportJson.apps) {
                    if ($app.Name) {
                        $installedScoop += $app.Name
                    }
                }
            }
            Write-Host " Scoop ✓" -ForegroundColor Green -NoNewline
        } catch { }

        # Get installed npm packages
        try {
            $npmList = npm list -g --depth=0 --json 2>&1 | ConvertFrom-Json
            if ($npmList.dependencies) {
                $installedNpm = $npmList.dependencies.PSObject.Properties.Name
            }
            Write-Host " npm ✓" -ForegroundColor Green -NoNewline
        } catch { }

        # Get installed pip packages
        try {
            $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
            if ($pythonCmd) {
                $pipList = pip list --format=freeze 2>&1 | Out-String
                $installedPip = ($pipList -split "`n" | Where-Object { $_ -match '\S' } | ForEach-Object {
                    if ($_ -match '^([^=]+)') { $matches[1] }
                })
            }
            Write-Host " pip ✓" -ForegroundColor Green -NoNewline
        } catch { }

        # Get installed winget packages
        try {
            $wingetListOutput = winget list 2>&1 | Out-String
            $wingetListLines = $wingetListOutput -split "`n"
            $inTable = $false
            foreach ($line in $wingetListLines) {
                if ($line -match 'Name.*Id.*Version') {
                    $inTable = $true
                    continue
                }
                if ($inTable -and $line.Trim().Length -gt 0 -and $line -notmatch '^-+$' -and $line -notmatch '^\d+\s+(upgrade|package)') {
                    # Extract package ID (second column typically)
                    # Use more robust parsing to handle various winget output formats
                    $parts = $line -split '\s{2,}' | Where-Object { $_.Trim() -ne '' }
                    if ($parts.Count -ge 2) {
                        # Trim and normalize the package ID (remove extra whitespace, special chars)
                        $packageId = $parts[1].Trim() -replace '\s+$',''
                        if ($packageId -ne '' -and $packageId -notmatch '^[\-\\/\|]') {
                            $installedWinget += $packageId
                        }
                    }
                }
            }
            Write-Host " winget ✓" -ForegroundColor Green
        } catch { }
        Write-Host ""
    }

    # Search Scoop
    Write-Host "📦 Scoop results:" -ForegroundColor Yellow
    Write-Host ""
    try {
        if ($searchInstalled) {
            # Search installed packages only - with uninstall selection
            $scoopList = scoop list 2>&1 | Out-String
            $allLines = $scoopList -split "`n"

            # Parse into structured objects for checkbox selection
            $scoopInstalledResults = @()
            $inData = $false

            foreach ($line in $allLines) {
                if ($line -match 'Name.*Version.*Source') {
                    $inData = $true
                    continue
                }
                if ($line -match '^-+') {
                    continue
                }
                if ($inData -and $line.Trim().Length -gt 0 -and $line -match $searchTerm) {
                    # Parse: Name Version Source Updated
                    $parts = $line -split '\s+' | Where-Object { $_.Trim() -ne '' }
                    if ($parts.Count -ge 2) {
                        $pkgName = $parts[0]
                        $pkgVersion = $parts[1]
                        $pkgSource = if ($parts.Count -ge 3) { $parts[2] } else { "" }

                        $scoopInstalledResults += @{
                            Manager = "scoop"
                            Name = $pkgName
                            Version = $pkgVersion
                            Source = $pkgSource
                            DisplayText = "$pkgName - $pkgVersion ($pkgSource)"
                        }
                    }
                }
            }

            if ($scoopInstalledResults.Count -eq 0) {
                Write-Host "  No matches found" -ForegroundColor Gray
            } else {
                Write-Host "  Found $($scoopInstalledResults.Count) installed package(s) matching '$searchTerm'" -ForegroundColor Cyan
                Write-Host "  Select packages to uninstall..." -ForegroundColor Gray
                Write-Host ""

                # Use pagination for large result sets
                $batchSize = 20
                $allSelections = @()
                $allSelectionsRef = [ref]$allSelections

                if ($scoopInstalledResults.Count -gt $batchSize) {
                    $startIndex = 0
                    $batchNumber = 1
                    $continueSelecting = $true

                    while ($continueSelecting -and $startIndex -lt $scoopInstalledResults.Count) {
                        $endIndex = [Math]::Min($startIndex + $batchSize, $scoopInstalledResults.Count)
                        $currentBatch = $scoopInstalledResults[$startIndex..($endIndex - 1)]

                        $result = Show-InlineBatchSelection `
                            -CurrentBatch $currentBatch `
                            -AllSelections $allSelectionsRef `
                            -Title "SCOOP PACKAGES TO UNINSTALL (BATCH $batchNumber)" `
                            -BatchNumber $batchNumber `
                            -TotalShown $endIndex `
                            -TotalAvailable $scoopInstalledResults.Count

                        if ($result.Cancelled) {
                            $continueSelecting = $false
                            $allSelections = @()  # Clear selections on cancel
                        } elseif (-not $result.FetchMore) {
                            $continueSelecting = $false
                        }

                        $startIndex = $endIndex
                        $batchNumber++
                    }
                } else {
                    $selectedPackages = Show-CheckboxSelection -Items $scoopInstalledResults -Title "SELECT SCOOP PACKAGES TO UNINSTALL"
                    if ($selectedPackages) { $allSelections = $selectedPackages }
                }

                if ($allSelections.Count -gt 0) {
                    foreach ($pkg in $allSelections) {
                        $pkg.Action = "uninstall"
                    }
                    $script:AllPackageSelections += $allSelections
                    Write-Host "`n✅ Added $($allSelections.Count) Scoop package(s) to uninstall queue" -ForegroundColor Green
                } else {
                    Write-Host "`nNo Scoop packages selected." -ForegroundColor Yellow
                }
            }
        } else {
            # Search globally available packages
            $scoopResults = scoop search $searchTerm 2>&1 | Out-String
            if ($scoopResults -match "No matches found" -or [string]::IsNullOrWhiteSpace($scoopResults)) {
                Write-Host "  No matches found" -ForegroundColor Gray
            } else {
                # Parse scoop search output
                $scoopLines = $scoopResults -split "`n"
                $scoopSearchResults = @()

                foreach ($line in $scoopLines) {
                    # Skip header lines and empty lines
                    if ($line -match "^'.*'.*bucket" -or
                        $line -match "^Results from" -or
                        $line -match "^Name\s+Version\s+Source" -or
                        $line -match "^\*Name\s+Version\s+Source" -or
                        $line -match "^-+\s+-+\s+-+" -or
                        $line.Trim().Length -eq 0) {
                        continue
                    }

                    # Try multiple parsing patterns for scoop search output
                    $pkgName = $null
                    $pkgVersion = $null
                    $pkgBucket = $null

                    # Pattern 1: "name version (bucket)" - with parentheses
                    if ($line -match '^\s*(\S+)\s+(\S+)\s+\((\S+)\)') {
                        $pkgName = $matches[1]
                        $pkgVersion = $matches[2]
                        $pkgBucket = $matches[3]
                    }
                    # Pattern 2: "name version bucket" - space-separated (newer scoop format)
                    elseif ($line -match '^\s*(\S+)\s+(\S+)\s+(\S+)\s*$') {
                        $pkgName = $matches[1]
                        $pkgVersion = $matches[2]
                        $pkgBucket = $matches[3]
                    }

                    # If we successfully parsed a package
                    if ($pkgName) {
                        $isInstalled = $false
                        foreach ($pkg in $installedScoop) {
                            if ($pkgName -eq $pkg) {
                                $isInstalled = $true
                                break
                            }
                        }

                        $scoopSearchResults += @{
                            Manager = "Scoop"
                            Name = $pkgName
                            Version = $pkgVersion
                            Bucket = $pkgBucket
                            Installed = $isInstalled
                            DisplayText = if ($isInstalled) {
                                "$pkgName - $pkgVersion ($pkgBucket) [INSTALLED]"
                            } else {
                                "$pkgName - $pkgVersion ($pkgBucket)"
                            }
                        }
                    }
                }

                Write-Host "  Found $($scoopSearchResults.Count) package(s)" -ForegroundColor Cyan
                Write-Host ""

                # Always show results, even if all are installed
                if ($scoopSearchResults.Count -eq 0) {
                    Write-Host "  No packages found to install" -ForegroundColor Gray
                } else {
                    # Count packages available for installation (non-installed)
                    $availableCount = ($scoopSearchResults | Where-Object { -not $_.Installed }).Count
                    $installedCount = ($scoopSearchResults | Where-Object { $_.Installed }).Count

                    if ($installedCount -gt 0) {
                        Write-Host "  $installedCount package(s) already installed (shown in gray in selection menu)" -ForegroundColor Gray
                    }
                    if ($availableCount -eq 0 -and $installedCount -gt 0) {
                        Write-Host "  All matching packages are already installed!" -ForegroundColor Green
                        Write-Host "  Showing anyway for reference..." -ForegroundColor Gray
                        Write-Host ""
                    } elseif ($availableCount -gt 0) {
                        Write-Host "  $availableCount package(s) available to install" -ForegroundColor Cyan
                        Write-Host "  Select packages to install using the interactive menu..." -ForegroundColor Gray
                        Write-Host ""
                    }

                    # Show interactive selection even if all are installed (for reference)
                    $selectedPackages = Show-CheckboxSelection -Items $scoopSearchResults -Title "SELECT SCOOP PACKAGES TO INSTALL"

                    if ($selectedPackages -and $selectedPackages.Count -gt 0) {
                        # Ensure each package has Manager property for unified installation
                        foreach ($pkg in $selectedPackages) {
                            if (-not $pkg.Manager) {
                                $pkg.Manager = "scoop"
                            }
                        }
                        $script:AllPackageSelections += $selectedPackages
                        Write-Host "`n✅ Added $($selectedPackages.Count) Scoop package(s) to installation queue" -ForegroundColor Green
                    } elseif ($null -eq $selectedPackages) {
                        Write-Host "`nScoop selection cancelled." -ForegroundColor Yellow
                    } else {
                        Write-Host "`nNo Scoop packages selected." -ForegroundColor Yellow
                    }
                }
            }
        }
    } catch {
        Write-Host "  ⚠️  Scoop not found or error searching" -ForegroundColor Red
    }

    # Search npm
    Write-Host "`n📦 npm results:" -ForegroundColor Yellow
    Write-Host ""
    try {
        if ($searchInstalled) {
            # Search installed npm packages - with uninstall selection
            $npmList = npm list -g --depth=0 --json 2>&1 | Out-String
            $npmInstalledResults = @()

            try {
                $npmData = $npmList | ConvertFrom-Json
                if ($npmData.dependencies) {
                    foreach ($pkg in $npmData.dependencies.PSObject.Properties) {
                        if ($pkg.Name -match $searchTerm) {
                            $npmInstalledResults += @{
                                Manager = "npm"
                                Name = $pkg.Name
                                Version = $pkg.Value.version
                                DisplayText = "$($pkg.Name) - $($pkg.Value.version)"
                            }
                        }
                    }
                }
            } catch {
                # Fallback to text parsing if JSON fails
                $matchedLines = $npmList -split "`n" | Where-Object { $_ -match $searchTerm -and $_ -match '@' }
                foreach ($line in $matchedLines) {
                    if ($line -match '[\+\`]\-\-\s*(@?[^@]+)@(.+)$') {
                        $npmInstalledResults += @{
                            Manager = "npm"
                            Name = $matches[1].Trim()
                            Version = $matches[2].Trim()
                            DisplayText = "$($matches[1].Trim()) - $($matches[2].Trim())"
                        }
                    }
                }
            }

            if ($npmInstalledResults.Count -eq 0) {
                Write-Host "  No matches found" -ForegroundColor Gray
            } else {
                Write-Host "  Found $($npmInstalledResults.Count) installed package(s) matching '$searchTerm'" -ForegroundColor Cyan
                Write-Host "  Select packages to uninstall..." -ForegroundColor Gray
                Write-Host ""

                # Use pagination for large result sets
                $batchSize = 20
                $allSelections = @()
                $allSelectionsRef = [ref]$allSelections

                if ($npmInstalledResults.Count -gt $batchSize) {
                    $startIndex = 0
                    $batchNumber = 1
                    $continueSelecting = $true

                    while ($continueSelecting -and $startIndex -lt $npmInstalledResults.Count) {
                        $endIndex = [Math]::Min($startIndex + $batchSize, $npmInstalledResults.Count)
                        $currentBatch = $npmInstalledResults[$startIndex..($endIndex - 1)]

                        $result = Show-InlineBatchSelection `
                            -CurrentBatch $currentBatch `
                            -AllSelections $allSelectionsRef `
                            -Title "NPM PACKAGES TO UNINSTALL (BATCH $batchNumber)" `
                            -BatchNumber $batchNumber `
                            -TotalShown $endIndex `
                            -TotalAvailable $npmInstalledResults.Count

                        if ($result.Cancelled) {
                            $continueSelecting = $false
                            $allSelections = @()
                        } elseif (-not $result.FetchMore) {
                            $continueSelecting = $false
                        }

                        $startIndex = $endIndex
                        $batchNumber++
                    }
                } else {
                    $selectedPackages = Show-CheckboxSelection -Items $npmInstalledResults -Title "SELECT NPM PACKAGES TO UNINSTALL"
                    if ($selectedPackages) { $allSelections = $selectedPackages }
                }

                if ($allSelections.Count -gt 0) {
                    foreach ($pkg in $allSelections) {
                        $pkg.Action = "uninstall"
                    }
                    $script:AllPackageSelections += $allSelections
                    Write-Host "`n✅ Added $($allSelections.Count) npm package(s) to uninstall queue" -ForegroundColor Green
                } else {
                    Write-Host "`nNo npm packages selected." -ForegroundColor Yellow
                }
            }
        } else {
            # Search globally available npm packages by name
            Write-Host "  Searching npm registry for '$searchTerm'..." -ForegroundColor Gray

            try {
                # Load local npm package list (3.6M+ packages from npm registry)
                $packageListFile = Join-Path $PSScriptRoot "resources\npm-packages.json"

                # Download package list if it doesn't exist
                if (-not (Test-Path $packageListFile)) {
                    Write-Host "  Package list not found. Download now? (90MB) (Y/n)" -ForegroundColor Yellow
                    $downloadResponse = Read-Host "  "

                    if ($downloadResponse -notmatch '^[Nn]') {
                        Write-Host "  Downloading package list (90MB)..." -ForegroundColor Cyan

                        # Ensure resources directory exists
                        $resourcesDir = Join-Path $PSScriptRoot "resources"
                        if (-not (Test-Path $resourcesDir)) {
                            New-Item -ItemType Directory -Path $resourcesDir -Force | Out-Null
                        }

                        try {
                            $packageListUrl = "https://raw.githubusercontent.com/nice-registry/all-the-package-names/master/names.json"
                            Invoke-WebRequest -Uri $packageListUrl -OutFile $packageListFile -ErrorAction Stop
                            Write-Host "  Package list downloaded successfully!" -ForegroundColor Green
                            Write-Host ""
                        }
                        catch {
                            Write-Host "  Error: Failed to download package list." -ForegroundColor Red
                            Write-Host "  $_" -ForegroundColor Red
                            throw "Download failed"
                        }
                    } else {
                        Write-Host "  Skipping download. Falling back to npm search command..." -ForegroundColor Yellow
                        throw "Package list download declined"
                    }
                }

                # Check if package list needs updating (older than 24 hours)
                $fileAge = (Get-Date) - (Get-Item $packageListFile).LastWriteTime
                if ($fileAge.TotalHours -gt 24) {
                    $days = [int]$fileAge.TotalDays
                    $hours = [int]$fileAge.TotalHours
                    $ageText = if ($days -gt 0) { "$days day(s)" } else { "$hours hour(s)" }

                    Write-Host "  Package list is $ageText old." -ForegroundColor Yellow
                    $updateResponse = Read-Host "  Update now? (Y/n)"

                    if ($updateResponse -notmatch '^[Nn]') {
                        Write-Host "  Downloading updated package list (90MB)..." -ForegroundColor Cyan
                        try {
                            $packageListUrl = "https://raw.githubusercontent.com/nice-registry/all-the-package-names/master/names.json"
                            Invoke-WebRequest -Uri $packageListUrl -OutFile $packageListFile -ErrorAction Stop
                            Write-Host "  Package list updated successfully!" -ForegroundColor Green
                        }
                        catch {
                            Write-Host "  Warning: Failed to update package list. Using existing version." -ForegroundColor Yellow
                        }
                    }
                    Write-Host ""
                }

                # Load and cache the package list (global variable for performance)
                if (-not $global:npmPackageCache) {
                    Write-Host "  Loading package database (one-time per session)..." -ForegroundColor Gray
                    $global:npmPackageCache = Get-Content $packageListFile -Raw | ConvertFrom-Json
                }
                $allPackages = $global:npmPackageCache

                # Filter packages by name (case-insensitive substring match)
                $matchedNamesAll = $allPackages | Where-Object { $_ -like "*$searchTerm*" }

                # Sort by relevance: shorter names first, then alphabetical
                # This prioritizes exact matches and similar names
                $sortedMatches = $matchedNamesAll | Sort-Object { $_.Length }, { $_ }

                # Prioritize non-scoped packages (without @) for better visibility
                $nonScoped = $sortedMatches | Where-Object { -not $_.StartsWith('@') } | Select-Object -First 20
                $scoped = $sortedMatches | Where-Object { $_.StartsWith('@') } | Select-Object -First (20 - $nonScoped.Count)
                $matchedNames = @($nonScoped) + @($scoped)

                if ($sortedMatches.Count -eq 0) {
                    Write-Host "  No matches found" -ForegroundColor Gray
                } else {
                    # Show total matches found
                    Write-Host "  Found $($sortedMatches.Count) matching packages" -ForegroundColor Cyan
                    Write-Host ""

                    # Track all selections across batches
                    $allSelections = @()
                    $allSelectionsRef = [ref]$allSelections

                    # Fetch and display metadata in batches with inline selection
                    $batchSize = 20
                    $startIndex = 0
                    $batchNumber = 1
                    $continueSearching = $true

                    while ($continueSearching -and $startIndex -lt $sortedMatches.Count) {
                        # Get next batch (prioritize non-scoped first)
                        $remainingMatches = $sortedMatches | Select-Object -Skip $startIndex
                        $nonScoped = $remainingMatches | Where-Object { -not $_.StartsWith('@') } | Select-Object -First $batchSize
                        $scoped = $remainingMatches | Where-Object { $_.StartsWith('@') } | Select-Object -First ($batchSize - $nonScoped.Count)
                        $currentBatch = @($nonScoped) + @($scoped)

                        if ($currentBatch.Count -eq 0) { break }

                        Write-Host "  Fetching metadata for batch $batchNumber..." -ForegroundColor Gray

                        # Fetch package metadata in parallel using runspaces for better performance
                        $runspacePool = [runspacefactory]::CreateRunspacePool(1, 20)
                        $runspacePool.Open()

                        $runspaces = @()
                        foreach ($pkgName in $currentBatch) {
                            $powershell = [powershell]::Create()
                            $powershell.RunspacePool = $runspacePool

                            [void]$powershell.AddScript({
                                param($name, $url)
                                try {
                                    $data = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop -TimeoutSec 3
                                    return @{
                                        name = $name
                                        version = $data.'dist-tags'.latest
                                        description = $data.description
                                        success = $true
                                    }
                                } catch {
                                    return @{
                                        name = $name
                                        success = $false
                                    }
                                }
                            })
                            [void]$powershell.AddArgument($pkgName)
                            [void]$powershell.AddArgument("https://registry.npmjs.org/$pkgName")

                            $runspaces += @{
                                Pipe = $powershell
                                Status = $powershell.BeginInvoke()
                                PackageName = $pkgName
                            }
                        }

                        # Wait for all runspaces to complete and collect results
                        $results = @{}
                        foreach ($runspace in $runspaces) {
                            $result = $runspace.Pipe.EndInvoke($runspace.Status)
                            if ($result) {
                                $results[$result.name] = $result
                            }
                            $runspace.Pipe.Dispose()
                        }

                        $runspacePool.Close()
                        $runspacePool.Dispose()

                        # Build batch of package objects for inline selection
                        $batchPackages = @()
                        foreach ($pkgName in $currentBatch) {
                            $result = $results[$pkgName]
                            $isInstalled = $installedNpm -contains $pkgName

                            if ($result -and $result.success) {
                                $version = $result.version
                                $description = if ($result.description) { $result.description } else { "" }

                                # Truncate description for display
                                $descriptionShort = if ($description.Length -gt 40) { $description.Substring(0, 37) + "..." } else { $description }

                                $batchPackages += @{
                                    Manager = "npm"
                                    Name = $pkgName
                                    Version = $version
                                    Description = $description
                                    Installed = $isInstalled
                                    DisplayText = if ($isInstalled) {
                                        "$pkgName - $version - $descriptionShort [INSTALLED]"
                                    } else {
                                        "$pkgName - $version - $descriptionShort"
                                    }
                                }
                            }
                        }

                        $startIndex += $currentBatch.Count

                        # Show inline batch selection if we have packages
                        if ($batchPackages.Count -gt 0) {
                            $result = Show-InlineBatchSelection `
                                -CurrentBatch $batchPackages `
                                -AllSelections $allSelectionsRef `
                                -Title "SELECT NPM PACKAGES (BATCH $batchNumber)" `
                                -BatchNumber $batchNumber `
                                -TotalShown $startIndex `
                                -TotalAvailable $sortedMatches.Count

                            if ($result.Cancelled) {
                                $continueSearching = $false
                            } elseif (-not $result.FetchMore) {
                                $continueSearching = $false
                            }
                        }

                        $batchNumber++
                    }

                    # Add selections to master collection for later installation
                    if ($allSelections.Count -gt 0) {
                        # Ensure each package has Manager property for unified installation
                        foreach ($pkg in $allSelections) {
                            if (-not $pkg.Manager) {
                                $pkg.Manager = "npm"
                            }
                        }
                        $script:AllPackageSelections += $allSelections
                        Write-Host "`n✅ Added $($allSelections.Count) npm package(s) to installation queue" -ForegroundColor Green
                    } elseif (-not $result.Cancelled) {
                        Write-Host "`nNo npm packages selected." -ForegroundColor Yellow
                    }
                }
            }
            catch {
                # Fallback to npm search command if API fails
                Write-Host "  API search failed, trying npm search command..." -ForegroundColor Gray
                $npmSearch = npm search $searchTerm 2>&1 | Out-String

                if ($npmSearch -match "No matches found" -or [string]::IsNullOrWhiteSpace($npmSearch)) {
                    Write-Host "  No matches found" -ForegroundColor Gray
                } else {
                    $npmLines = $npmSearch -split "`n"
                    $headerShown = $false

                    foreach ($line in $npmLines) {
                        if ($line.Trim().Length -eq 0) { continue }

                        # Show header line
                        if ($line -match '^NAME' -or $line -match '^=+') {
                            Write-Host $line
                            $headerShown = $true
                            continue
                        }

                        # Check if this package is installed
                        if ($headerShown) {
                            $isInstalled = $false
                            # Extract package name (first column)
                            if ($line -match '^\s*(\S+)') {
                                $pkgName = $matches[1]
                                if ($installedNpm -contains $pkgName) {
                                    $isInstalled = $true
                                }
                            }

                            if ($isInstalled) {
                                Write-Host $line -ForegroundColor Green
                            } else {
                                Write-Host $line
                            }
                        }
                    }
                }
            }
        }
    } catch {
        Write-Host "  ⚠️  npm not found or error searching" -ForegroundColor Red
    }

    # Search pip
    Write-Host "`n📦 pip results:" -ForegroundColor Yellow
    Write-Host ""
    try {
        # Check if Python is available
        $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
        if (-not $pythonCmd) {
            Write-Host "  ⚠️  Python not found" -ForegroundColor Red
        } else {
            if ($searchInstalled) {
                # Search installed pip packages - with uninstall selection
                $pipList = pip list 2>&1 | Out-String
                $pipLines = $pipList -split "`n"
                $pipInstalledResults = @()
                $inData = $false

                foreach ($line in $pipLines) {
                    if ($line -match '^Package\s+Version') {
                        $inData = $true
                        continue
                    }
                    if ($line -match '^-+\s+-+') {
                        continue
                    }
                    if ($inData -and $line -match $searchTerm -and $line.Trim().Length -gt 0) {
                        # Parse: Package Version
                        $parts = $line -split '\s+' | Where-Object { $_.Trim() -ne '' }
                        if ($parts.Count -ge 2) {
                            $pipInstalledResults += @{
                                Manager = "pip"
                                Name = $parts[0]
                                Version = $parts[1]
                                DisplayText = "$($parts[0]) - $($parts[1])"
                            }
                        }
                    }
                }

                if ($pipInstalledResults.Count -eq 0) {
                    Write-Host "  No matches found" -ForegroundColor Gray
                } else {
                    Write-Host "  Found $($pipInstalledResults.Count) installed package(s) matching '$searchTerm'" -ForegroundColor Cyan
                    Write-Host "  Select packages to uninstall..." -ForegroundColor Gray
                    Write-Host ""

                    # Use pagination for large result sets
                    $batchSize = 20
                    $allSelections = @()
                    $allSelectionsRef = [ref]$allSelections

                    if ($pipInstalledResults.Count -gt $batchSize) {
                        $startIndex = 0
                        $batchNumber = 1
                        $continueSelecting = $true

                        while ($continueSelecting -and $startIndex -lt $pipInstalledResults.Count) {
                            $endIndex = [Math]::Min($startIndex + $batchSize, $pipInstalledResults.Count)
                            $currentBatch = $pipInstalledResults[$startIndex..($endIndex - 1)]

                            $result = Show-InlineBatchSelection `
                                -CurrentBatch $currentBatch `
                                -AllSelections $allSelectionsRef `
                                -Title "PIP PACKAGES TO UNINSTALL (BATCH $batchNumber)" `
                                -BatchNumber $batchNumber `
                                -TotalShown $endIndex `
                                -TotalAvailable $pipInstalledResults.Count

                            if ($result.Cancelled) {
                                $continueSelecting = $false
                                $allSelections = @()
                            } elseif (-not $result.FetchMore) {
                                $continueSelecting = $false
                            }

                            $startIndex = $endIndex
                            $batchNumber++
                        }
                    } else {
                        $selectedPackages = Show-CheckboxSelection -Items $pipInstalledResults -Title "SELECT PIP PACKAGES TO UNINSTALL"
                        if ($selectedPackages) { $allSelections = $selectedPackages }
                    }

                    if ($allSelections.Count -gt 0) {
                        foreach ($pkg in $allSelections) {
                            $pkg.Action = "uninstall"
                        }
                        $script:AllPackageSelections += $allSelections
                        Write-Host "`n✅ Added $($allSelections.Count) pip package(s) to uninstall queue" -ForegroundColor Green
                    } else {
                        Write-Host "`nNo pip packages selected." -ForegroundColor Yellow
                    }
                }
            } else {
                # Use PyPI JSON API to search (pip search was disabled in 2021)
                Write-Host "  Searching PyPI for '$searchTerm'..." -ForegroundColor Gray
                try {
                    # Collect packages for potential installation
                    $pipSearchResults = @()

                    # Use PyPI's simple search via web scraping alternative
                    $searchUrl = "https://pypi.org/search/?q=$searchTerm"
                    Write-Host "  Note: Using web search. For more results visit: $searchUrl" -ForegroundColor Cyan
                    Write-Host ""

                    # Try to get exact package info if searchTerm looks like a package name
                    if ($searchTerm -match '^[a-zA-Z0-9_-]+$') {
                        $foundExact = $false
                        try {
                            $response = Invoke-RestMethod -Uri "https://pypi.org/pypi/$searchTerm/json" -ErrorAction SilentlyContinue -TimeoutSec 5
                            if ($response) {
                                $foundExact = $true
                                $pkgInfo = $response.info
                                $isInstalled = pip list 2>&1 | Select-String -Pattern "^$searchTerm\s" -Quiet

                                $installStatus = if ($isInstalled) { " [INSTALLED]" } else { "" }
                                $color = if ($isInstalled) { "Green" } else { "White" }

                                # Add to results collection
                                $pipSearchResults += @{
                                    Manager = "pip"
                                    Name = $pkgInfo.name
                                    Version = $pkgInfo.version
                                    Summary = $pkgInfo.summary
                                    Installed = $isInstalled
                                    DisplayText = if ($isInstalled) {
                                        "$($pkgInfo.name) - $($pkgInfo.version) - $($pkgInfo.summary) [INSTALLED]"
                                    } else {
                                        "$($pkgInfo.name) - $($pkgInfo.version) - $($pkgInfo.summary)"
                                    }
                                }

                                Write-Host "  Package: $($pkgInfo.name)$installStatus" -ForegroundColor $color
                                Write-Host "  Version: $($pkgInfo.version)" -ForegroundColor Gray
                                Write-Host "  Summary: $($pkgInfo.summary)" -ForegroundColor Gray
                                if ($pkgInfo.home_page) {
                                    Write-Host "  Homepage: $($pkgInfo.home_page)" -ForegroundColor Gray
                                }
                                Write-Host ""
                            }
                        } catch {
                            # Exact package not found, try common variations
                            $variations = @("py$searchTerm", "${searchTerm}svg", "python-$searchTerm")
                            foreach ($variant in $variations) {
                                try {
                                    $response = Invoke-RestMethod -Uri "https://pypi.org/pypi/$variant/json" -ErrorAction SilentlyContinue -TimeoutSec 3
                                    if ($response) {
                                        $foundExact = $true
                                        $pkgInfo = $response.info
                                        $isInstalled = pip list 2>&1 | Select-String -Pattern "^$variant\s" -Quiet

                                        $installStatus = if ($isInstalled) { " [INSTALLED]" } else { "" }
                                        $color = if ($isInstalled) { "Green" } else { "White" }

                                        # Add to results collection
                                        $pipSearchResults += @{
                                            Manager = "pip"
                                            Name = $pkgInfo.name
                                            Version = $pkgInfo.version
                                            Summary = $pkgInfo.summary
                                            Installed = $isInstalled
                                            DisplayText = if ($isInstalled) {
                                                "$($pkgInfo.name) - $($pkgInfo.version) - $($pkgInfo.summary) [INSTALLED]"
                                            } else {
                                                "$($pkgInfo.name) - $($pkgInfo.version) - $($pkgInfo.summary)"
                                            }
                                        }

                                        Write-Host "  Found similar package:" -ForegroundColor Cyan
                                        Write-Host "  Package: $($pkgInfo.name)$installStatus" -ForegroundColor $color
                                        Write-Host "  Version: $($pkgInfo.version)" -ForegroundColor Gray
                                        Write-Host "  Summary: $($pkgInfo.summary)" -ForegroundColor Gray
                                        if ($pkgInfo.home_page) {
                                            Write-Host "  Homepage: $($pkgInfo.home_page)" -ForegroundColor Gray
                                        }
                                        Write-Host ""
                                    }
                                } catch {
                                    # Continue to next variation
                                }
                            }
                        }

                        if (-not $foundExact) {
                            # No exact match or variations found
                            Write-Host "  No exact match for '$searchTerm' on PyPI." -ForegroundColor Yellow
                            Write-Host "  💡 Try: 'py$searchTerm' or '${searchTerm}svg' or search on PyPI web" -ForegroundColor Cyan
                            Write-Host ""
                            Write-Host "  Showing installed packages matching '$searchTerm':" -ForegroundColor Gray
                            Write-Host ""

                            $pipList = pip list 2>&1 | Out-String
                            $pipLines = $pipList -split "`n"
                            $matchedLines = @()
                            $headerLines = @()

                            foreach ($line in $pipLines) {
                                if ($line -match '^Package\s+Version' -or $line -match '^-+\s+-+') {
                                    $headerLines += $line
                                } elseif ($line -match $searchTerm -and $line.Trim().Length -gt 0 -and $line -notmatch '^\[notice\]') {
                                    $matchedLines += $line
                                }
                            }

                            if ($matchedLines.Count -eq 0) {
                                Write-Host "  No matches found in installed packages" -ForegroundColor Gray
                                Write-Host "  💡 Try searching on PyPI: $searchUrl" -ForegroundColor Cyan
                            } else {
                                $headerLines | ForEach-Object { Write-Host $_ }
                                $matchedLines | Sort-Object | ForEach-Object {
                                    Write-Host $_ -ForegroundColor Green
                                }
                            }
                        }
                    } else {
                        # For non-exact searches, just show the web link and installed matches
                        Write-Host "  For multiple results, visit: $searchUrl" -ForegroundColor Cyan
                        Write-Host ""
                        Write-Host "  Showing installed packages matching '$searchTerm':" -ForegroundColor Gray
                        Write-Host ""

                        $pipList = pip list 2>&1 | Out-String
                        $pipLines = $pipList -split "`n"
                        $matchedLines = @()
                        $headerLines = @()

                        foreach ($line in $pipLines) {
                            if ($line -match '^Package\s+Version' -or $line -match '^-+\s+-+') {
                                $headerLines += $line
                            } elseif ($line -match $searchTerm -and $line.Trim().Length -gt 0 -and $line -notmatch '^\[notice\]') {
                                $matchedLines += $line
                            }
                        }

                        if ($matchedLines.Count -eq 0) {
                            Write-Host "  No matches found in installed packages" -ForegroundColor Gray
                        } else {
                            $headerLines | ForEach-Object { Write-Host $_ }
                            $matchedLines | Sort-Object | ForEach-Object {
                                Write-Host $_ -ForegroundColor Green
                            }
                        }
                    }

                    # Offer to install packages from search results
                    if ($pipSearchResults.Count -eq 0) {
                        Write-Host "  No packages found to install" -ForegroundColor Gray
                    } else {
                        # Count packages available for installation (non-installed)
                        $availableCount = ($pipSearchResults | Where-Object { -not $_.Installed }).Count
                        $installedCount = ($pipSearchResults | Where-Object { $_.Installed }).Count

                        if ($installedCount -gt 0) {
                            Write-Host "  $installedCount package(s) already installed (shown in gray in selection menu)" -ForegroundColor Gray
                        }
                        if ($availableCount -eq 0) {
                            Write-Host "  All matching packages are already installed!" -ForegroundColor Green
                        } else {
                            Write-Host ""
                            Write-Host "  $availableCount package(s) available to install" -ForegroundColor Cyan
                            Write-Host "  Select packages to install using the interactive menu..." -ForegroundColor Gray
                            Write-Host ""

                            # Show interactive selection (includes all packages, but installed ones are unselectable)
                            $selectedPackages = Show-CheckboxSelection -Items $pipSearchResults -Title "SELECT PIP PACKAGES TO INSTALL"

                            if ($selectedPackages -and $selectedPackages.Count -gt 0) {
                                # Ensure each package has Manager property for unified installation
                                foreach ($pkg in $selectedPackages) {
                                    if (-not $pkg.Manager) {
                                        $pkg.Manager = "pip"
                                    }
                                }
                                $script:AllPackageSelections += $selectedPackages
                                Write-Host "`n✅ Added $($selectedPackages.Count) pip package(s) to installation queue" -ForegroundColor Green
                            } elseif ($null -eq $selectedPackages) {
                                Write-Host "`nPip selection cancelled." -ForegroundColor Yellow
                            } else {
                                Write-Host "`nNo pip packages selected." -ForegroundColor Yellow
                            }
                        }
                    }
                } catch {
                    Write-Host "  ⚠️  Error searching PyPI. Visit https://pypi.org/search/?q=$searchTerm" -ForegroundColor Yellow
                }
            }
        }
    } catch {
        Write-Host "  ⚠️  pip not found or error searching" -ForegroundColor Red
    }

    # Search winget
    Write-Host "`n📦 winget results:" -ForegroundColor Yellow
    Write-Host ""
    try {
        if ($searchInstalled) {
            # Search installed packages only
            $wingetListOutput = winget list $searchTerm 2>&1 | Out-String
        } else {
            # Search globally available packages
            $wingetListOutput = winget search $searchTerm 2>&1 | Out-String
        }

        # Filter out progress indicators
        $cleanedLines = $wingetListOutput -split "`n" | Where-Object {
            $line = $_
            if (-not $line.Trim()) { return $false }
            if ($line -match '^\s*[\-\\/\|]\s*$') { return $false }
            if ($line.Trim() -match '^[\-\\/\|]$') { return $false }
            return $true
        }

        if ($wingetListOutput -match "No package found" -or $wingetListOutput -match "No installed package found" -or $cleanedLines.Count -eq 0) {
            Write-Host "  No matches found" -ForegroundColor Gray
        } else {
            # Parse and sort winget output
            $headerLine = $null
            $separatorLine = $null
            $dataLines = @()
            $footerLines = @()
            $inData = $false

            foreach ($line in $cleanedLines) {
                # Detect header line (contains "Name" and "Id" and "Version")
                if ($line -match 'Name.*Id.*Version' -and -not $headerLine) {
                    $headerLine = $line
                    continue
                }
                # Detect separator line (dashes)
                elseif ($line -match '^-+' -and $headerLine -and -not $separatorLine) {
                    $separatorLine = $line
                    $inData = $true
                    continue
                }
                # Detect footer (upgrade count or other summary)
                elseif ($line -match '^\d+\s+(package|upgrade|installed|available)' -or $line -match 'The following packages') {
                    $inData = $false
                    $footerLines += $line
                }
                # Data lines
                elseif ($inData) {
                    $dataLines += $line
                }
                # Other lines (pre-header or post-footer)
                else {
                    $footerLines += $line
                }
            }

            # Parse data lines into structured objects using header column positions
            $wingetSearchResults = @()
            $sortedDataLines = $dataLines | Sort-Object

            # Determine column positions from header line
            $namePos = $headerLine.IndexOf("Name")
            $idPos = $headerLine.IndexOf("Id")
            $versionPos = $headerLine.IndexOf("Version")

            foreach ($line in $sortedDataLines) {
                try {
                    # Use header positions to extract columns (more reliable than splitting on spaces)
                    # Extract Name (from start to Id column)
                    $packageName = if ($idPos -gt $namePos) {
                        $line.Substring($namePos, $idPos - $namePos).Trim()
                    } else { "" }

                    # Extract Id (from Id column to Version column)
                    $packageId = if ($versionPos -gt $idPos) {
                        $line.Substring($idPos, $versionPos - $idPos).Trim()
                    } else { "" }

                    # Extract Version (from Version column to end, or to Match column if it exists)
                    $matchPos = $headerLine.IndexOf("Match")
                    $sourcePos = $headerLine.IndexOf("Source")
                    $versionEndPos = if ($matchPos -gt $versionPos) {
                        $matchPos
                    } elseif ($sourcePos -gt $versionPos) {
                        $sourcePos
                    } else {
                        $line.Length
                    }

                    $packageVersion = if ($versionEndPos -gt $versionPos -and $versionPos -lt $line.Length) {
                        $line.Substring($versionPos, [Math]::Min($versionEndPos - $versionPos, $line.Length - $versionPos)).Trim()
                    } else { "" }

                    # Only add if we have at minimum a package ID
                    if ($packageId -ne "") {
                        # Robust comparison for package IDs
                        $isInstalled = ($installedWinget | Where-Object { $_ -eq $packageId } | Select-Object -First 1) -ne $null

                        $wingetSearchResults += @{
                            Manager = "winget"
                            Name = $packageId
                            DisplayName = $packageName
                            Version = $packageVersion
                            Installed = $isInstalled
                            DisplayText = if ($isInstalled) {
                                "$packageName - $packageId ($packageVersion) [INSTALLED]"
                            } else {
                                "$packageName - $packageId ($packageVersion)"
                            }
                        }
                    }
                } catch {
                    # Skip lines that can't be parsed
                    continue
                }
            }

            if ($searchInstalled) {
                # Installed search - with uninstall selection and pagination
                if ($wingetSearchResults.Count -eq 0) {
                    Write-Host "  No matches found" -ForegroundColor Gray
                } else {
                    Write-Host "  Found $($wingetSearchResults.Count) installed package(s) matching '$searchTerm'" -ForegroundColor Cyan
                    Write-Host "  Select packages to uninstall..." -ForegroundColor Gray
                    Write-Host ""

                    # Use pagination for large result sets (>20 items)
                    $batchSize = 20
                    $allSelections = @()
                    $allSelectionsRef = [ref]$allSelections

                    if ($wingetSearchResults.Count -gt $batchSize) {
                        $startIndex = 0
                        $batchNumber = 1
                        $continueSelecting = $true

                        while ($continueSelecting -and $startIndex -lt $wingetSearchResults.Count) {
                            $endIndex = [Math]::Min($startIndex + $batchSize, $wingetSearchResults.Count)
                            $currentBatch = $wingetSearchResults[$startIndex..($endIndex - 1)]

                            if ($currentBatch.Count -eq 0) { break }

                            $result = Show-InlineBatchSelection `
                                -CurrentBatch $currentBatch `
                                -AllSelections $allSelectionsRef `
                                -Title "SELECT WINGET PACKAGES TO UNINSTALL (BATCH $batchNumber)" `
                                -BatchNumber $batchNumber `
                                -TotalShown $endIndex `
                                -TotalAvailable $wingetSearchResults.Count

                            if ($result.Cancelled) {
                                $continueSelecting = $false
                                $allSelections = @()  # Clear selections on cancel
                            } elseif (-not $result.FetchMore) {
                                $continueSelecting = $false
                            }

                            $startIndex = $endIndex
                            $batchNumber++
                        }
                    } else {
                        # Small list - use simple checkbox selection
                        $selectedPackages = Show-CheckboxSelection -Items $wingetSearchResults -Title "SELECT WINGET PACKAGES TO UNINSTALL"
                        if ($selectedPackages) {
                            $allSelections = $selectedPackages
                        }
                    }

                    if ($allSelections -and $allSelections.Count -gt 0) {
                        foreach ($pkg in $allSelections) {
                            $pkg.Action = "uninstall"
                        }
                        $script:AllPackageSelections += $allSelections
                        Write-Host "`n✅ Added $($allSelections.Count) winget package(s) to uninstall queue" -ForegroundColor Green
                    } elseif ($null -eq $allSelections -or $allSelections.Count -eq 0) {
                        Write-Host "`nNo winget packages selected." -ForegroundColor Yellow
                    }
                }
            } else {
                # Display with highlighting, then offer selection with pagination
                Write-Host "  Found $($wingetSearchResults.Count) package(s)" -ForegroundColor Cyan
                Write-Host ""

                # Offer to install packages from search results with pagination
                if ($wingetSearchResults.Count -eq 0) {
                    Write-Host "  No packages found to install" -ForegroundColor Gray
                } else {
                    # Count packages available for installation (non-installed)
                    $availableCount = ($wingetSearchResults | Where-Object { -not $_.Installed }).Count
                    $installedCount = ($wingetSearchResults | Where-Object { $_.Installed }).Count

                    if ($installedCount -gt 0) {
                        Write-Host "  $installedCount package(s) already installed (shown in gray in selection menu)" -ForegroundColor Gray
                    }
                    if ($availableCount -eq 0) {
                        Write-Host "  All matching packages are already installed!" -ForegroundColor Green
                    } else {
                        Write-Host "  $availableCount package(s) available to install" -ForegroundColor Cyan
                        Write-Host "  Displaying results in batches for easier browsing..." -ForegroundColor Gray
                        Write-Host ""

                        # Use pagination for large result sets
                        $batchSize = 20
                        $startIndex = 0
                        $allSelections = @()
                        $allSelectionsRef = [ref]$allSelections
                        $continueSearching = $true
                        $batchNumber = 1

                        while ($continueSearching -and $startIndex -lt $wingetSearchResults.Count) {
                            $endIndex = [Math]::Min($startIndex + $batchSize, $wingetSearchResults.Count)
                            $currentBatch = $wingetSearchResults[$startIndex..($endIndex - 1)]

                            if ($currentBatch.Count -eq 0) { break }

                            # Show inline batch selection
                            $result = Show-InlineBatchSelection `
                                -CurrentBatch $currentBatch `
                                -AllSelections $allSelectionsRef `
                                -Title "SELECT WINGET PACKAGES (BATCH $batchNumber)" `
                                -BatchNumber $batchNumber `
                                -TotalShown $endIndex `
                                -TotalAvailable $wingetSearchResults.Count

                            if ($result.Cancelled) {
                                $continueSearching = $false
                            } elseif (-not $result.FetchMore) {
                                $continueSearching = $false
                            }

                            $startIndex = $endIndex
                            $batchNumber++
                        }

                        # Add selections to master collection for later installation
                        if ($allSelections.Count -gt 0) {
                            # Ensure each package has Manager property for unified installation
                            foreach ($pkg in $allSelections) {
                                if (-not $pkg.Manager) {
                                    $pkg.Manager = "winget"
                                }
                            }
                            $script:AllPackageSelections += $allSelections
                            Write-Host "`n✅ Added $($allSelections.Count) winget package(s) to installation queue" -ForegroundColor Green
                        } elseif (-not $result.Cancelled) {
                            Write-Host "`nNo winget packages selected." -ForegroundColor Yellow
                        }
                    }
                }
            }
        }
    } catch {
        Write-Host "  ⚠️  winget not found or error searching" -ForegroundColor Red
    }

    # ═══════════════════════════════════════════════════════════════
    # PACKAGE ACTION SUMMARY & UNIFIED EXECUTION
    # ═══════════════════════════════════════════════════════════════

    Write-Host ""

    # Check if any packages were selected across all package managers
    if ($script:AllPackageSelections.Count -eq 0) {
        Write-Host "No packages selected." -ForegroundColor Gray
        return
    }

    # Separate packages by action
    $packagesToInstall = @($script:AllPackageSelections | Where-Object { $_.Action -ne "uninstall" })
    $packagesToUninstall = @($script:AllPackageSelections | Where-Object { $_.Action -eq "uninstall" })

    # Display summary
    if ($packagesToInstall.Count -gt 0) {
        Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║  PACKAGES TO INSTALL                       ║" -ForegroundColor Cyan
        Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Cyan

        $byManager = $packagesToInstall | Group-Object Manager
        Write-Host "Total: $($packagesToInstall.Count) package(s) to install`n" -ForegroundColor White

        foreach ($group in $byManager) {
            $managerName = $group.Name.ToUpper()
            Write-Host "  $managerName ($($group.Count) package(s)):" -ForegroundColor Yellow
            foreach ($pkg in $group.Group) {
                if ($pkg.Version) {
                    Write-Host "    • $($pkg.Name) ($($pkg.Version))" -ForegroundColor White
                } else {
                    Write-Host "    • $($pkg.Name)" -ForegroundColor White
                }
            }
            Write-Host ""
        }
    }

    if ($packagesToUninstall.Count -gt 0) {
        Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Red
        Write-Host "║  PACKAGES TO UNINSTALL                     ║" -ForegroundColor Red
        Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Red

        $byManager = $packagesToUninstall | Group-Object Manager
        Write-Host "Total: $($packagesToUninstall.Count) package(s) to uninstall`n" -ForegroundColor White

        foreach ($group in $byManager) {
            $managerName = $group.Name.ToUpper()
            Write-Host "  $managerName ($($group.Count) package(s)):" -ForegroundColor Yellow
            foreach ($pkg in $group.Group) {
                if ($pkg.Version) {
                    Write-Host "    • $($pkg.Name) ($($pkg.Version))" -ForegroundColor White
                } else {
                    Write-Host "    • $($pkg.Name)" -ForegroundColor White
                }
            }
            Write-Host ""
        }
    }

    # Confirm action - with extra confirmation for uninstalls
    if ($packagesToUninstall.Count -gt 0) {
        # Warning banner for uninstalls
        Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
        Write-Host "║                        ⚠️  WARNING ⚠️                          ║" -ForegroundColor Red
        $uninstallMsg = "  You are about to UNINSTALL $($packagesToUninstall.Count) package(s)."
        Write-Host "║$($uninstallMsg.PadRight(64))║" -ForegroundColor Red
        Write-Host "║  This action CANNOT be undone!                                 ║" -ForegroundColor Red
        Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
        Write-Host ""

        # First confirmation
        if ($packagesToInstall.Count -gt 0) {
            Write-Host "Are you sure you want to install $($packagesToInstall.Count) AND uninstall $($packagesToUninstall.Count) package(s)? (y/N): " -ForegroundColor Yellow -NoNewline
        } else {
            Write-Host "Are you sure you want to uninstall $($packagesToUninstall.Count) package(s)? (y/N): " -ForegroundColor Yellow -NoNewline
        }
        $confirm1 = Read-Host
        if ($confirm1.ToLower() -ne "y") {
            Write-Host "`nCancelled." -ForegroundColor Cyan
            return
        }

        # Second confirmation - type UNINSTALL
        Write-Host ""
        Write-Host "Type 'UNINSTALL' to confirm: " -ForegroundColor Red -NoNewline
        $confirm2 = Read-Host
        if ($confirm2 -ne "UNINSTALL") {
            Write-Host "`nCancelled." -ForegroundColor Cyan
            return
        }
        Write-Host ""
    } else {
        # Simple confirmation for install-only
        Write-Host "Proceed with installation? (Y/n): " -ForegroundColor Cyan -NoNewline
        $confirm = Read-Host
        if ($confirm -match '^[Nn]') {
            Write-Host "`nCancelled." -ForegroundColor Yellow
            return
        }
    }

    $results = @{
        Installed = 0
        Uninstalled = 0
        Failed = 0
        Errors = @()
    }

    # ═══════════════════════════════════════════════════════════════
    # UNIFIED INSTALLATION PHASE
    # ═══════════════════════════════════════════════════════════════

    if ($packagesToInstall.Count -gt 0) {
        Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║  INSTALLING PACKAGES                       ║" -ForegroundColor Cyan
        Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Cyan

        # Install npm packages
        $npmPackages = $packagesToInstall | Where-Object { $_.Manager -eq "npm" }
        if ($npmPackages.Count -gt 0) {
            Write-Host "Installing npm packages..." -ForegroundColor Cyan
            foreach ($pkg in $npmPackages) {
                Write-Host "  → $($pkg.Name) ($($pkg.Version))..." -ForegroundColor Yellow -NoNewline
                try {
                    $output = npm install -g "$($pkg.Name)@$($pkg.Version)" 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host " ✅" -ForegroundColor Green
                        $results.Installed++
                    } else {
                        Write-Host " ❌" -ForegroundColor Red
                        $results.Failed++
                        $results.Errors += "npm install: $($pkg.Name) - $output"
                    }
                } catch {
                    Write-Host " ❌" -ForegroundColor Red
                    $results.Failed++
                    $results.Errors += "npm install: $($pkg.Name) - $_"
                }
            }
            Write-Host ""
        }

        # Install Scoop packages
        $scoopPackages = $packagesToInstall | Where-Object { $_.Manager -eq "scoop" }
        if ($scoopPackages.Count -gt 0) {
            Write-Host "Installing Scoop packages..." -ForegroundColor Cyan
            foreach ($pkg in $scoopPackages) {
                Write-Host "  → $($pkg.Name)..." -ForegroundColor Yellow -NoNewline
                try {
                    $output = scoop install $pkg.Name 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host " ✅" -ForegroundColor Green
                        $results.Installed++
                    } else {
                        Write-Host " ❌" -ForegroundColor Red
                        $results.Failed++
                        $results.Errors += "scoop install: $($pkg.Name) - $output"
                    }
                } catch {
                    Write-Host " ❌" -ForegroundColor Red
                    $results.Failed++
                    $results.Errors += "scoop install: $($pkg.Name) - $_"
                }
            }
            Write-Host ""
        }

        # Install pip packages
        $pipPackages = $packagesToInstall | Where-Object { $_.Manager -eq "pip" }
        if ($pipPackages.Count -gt 0) {
            Write-Host "Installing pip packages..." -ForegroundColor Cyan
            foreach ($pkg in $pipPackages) {
                Write-Host "  → $($pkg.Name)..." -ForegroundColor Yellow -NoNewline
                try {
                    $output = pip install $pkg.Name 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host " ✅" -ForegroundColor Green
                        $results.Installed++
                    } else {
                        Write-Host " ❌" -ForegroundColor Red
                        $results.Failed++
                        $results.Errors += "pip install: $($pkg.Name) - $output"
                    }
                } catch {
                    Write-Host " ❌" -ForegroundColor Red
                    $results.Failed++
                    $results.Errors += "pip install: $($pkg.Name) - $_"
                }
            }
            Write-Host ""
        }

        # Install winget packages
        $wingetPackages = $packagesToInstall | Where-Object { $_.Manager -eq "winget" }
        if ($wingetPackages.Count -gt 0) {
            Write-Host "Installing winget packages..." -ForegroundColor Cyan
            foreach ($pkg in $wingetPackages) {
                Write-Host "  → $($pkg.Name)..." -ForegroundColor Yellow -NoNewline
                try {
                    $output = winget install --id $pkg.Name --exact --accept-package-agreements --accept-source-agreements 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host " ✅" -ForegroundColor Green
                        $results.Installed++
                    } else {
                        Write-Host " ❌" -ForegroundColor Red
                        $results.Failed++
                        $results.Errors += "winget install: $($pkg.Name) - $output"
                    }
                } catch {
                    Write-Host " ❌" -ForegroundColor Red
                    $results.Failed++
                    $results.Errors += "winget install: $($pkg.Name) - $_"
                }
            }
            Write-Host ""
        }
    }

    # ═══════════════════════════════════════════════════════════════
    # UNIFIED UNINSTALLATION PHASE
    # ═══════════════════════════════════════════════════════════════

    if ($packagesToUninstall.Count -gt 0) {
        Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Red
        Write-Host "║  UNINSTALLING PACKAGES                     ║" -ForegroundColor Red
        Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Red

        # Uninstall packages using consolidated helper function
        $uninstallResults = Invoke-PackageUninstall -Packages $packagesToUninstall
        $results.Uninstalled += $uninstallResults.Uninstalled
        $results.Failed += $uninstallResults.Failed
        $results.Errors += $uninstallResults.Errors
    }

    # Display final summary
    Write-Host "╔════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  COMPLETE                                  ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    if ($results.Installed -gt 0) {
        Write-Host "  ✅ Successfully installed: $($results.Installed)" -ForegroundColor Green
    }
    if ($results.Uninstalled -gt 0) {
        Write-Host "  ✅ Successfully uninstalled: $($results.Uninstalled)" -ForegroundColor Green
    }
    if ($results.Failed -gt 0) {
        Write-Host "  ❌ Failed: $($results.Failed)" -ForegroundColor Red
        Write-Host "`nErrors:" -ForegroundColor Red
        foreach ($errorMsg in $results.Errors) {
            Write-Host "  • $errorMsg" -ForegroundColor Gray
        }
    }

    Write-Host ""
}

function Invoke-ScoopInJob {
    <#
    .SYNOPSIS
    Executes a scoop command in a background job to prevent console artifacts.

    .DESCRIPTION
    Scoop's progress bars use direct console API calls that bypass PowerShell's
    output redirection, causing visual artifacts. This function isolates scoop
    commands in background jobs and provides filtered output.

    .PARAMETER Command
    The scoop command to execute (e.g., "cleanup * -k", "cache rm *")

    .PARAMETER OutputFilter
    Optional scriptblock to filter/format output lines. Default shows "Removing" lines.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [scriptblock]$OutputFilter = {
            param($line)
            # Default: show "Removing" lines with formatted output
            if ($line -match 'Removing\s+(.+):\s+(.+)') {
                Write-Host "    • $($matches[1]): $($matches[2])" -ForegroundColor Gray
            }
        }
    )

    # Start background job to isolate console output
    $job = Start-Job -ScriptBlock ([scriptblock]::Create("scoop $Command 2>&1"))

    # Poll job output and apply filter
    while ($job.State -eq 'Running') {
        $output = Receive-Job $job 2>&1
        if ($output) {
            $output | ForEach-Object {
                & $OutputFilter $_.ToString()
            }
        }
        Start-Sleep -Milliseconds 100
    }

    # Get any remaining output
    $output = Receive-Job $job 2>&1
    if ($output) {
        $output | ForEach-Object {
            & $OutputFilter $_.ToString()
        }
    }

    # Clean up job
    $job | Remove-Job
}

function Invoke-PackageManagerCleanup {
    [CmdletBinding()]
    param()

    Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  PACKAGE MANAGER CLEANUP                   ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    Write-Host "This will clean caches and perform maintenance for all package managers." -ForegroundColor Yellow
    Write-Host ""

    # Scoop cleanup
    Write-Host "📦 Scoop Cleanup:" -ForegroundColor Yellow
    Write-Host ""
    try {
        $scoopCmd = Get-Command scoop -ErrorAction SilentlyContinue
        if ($scoopCmd) {
            # Run scoop checkup
            Write-Host "  Running scoop checkup..." -ForegroundColor Cyan
            Invoke-ScoopInJob -Command "checkup" -OutputFilter {
                param($line)
                # Show all checkup output but filter progress artifacts
                if ($line -notmatch '^\s*$' -and $line -notmatch '\[[\d\/]+\]') {
                    Write-Host "    $line" -ForegroundColor Gray
                }
            }
            Write-Host ""

            # Run scoop cleanup for all apps (removes old versions)
            Write-Host "  Cleaning up old versions..." -ForegroundColor Cyan
            Invoke-ScoopInJob -Command "cleanup * -k"
            Write-Host "  ✅ Old versions cleaned" -ForegroundColor Green
            Write-Host ""

            # Ask about clearing cache
            Write-Host "  Clear cache (removes cached installers)? (y/N): " -ForegroundColor Yellow -NoNewline
            $wipeCacheResponse = Read-Host
            if ($wipeCacheResponse -match '^[Yy]') {
                Write-Host "  Removing all cached installers..." -ForegroundColor Cyan

                # Track removal count for progress feedback
                $script:removeCount = 0
                Invoke-ScoopInJob -Command "cache rm *" -OutputFilter {
                    param($line)
                    if ($line -match 'Removing') {
                        $script:removeCount++
                        if ($script:removeCount % 10 -eq 0) {
                            Write-Host "    • Removed $($script:removeCount) files..." -ForegroundColor Gray
                        }
                    }
                }

                if ($script:removeCount -gt 0) {
                    Write-Host "    • Removed $($script:removeCount) total files" -ForegroundColor Gray
                }
                Write-Host "  ✅ Scoop cache completely cleared" -ForegroundColor Green
            } else {
                Write-Host "  Skipping full cache wipe" -ForegroundColor Gray
            }
        } else {
            Write-Host "  ⚠️  Scoop not found" -ForegroundColor Red
        }
    } catch {
        Write-Host "  ⚠️  Error during Scoop cleanup: $_" -ForegroundColor Red
    }
    Write-Host ""

    # npm cleanup
    Write-Host "📦 npm Cleanup:" -ForegroundColor Yellow
    Write-Host ""
    try {
        $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
        if ($npmCmd) {
            # Clean cache
            Write-Host "  Cleaning npm cache..." -ForegroundColor Cyan
            npm cache clean --force
            Write-Host "  ✅ npm cache cleaned" -ForegroundColor Green
            Write-Host ""

            # Verify cache
            Write-Host "  Verifying npm cache integrity..." -ForegroundColor Cyan
            npm cache verify
            Write-Host "  ✅ npm cache verified" -ForegroundColor Green
        } else {
            Write-Host "  ⚠️  npm not found" -ForegroundColor Red
        }
    } catch {
        Write-Host "  ⚠️  Error during npm cleanup: $_" -ForegroundColor Red
    }
    Write-Host ""

    # pip cleanup
    Write-Host "📦 pip Cleanup:" -ForegroundColor Yellow
    Write-Host ""
    try {
        $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
        if ($pythonCmd) {
            # Check if pip itself needs updating
            Write-Host "  Checking pip version..." -ForegroundColor Cyan
            $pipVersionOutput = python -m pip --version 2>&1 | Out-String
            $pipNeedsUpdate = $false
            $currentPipVer = ""
            $latestPipVer = ""

            # Extract just the version number from "pip X.Y.Z from ..."
            if ($pipVersionOutput -match 'pip ([\d\.]+)') {
                $currentPipVer = $matches[1]
                try {
                    # Check latest version available
                    $pipIndexOutput = python -m pip index versions pip 2>&1 | Out-String
                    if ($pipIndexOutput -match 'LATEST:\s+([\d\.]+)') {
                        $latestPipVer = $matches[1]
                        Write-Host "  Current: $currentPipVer | Latest: $latestPipVer" -ForegroundColor Gray

                        # Check if versions differ
                        if ($currentPipVer -ne $latestPipVer) {
                            $pipNeedsUpdate = $true
                        }
                    } else {
                        Write-Host "  Current: $currentPipVer" -ForegroundColor Gray
                        $pipNeedsUpdate = $true  # Assume update needed if we can't check latest
                    }
                } catch {
                    Write-Host "  Current: $currentPipVer" -ForegroundColor Gray
                    $pipNeedsUpdate = $true  # Assume update needed if check fails
                }
            } else {
                Write-Host "  Current pip: $pipVersionOutput" -ForegroundColor Gray
                $pipNeedsUpdate = $true  # Assume update needed if we can't parse version
            }

            if ($pipNeedsUpdate) {
                Write-Host "  Update pip to latest? (Y/n): " -ForegroundColor Yellow -NoNewline
                $updatePipResponse = Read-Host
                if ($updatePipResponse -notmatch '^[Nn]') {
                    Write-Host "  Updating pip..." -ForegroundColor Cyan
                    python -m pip install --upgrade pip
                    Write-Host "  ✅ pip updated" -ForegroundColor Green
                } else {
                    Write-Host "  Skipping pip update" -ForegroundColor Gray
                }
            } else {
                Write-Host "  ✅ pip is already up to date" -ForegroundColor Green
            }
            Write-Host ""

            # Purge cache
            Write-Host "  Purging pip cache..." -ForegroundColor Cyan
            pip cache purge
            Write-Host "  ✅ pip cache purged" -ForegroundColor Green
        } else {
            Write-Host "  ⚠️  Python/pip not found" -ForegroundColor Red
        }
    } catch {
        Write-Host "  ⚠️  Error during pip cleanup: $_" -ForegroundColor Red
    }
    Write-Host ""

    # winget cleanup
    Write-Host "📦 winget Cleanup:" -ForegroundColor Yellow
    Write-Host ""
    try {
        $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
        if ($wingetCmd) {
            # Update winget source catalogs
            Write-Host "  Updating winget source catalogs..." -ForegroundColor Cyan
            winget source update 2>&1 | Out-Null
            Write-Host "  ✅ winget sources updated" -ForegroundColor Green
            Write-Host ""

            # Note: winget validate requires a manifest file, skip this operation
            # It's used for package manifest validation, not winget itself
            # winget source update already validates the installation

            # Clean winget cache
            Write-Host "  Clear winget cache? (y/N): " -ForegroundColor Yellow -NoNewline
            $clearWingetCacheResponse = Read-Host
            if ($clearWingetCacheResponse -match '^[Yy]') {
                Write-Host "  Clearing winget cache..." -ForegroundColor Cyan
                $cachePath = "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\AC\INetCache"
                if (Test-Path $cachePath) {
                    try {
                        Remove-Item "$cachePath\*" -Recurse -Force -ErrorAction Stop
                        Write-Host "  ✅ winget cache cleared" -ForegroundColor Green
                    } catch {
                        Write-Host "  ⚠️  Error clearing cache: $_" -ForegroundColor Red
                    }
                } else {
                    Write-Host "  ⚠️  Cache path not found" -ForegroundColor Yellow
                }
            } else {
                Write-Host "  Skipping cache clear" -ForegroundColor Gray
            }
        } else {
            Write-Host "  ⚠️  winget not found" -ForegroundColor Red
        }
    } catch {
        Write-Host "  ⚠️  Error during winget cleanup: $_" -ForegroundColor Red
    }
    Write-Host ""

    Write-Host "╔════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  CLEANUP COMPLETE                          ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Cyan
}

function Show-PackageManagerMenu {
    # Define default menu
    $defaultMenu = @(
        (New-MenuAction "Manage Updates" {
            Select-PackagesToUpdate
            Invoke-StandardPause
        }),
        (New-MenuAction "List Installed Packages" {
            Get-InstalledPackages
            Invoke-StandardPause
        }),
        (New-MenuAction "Search Packages" {
            Search-Packages
            Invoke-StandardPause
        }),
        (New-MenuAction "Package Manager Cleanup" {
            Invoke-PackageManagerCleanup
            Invoke-StandardPause
        })
    )

    # Load menu from config (or use default if not customized)
    $packageMenuItems = Get-MenuFromConfig -MenuTitle "Package Manager" -DefaultMenuItems $defaultMenu

    do {
        $choice = Show-ArrowMenu -MenuItems $packageMenuItems -Title "Package Manager"

        if ($choice -eq -1) {
            Write-Host "Returning to Main Menu..." -ForegroundColor Cyan
            return
        }

        # Execute the selected action
        $selectedAction = $packageMenuItems[$choice]
        & $selectedAction.Action

    } while ($true)
}

# ==========================================
# MENU HELPER FUNCTIONS
# ==========================================

function New-MenuAction {
    param(
        [string]$Text,
        [scriptblock]$Action
    )
    return @{
        Text = $Text
        Action = $Action
    }
}


function Start-InteractivePing {
    param(
        [string]$Target = "google.com"
    )

    Write-Host "Starting continuous ping to $Target..." -ForegroundColor Green
    Write-Host "Press 'Q' or 'Esc' to quit and return to menu" -ForegroundColor DarkYellow
    Write-Host ""

    $pingCount = 0

    while ($true) {
        # Check if Q or Esc key was pressed
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.KeyChar -eq 'q' -or $key.KeyChar -eq 'Q' -or $key.Key -eq 'Escape') {
                Write-Host ""
                Write-Host "Ping stopped by user." -ForegroundColor Cyan
                break
            }
        }

        try {
            $pingResult = Test-Connection -ComputerName $Target -Count 1 -ErrorAction Stop
            $pingCount++

            $timestamp = Get-Date -Format "HH:mm:ss"
            $ipAddress = $pingResult.Address
            $responseTime = $pingResult.Latency
            $ttl = $pingResult.Reply.Options.Ttl
            Write-Host "[$timestamp] Reply from ${ipAddress}: bytes=32 time=${responseTime}ms TTL=$ttl" -ForegroundColor Green
        }
        catch {
            $timestamp = Get-Date -Format "HH:mm:ss"
            Write-Host "[$timestamp] Request timed out or failed: $($_.Exception.Message)" -ForegroundColor Red
        }

        Start-Sleep -Seconds 1
    }

    Write-Host ""
    Write-Host "Ping completed. Total pings sent: $pingCount" -ForegroundColor Cyan
}

function Show-NetworkConfiguration {
    [CmdletBinding()]
    param()

    Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  NETWORK CONFIGURATION                     ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    try {
        # Show progress spinner while gathering information
        Write-Host "Gathering network information" -NoNewline -ForegroundColor Yellow

        # Get all network adapters (including hidden ones)
        # Only get adapters that are physical or virtual (exclude WAN Miniport, etc.)
        $allAdapters = Get-NetAdapter -IncludeHidden | Where-Object {
            $_.InterfaceDescription -notmatch 'WAN Miniport|Kernel Debug|Microsoft Kernel Debug'
        }

        if (-not $allAdapters) {
            Write-Host "`r                                        `r" -NoNewline  # Clear spinner line
            Write-Host "No network adapters found." -ForegroundColor Yellow
            return
        }

        # Build table data with progress spinner
        $tableData = @()
        $spinnerChars = @('|', '/', '-', '\')
        $spinnerIndex = 0
        $adapterCount = $allAdapters.Count
        $currentAdapter = 0

        foreach ($netAdapter in $allAdapters) {
            $currentAdapter++

            # Update spinner
            $spinner = $spinnerChars[$spinnerIndex % 4]
            Write-Host "`r$spinner Gathering network information ($currentAdapter/$adapterCount)..." -NoNewline -ForegroundColor Yellow
            $spinnerIndex++
            # Try to get IP configuration for this adapter
            # Use a scriptblock with redirection to suppress all output streams
            $ipConfig = $null
            $ipConfig = & {
                $ErrorActionPreference = 'SilentlyContinue'
                Get-NetIPConfiguration -InterfaceIndex $netAdapter.InterfaceIndex
            } 2>&1 | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }

            # Get IP information
            $ipv4 = if ($ipConfig -and $ipConfig.IPv4Address) {
                $ipConfig.IPv4Address[0].IPAddress
            } else {
                "N/A"
            }

            $subnet = if ($ipConfig -and $ipConfig.IPv4Address) {
                $prefixLength = $ipConfig.IPv4Address[0].PrefixLength
                "$(Convert-PrefixToSubnetMask -PrefixLength $prefixLength) (/$prefixLength)"
            } else {
                "N/A"
            }

            $gateway = if ($ipConfig -and $ipConfig.IPv4DefaultGateway) {
                $ipConfig.IPv4DefaultGateway[0].NextHop
            } else {
                "N/A"
            }

            $dns = if ($ipConfig -and $ipConfig.DNSServer) {
                ($ipConfig.DNSServer.ServerAddresses | Select-Object -First 2) -join ", "
            } else {
                "N/A"
            }

            $dhcp = if ($ipConfig -and $ipConfig.NetIPv4Interface.Dhcp -eq "Enabled") {
                "Yes"
            } else {
                "No"
            }

            # Determine IP type for sorting (routable, link-local, or none)
            $ipType = if ($ipv4 -eq "N/A") {
                3  # No IP - lowest priority
            } elseif ($ipv4 -like "169.254.*") {
                2  # Link-local (APIPA) - medium priority
            } else {
                1  # Routable IP - highest priority
            }

            # Status priority (Up = 1, anything else = 2)
            $statusPriority = if ($netAdapter.Status -eq "Up") { 1 } else { 2 }

            $tableData += [PSCustomObject]@{
                Adapter         = $netAdapter.InterfaceAlias
                Status          = $netAdapter.Status
                IPAddress       = $ipv4
                SubnetMask      = $subnet
                Gateway         = $gateway
                DNS             = $dns
                DHCP            = $dhcp
                MAC             = $netAdapter.MacAddress
                LinkSpeed       = $netAdapter.LinkSpeed
                StatusPriority  = $statusPriority
                IPTypePriority  = $ipType
            }
        }

        # Clear spinner line
        Write-Host "`r                                                                `r" -NoNewline

        # Sort by status (Up first), then by IP type (routable first), then by adapter name
        $tableData = $tableData | Sort-Object StatusPriority, IPTypePriority, Adapter

        # Display table with colors
        Write-Host "Network Adapters:" -ForegroundColor Yellow
        Write-Host ""

        # Custom table rendering with colors
        $headers = @("Adapter", "Status", "IP Address", "Subnet Mask", "Gateway", "DNS Servers", "DHCP", "MAC", "Speed")

        # Calculate column widths dynamically based on content
        $colWidths = @{
            Adapter    = [Math]::Max(($tableData.Adapter | Measure-Object -Maximum -Property Length).Maximum, $headers[0].Length)
            Status     = [Math]::Max(($tableData.Status | Measure-Object -Maximum -Property Length).Maximum, $headers[1].Length)
            IPAddress  = [Math]::Max(($tableData.IPAddress | Measure-Object -Maximum -Property Length).Maximum, $headers[2].Length)
            SubnetMask = [Math]::Max(($tableData.SubnetMask | Measure-Object -Maximum -Property Length).Maximum, $headers[3].Length)
            Gateway    = [Math]::Max(($tableData.Gateway | Measure-Object -Maximum -Property Length).Maximum, $headers[4].Length)
            DNS        = [Math]::Max([Math]::Min(($tableData.DNS | Measure-Object -Maximum -Property Length).Maximum, 35), $headers[5].Length)
            DHCP       = [Math]::Max(($tableData.DHCP | Measure-Object -Maximum -Property Length).Maximum, $headers[6].Length)
            MAC        = [Math]::Max(($tableData.MAC | Measure-Object -Maximum -Property Length).Maximum, $headers[7].Length)
            LinkSpeed  = [Math]::Max(($tableData.LinkSpeed | Measure-Object -Maximum -Property Length).Maximum, $headers[8].Length)
        }

        # Calculate total table width
        $totalWidth = $colWidths.Values | Measure-Object -Sum | Select-Object -ExpandProperty Sum
        $totalWidth += ($colWidths.Count - 1) * 1  # Add spaces between columns

        # Header row
        Write-Host ("─" * $totalWidth) -ForegroundColor Cyan
        Write-Host ("{0,-$($colWidths.Adapter)} {1,-$($colWidths.Status)} {2,-$($colWidths.IPAddress)} {3,-$($colWidths.SubnetMask)} {4,-$($colWidths.Gateway)} {5,-$($colWidths.DNS)} {6,-$($colWidths.DHCP)} {7,-$($colWidths.MAC)} {8,-$($colWidths.LinkSpeed)}" -f `
            $headers[0], $headers[1], $headers[2], $headers[3], $headers[4], $headers[5], $headers[6], $headers[7], $headers[8]) -ForegroundColor Yellow
        Write-Host ("─" * $totalWidth) -ForegroundColor Cyan

        # Data rows
        foreach ($row in $tableData) {
            # Adapter name
            Write-Host ("{0,-$($colWidths.Adapter)} " -f $row.Adapter) -NoNewline -ForegroundColor White

            # Status with color
            if ($row.Status -eq "Up") {
                Write-Host ("{0,-$($colWidths.Status)} " -f $row.Status) -NoNewline -ForegroundColor Green
            } else {
                Write-Host ("{0,-$($colWidths.Status)} " -f $row.Status) -NoNewline -ForegroundColor Red
            }

            # IP Address
            Write-Host ("{0,-$($colWidths.IPAddress)} " -f $row.IPAddress) -NoNewline -ForegroundColor Cyan

            # Subnet Mask
            Write-Host ("{0,-$($colWidths.SubnetMask)} " -f $row.SubnetMask) -NoNewline -ForegroundColor White

            # Gateway
            Write-Host ("{0,-$($colWidths.Gateway)} " -f $row.Gateway) -NoNewline -ForegroundColor Cyan

            # DNS (truncate if too long)
            $dnsDisplay = if ($row.DNS.Length -gt $colWidths.DNS) { $row.DNS.Substring(0, $colWidths.DNS - 3) + "..." } else { $row.DNS }
            Write-Host ("{0,-$($colWidths.DNS)} " -f $dnsDisplay) -NoNewline -ForegroundColor Cyan

            # DHCP with color
            if ($row.DHCP -eq "Yes") {
                Write-Host ("{0,-$($colWidths.DHCP)} " -f $row.DHCP) -NoNewline -ForegroundColor Green
            } else {
                Write-Host ("{0,-$($colWidths.DHCP)} " -f $row.DHCP) -NoNewline -ForegroundColor Yellow
            }

            # MAC Address
            Write-Host ("{0,-$($colWidths.MAC)} " -f $row.MAC) -NoNewline -ForegroundColor Gray

            # Link Speed
            Write-Host ("{0,-$($colWidths.LinkSpeed)}" -f $row.LinkSpeed) -ForegroundColor White
        }

        Write-Host ("─" * $totalWidth) -ForegroundColor Cyan
        Write-Host ""

        # System Information
        Write-Host "System Information:" -ForegroundColor Yellow
        Write-Host "  Computer Name: " -NoNewline -ForegroundColor Gray
        Write-Host "$env:COMPUTERNAME" -ForegroundColor White
        Write-Host "  DNS Domain:    " -NoNewline -ForegroundColor Gray
        $dnsDomain = (Get-WmiObject Win32_ComputerSystem).Domain
        Write-Host "$dnsDomain" -ForegroundColor White
        Write-Host ""
    }
    catch {
        Write-Host "Error retrieving network configuration: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Convert-PrefixToSubnetMask {
    param([int]$PrefixLength)

    $mask = ([Math]::Pow(2, 32) - [Math]::Pow(2, (32 - $PrefixLength)))
    $bytes = [BitConverter]::GetBytes([UInt32]$mask)
    [Array]::Reverse($bytes)
    return ($bytes -join '.')
}

function Invoke-StandardPause {
    <#
    .SYNOPSIS
        Standardized pause function with consistent key handling across the console.

    .DESCRIPTION
        Provides a unified pause experience that responds to Enter, Esc, and optionally Q.
        Replaces inconsistent pause patterns throughout the codebase.

    .PARAMETER Message
        Custom message to display (default: "Press Enter to continue...")

    .PARAMETER AllowQuit
        If $true, also accepts 'Q' to quit and returns $false (default: $true)

    .PARAMETER AllowEscape
        If $true, also accepts 'Esc' to quit and returns $false (default: $true)

    .EXAMPLE
        Invoke-StandardPause
        # Shows: "Press Enter to continue..."
        # Responds to: Enter, Esc, Q

    .EXAMPLE
        Invoke-StandardPause -Message "Custom message..." -AllowQuit $false
        # Shows custom message
        # Responds to: Enter, Esc only (Q disabled)
        # Returns $true if Enter, $false if Esc

    .OUTPUTS
        Boolean - $true if user pressed Enter, $false if user pressed Q/Esc to quit
    #>
    param(
        [string]$Message = "Press Enter to continue...",
        [bool]$AllowQuit = $true,
        [bool]$AllowEscape = $true
    )

    Write-Host $Message -ForegroundColor Gray -NoNewline

    # Clear any lingering keyboard buffer before reading
    while ([Console]::KeyAvailable) {
        [Console]::ReadKey($true) | Out-Null
    }

    while ($true) {
        $key = [Console]::ReadKey($true)

        # Always accept Enter
        if ($key.Key -eq 'Enter') {
            Write-Host ""  # New line after key press
            return $true
        }

        # Accept Esc if enabled
        if ($AllowEscape -and $key.Key -eq 'Escape') {
            Write-Host ""  # New line after key press
            return $false
        }

        # Accept Q if enabled
        if ($AllowQuit -and ($key.Key -eq 'Q' -or $key.KeyChar -eq 'q')) {
            Write-Host ""  # New line after key press
            return $false
        }
    }
}

function Invoke-TimedPause {
    <#
    .SYNOPSIS
        Pauses execution with an auto-continue timer and option to press Enter to continue immediately.

    .PARAMETER TimeoutSeconds
        Number of seconds to wait before auto-continuing (default: 30)

    .PARAMETER Message
        Custom message to display (default: "Returning to menu")

    .EXAMPLE
        Invoke-TimedPause -TimeoutSeconds 30 -Message "Returning to menu"
    #>
    param(
        [int]$TimeoutSeconds = 30,
        [string]$Message = "Returning to menu"
    )

    Write-Host ""
    $elapsed = 0
    $lastRemaining = $TimeoutSeconds

    # Display initial countdown
    Write-Host "$Message in $TimeoutSeconds seconds (or press Enter to continue now)..." -NoNewline -ForegroundColor Yellow

    while ($elapsed -lt $TimeoutSeconds) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq 'Enter') {
                Write-Host "`r$(' ' * 100)`r$Message..." -ForegroundColor Green
                return
            }
        }
        Start-Sleep -Milliseconds 100
        $elapsed += 0.1

        # Update countdown every second
        $remaining = [Math]::Ceiling($TimeoutSeconds - $elapsed)
        if ($remaining -ne $lastRemaining) {
            $lastRemaining = $remaining
            # Clear line and rewrite
            Write-Host "`r$(' ' * 100)`r$Message in $remaining seconds (or press Enter to continue now)..." -NoNewline -ForegroundColor Yellow
        }
    }

    Write-Host "`r$(' ' * 100)`r$Message..." -ForegroundColor Cyan
}

# ==========================================
# MENU POSITION MEMORY FUNCTIONS
# ==========================================

function Get-SavedMenuPosition {
    <#
    .SYNOPSIS
        Retrieves the last saved menu position for a given menu title.

    .DESCRIPTION
        Returns the last selected index for the specified menu, or 0 if no position is saved.
        This function is designed to be easily expandable to Option 3 (timeout-based memory).

    .PARAMETER Title
        The menu title used as the key for position storage.

    .EXAMPLE
        $position = Get-SavedMenuPosition -Title "Main Menu"
    #>
    param([string]$Title)

    if ($global:MenuPositionMemory.ContainsKey($Title)) {
        return $global:MenuPositionMemory[$Title]
    }
    return 0
}

function Save-MenuPosition {
    <#
    .SYNOPSIS
        Saves the current menu position for a given menu title.

    .DESCRIPTION
        Stores the selected index for the specified menu to remember user's position.
        This function is designed to be easily expandable to Option 3 (timeout-based memory).

    .PARAMETER Title
        The menu title used as the key for position storage.

    .PARAMETER Position
        The index position to save.

    .EXAMPLE
        Save-MenuPosition -Title "Main Menu" -Position 2
    #>
    param(
        [string]$Title,
        [int]$Position
    )

    $global:MenuPositionMemory[$Title] = $Position
}

function Show-ArrowMenu {
    param(
        $MenuItems,  # Can be string[] or object[] with Text property
        [string]$Title = "Please select an option",
        [string[]]$HeaderLines = @()  # Optional header lines to display above menu
    )

    # Restore last position for this menu, or default to 0
    $selectedIndex = Get-SavedMenuPosition -Title $Title
    $key = $null

    do {
        Clear-Host

        # Display optional header lines before the menu
        if ($HeaderLines.Count -gt 0) {
            foreach ($line in $HeaderLines) {
                Write-Host $line
            }
            Write-Host ""
        }

        Write-Host $Title -ForegroundColor Yellow
        Write-Host ('=' * $Title.Length) -ForegroundColor Yellow
        Write-Host ""

        for ($i = 0; $i -lt $MenuItems.Length; $i++) {
            $menuItem = $MenuItems[$i]

            # Handle both string and object menu items
            if ($menuItem -is [string]) {
                $text = $menuItem
            } else {
                $text = $menuItem.Text
            }

            if ($i -eq $selectedIndex) {
                Write-Host "> $text" -ForegroundColor Green
            } else {
                Write-Host "  $text" -ForegroundColor White
            }
        }

        Write-Host ""
        Write-Host "↑↓ navigate | ⏎ select | ⎋ back | ⌃x exit | ⌃␣ move | ⌃r rename" -ForegroundColor Gray

        $key = [Console]::ReadKey($true)

        switch ($key.Key) {
            'UpArrow' {
                $selectedIndex = ($selectedIndex - 1 + $MenuItems.Length) % $MenuItems.Length
            }
            'DownArrow' {
                $selectedIndex = ($selectedIndex + 1) % $MenuItems.Length
            }
            'Enter' {
                # Save position before returning
                Save-MenuPosition -Title $Title -Position $selectedIndex
                return $selectedIndex
            }
            'Escape' {
                # Don't save position when going back
                return -1
            }
            'Q' {
                # Don't save position when going back
                return -1
            }
            'X' {
                # Check if Ctrl is pressed
                if ($key.Modifiers -band [ConsoleModifiers]::Control) {
                    Write-Host "`nExiting script. Goodbye!" -ForegroundColor Cyan
                    Start-Sleep -Seconds 1
                    Restore-ConsoleState
                    exit
                }
            }
            'Spacebar' {
                # Check if Ctrl is pressed for move mode
                if ($key.Modifiers -band [ConsoleModifiers]::Control) {
                    # Enter move mode
                    $moveMode = $true
                    $moveIndex = $selectedIndex

                    while ($moveMode) {
                        Clear-Host

                        # Display optional header lines
                        if ($HeaderLines.Count -gt 0) {
                            foreach ($line in $HeaderLines) {
                                Write-Host $line
                            }
                            Write-Host ""
                        }

                        Write-Host "$Title - MOVE MODE" -ForegroundColor Magenta
                        Write-Host ('=' * "$Title - MOVE MODE".Length) -ForegroundColor Magenta
                        Write-Host ""

                        for ($i = 0; $i -lt $MenuItems.Length; $i++) {
                            $menuItem = $MenuItems[$i]
                            $text = if ($menuItem -is [string]) { $menuItem } else { $menuItem.Text }

                            if ($i -eq $moveIndex) {
                                Write-Host "→ $text ←" -ForegroundColor Magenta
                            } else {
                                Write-Host "  $text" -ForegroundColor DarkGray
                            }
                        }

                        Write-Host ""
                        Write-Host "⬆️⬇️move position | ⏎ confirm | ⎋ cancel" -ForegroundColor Yellow

                        $moveKey = [Console]::ReadKey($true)

                        switch ($moveKey.Key) {
                            'UpArrow' {
                                if ($moveIndex -gt 0) {
                                    # Swap items
                                    $temp = $MenuItems[$moveIndex]
                                    $MenuItems[$moveIndex] = $MenuItems[$moveIndex - 1]
                                    $MenuItems[$moveIndex - 1] = $temp
                                    $moveIndex--
                                    $selectedIndex = $moveIndex
                                }
                            }
                            'DownArrow' {
                                if ($moveIndex -lt ($MenuItems.Length - 1)) {
                                    # Swap items
                                    $temp = $MenuItems[$moveIndex]
                                    $MenuItems[$moveIndex] = $MenuItems[$moveIndex + 1]
                                    $MenuItems[$moveIndex + 1] = $temp
                                    $moveIndex++
                                    $selectedIndex = $moveIndex
                                }
                            }
                            'Enter' {
                                $moveMode = $false
                                # Save menu after move
                                if ($Title -eq "Select AWS Account/Environment") {
                                    Save-AwsAccountMenuOrder -MenuItems $MenuItems
                                } else {
                                    Save-Menu -MenuTitle $Title -MenuItems $MenuItems
                                }
                            }
                            'Escape' {
                                $moveMode = $false
                            }
                        }
                    }
                }
            }
            'R' {
                # Check if Ctrl is pressed for rename
                if ($key.Modifiers -band [ConsoleModifiers]::Control) {
                    Clear-Host

                    $currentText = if ($MenuItems[$selectedIndex] -is [string]) {
                        $MenuItems[$selectedIndex]
                    } else {
                        $MenuItems[$selectedIndex].Text
                    }

                    Write-Host "╔════════════════════════════════════════════╗" -ForegroundColor Cyan
                    Write-Host "║  RENAME MENU ITEM                          ║" -ForegroundColor Cyan
                    Write-Host "╚════════════════════════════════════════════╝" -ForegroundColor Cyan
                    Write-Host ""
                    Write-Host "Current name: $currentText" -ForegroundColor Yellow
                    Write-Host ""
                    $newName = Read-Host "Enter new name (or press Enter to cancel)"

                    if (-not [string]::IsNullOrWhiteSpace($newName)) {
                        if ($MenuItems[$selectedIndex] -is [string]) {
                            $MenuItems[$selectedIndex] = $newName
                        } else {
                            $MenuItems[$selectedIndex].Text = $newName
                        }

                        # Save menu after rename
                        if ($Title -eq "Select AWS Account/Environment") {
                            # For AWS Account menu, save custom name to environment
                            $item = $MenuItems[$selectedIndex]
                            Save-AwsAccountCustomName -Environment $item.Environment -Role $item.Role -CustomName $newName
                        } else {
                            Save-Menu -MenuTitle $Title -MenuItems $MenuItems
                        }
                    }
                }
            }
        }
    } while ($true)
}

function Start-MerakiBackup {
    Write-Host "Meraki Backup" -ForegroundColor Cyan
    Write-Host "=============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "This will launch the interactive Meraki backup tool." -ForegroundColor Yellow
    Write-Host ""

    # Read devRoot from config.json (same as count-lines.py does)
    # meraki-api is a separate project at the same level as powershell-console
    if ($script:Config.paths.devRoot) {
        $devRoot = $script:Config.paths.devRoot
    } else {
        # Fallback to parent directory if devRoot not configured
        $devRoot = Split-Path $PSScriptRoot -Parent
    }
    $merakiPath = Join-Path $devRoot "meraki-api"

    if (Test-Path $merakiPath) {
        try {
            Push-Location $merakiPath

            # Check if Python is available
            $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
            if (-not $pythonCmd) {
                Write-Host "Python not found in PATH. Please ensure Python is installed." -ForegroundColor Red
                Invoke-StandardPause
                return
            }

            # Check if backup.py exists
            if (-not (Test-Path "backup.py")) {
                Write-Host "backup.py not found in meraki-api directory." -ForegroundColor Red
                Invoke-StandardPause
                return
            }

            # Check if .env file exists
            if (-not (Test-Path ".env")) {
                Write-Host "Warning: .env file not found. Make sure MERAKI_API_KEY is set in environment." -ForegroundColor Yellow
            }

            Write-Host "Executing: python backup.py -i" -ForegroundColor Cyan
            Write-Host ""

            # Run the backup script in interactive mode
            # -i flag allows user to select specific orgs/networks instead of backing up everything
            python backup.py -i

            Write-Host ""
            Write-Host "Meraki backup completed." -ForegroundColor Green
        }
        catch {
            Write-Host "Error running Meraki backup: $($_.Exception.Message)" -ForegroundColor Red
        }
        finally {
            Pop-Location
        }
    }
    else {
        Write-Host "Meraki API directory not found at: $merakiPath" -ForegroundColor Red
        Write-Host "Please ensure the meraki-api folder exists in the dev directory (same level as powershell-console)." -ForegroundColor Yellow
    }

    Invoke-StandardPause
}

function Start-CodeCount {
    # Use $PSScriptRoot to get the actual script directory
    $countScriptPath = Join-Path $PSScriptRoot "modules\line-counter\count-lines.py"
    $configPath = Join-Path $PSScriptRoot "config.json"

    # Check if Python is available
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonCmd) {
        Write-Host "`nPython not found in PATH. Please ensure Python is installed." -ForegroundColor Red
        Invoke-StandardPause
        return  # This is a hard error, exit to main menu
    }

    # Check if count-lines.py exists
    if (-not (Test-Path $countScriptPath)) {
        Write-Host "`ncount-lines.py not found at: $countScriptPath" -ForegroundColor Red
        Invoke-StandardPause
        return  # This is a hard error, exit to main menu
    }

    # Initialize navigation state
    # Read devRoot from config.json (same as count-lines.py does)
    if ($script:Config.paths.devRoot) {
        $devRoot = $script:Config.paths.devRoot
    } else {
        # Fallback to parent directory if devRoot not configured
        Write-Host "`nWarning: paths.devRoot not found in config.json, using parent directory" -ForegroundColor Yellow
        $devRoot = Split-Path $PSScriptRoot -Parent
    }
    $currentPath = $devRoot
    $pathStack = @()
    $selections = @{}  # Track selections by full path
    $done = $false

    while (-not $done) {
        # Build menu for current directory
        $menuOptions = @()

        # Add "All Projects" at root level only
        if ($currentPath -eq $devRoot) {
            $menuOptions += [PSCustomObject]@{
                Name = "All Projects"
                Path = $null
                Type = "Special"
            }
        }

        # Add parent directory option if not at root
        if ($currentPath -ne $devRoot) {
            $menuOptions += [PSCustomObject]@{
                Name = ".. (Parent Directory)"
                Path = Split-Path $currentPath -Parent
                Type = "Parent"
            }
        }

        # Add subdirectories
        Get-ChildItem $currentPath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike ".*" } | Sort-Object Name | ForEach-Object {
            $menuOptions += [PSCustomObject]@{
                Name = "📁 $($_.Name)"
                Path = $_.FullName
                Type = "Directory"
            }
        }

        # Add files (excluding common binary/excluded types that shouldn't be counted)
        $excludedExtensions = @('.vhdx', '.avhdx', '.vsix', '.zip', '.csv', '.log', '.exe', '.dll', '.bin', '.iso')
        Get-ChildItem $currentPath -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -notlike ".*" -and $excludedExtensions -notcontains $_.Extension.ToLower()
        } | Sort-Object Name | ForEach-Object {
            $menuOptions += [PSCustomObject]@{
                Name = "📄 $($_.Name)"
                Path = $_.FullName
                Type = "File"
            }
        }

        if ($menuOptions.Count -eq 0) {
            Invoke-StandardPause -Message "Empty directory. Press Enter to go back..."
            if ($pathStack.Count -gt 0) {
                $currentPath = $pathStack[-1]
                $pathStack = $pathStack[0..($pathStack.Count - 2)]
            }
            continue
        }

        # Initialize selections for new items
        $selectedIndexes = New-Object bool[] $menuOptions.Count
        for ($i = 0; $i -lt $menuOptions.Count; $i++) {
            if ($menuOptions[$i].Path -and $selections.ContainsKey($menuOptions[$i].Path)) {
                $selectedIndexes[$i] = $selections[$menuOptions[$i].Path]
            }
        }

        $currentIndex = 0

        # Menu loop
        $menuDone = $false
        while (-not $menuDone) {
            Clear-Host
            Write-Host "╔════════════════════════════════════════════╗" -ForegroundColor Cyan
            Write-Host "║  CODE LINE COUNTER                         ║" -ForegroundColor Cyan
            Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Cyan

            # Show current path
            $relativePath = $currentPath.Replace($devRoot, "~")
            if ($relativePath -eq "") { $relativePath = "~" }
            Write-Host "Current: $relativePath" -ForegroundColor Yellow
            Write-Host ""

            Write-Host "↑↓ navigate | → enter dir | ← parent | Space select | Enter count | A all | N none | Q cancel`n" -ForegroundColor Gray

            for ($i = 0; $i -lt $menuOptions.Count; $i++) {
                $option = $menuOptions[$i]
                $checkbox = if ($selectedIndexes[$i]) { "[x]" } else { "[ ]" }
                $arrow = if ($i -eq $currentIndex) { ">" } else { " " }
                $color = if ($i -eq $currentIndex) { "Green" } else { "White" }

                # Don't show checkbox for parent directory
                if ($option.Type -eq "Parent") {
                    Write-Host "$arrow     $($option.Name)" -ForegroundColor $color
                } else {
                    Write-Host "$arrow $checkbox $($option.Name)" -ForegroundColor $color
                }
            }

            $key = [Console]::ReadKey($true)

            switch ($key.Key) {
                'UpArrow' {
                    $currentIndex = ($currentIndex - 1 + $menuOptions.Count) % $menuOptions.Count
                }
                'DownArrow' {
                    $currentIndex = ($currentIndex + 1) % $menuOptions.Count
                }
                'RightArrow' {
                    # Navigate into directory
                    if ($menuOptions[$currentIndex].Type -eq "Directory") {
                        $pathStack += $currentPath
                        $currentPath = $menuOptions[$currentIndex].Path
                        $menuDone = $true
                    }
                }
                'LeftArrow' {
                    # Navigate to parent
                    if ($currentPath -ne $devRoot) {
                        if ($pathStack.Count -gt 0) {
                            $currentPath = $pathStack[-1]
                            $pathStack = $pathStack[0..($pathStack.Count - 2)]
                        } else {
                            $currentPath = $devRoot
                        }
                        $menuDone = $true
                    }
                }
                'Spacebar' {
                    # Toggle selection (except for parent directory)
                    if ($menuOptions[$currentIndex].Type -ne "Parent") {
                        $selectedIndexes[$currentIndex] = -not $selectedIndexes[$currentIndex]
                        if ($menuOptions[$currentIndex].Path) {
                            $selections[$menuOptions[$currentIndex].Path] = $selectedIndexes[$currentIndex]
                        }
                    } else {
                        # Parent directory navigation
                        if ($pathStack.Count -gt 0) {
                            $currentPath = $pathStack[-1]
                            $pathStack = $pathStack[0..($pathStack.Count - 2)]
                        } else {
                            $currentPath = Split-Path $currentPath -Parent
                        }
                        $menuDone = $true
                    }
                }
                'A' {
                    for ($i = 0; $i -lt $selectedIndexes.Count; $i++) {
                        if ($menuOptions[$i].Type -ne "Parent") {
                            $selectedIndexes[$i] = $true
                            if ($menuOptions[$i].Path) {
                                $selections[$menuOptions[$i].Path] = $true
                            }
                        }
                    }
                }
                'N' {
                    for ($i = 0; $i -lt $selectedIndexes.Count; $i++) {
                        if ($menuOptions[$i].Type -ne "Parent") {
                            $selectedIndexes[$i] = $false
                            if ($menuOptions[$i].Path) {
                                $selections[$menuOptions[$i].Path] = $false
                            }
                        }
                    }
                }
                'Enter' {
                    $done = $true
                    $menuDone = $true
                }
                'Q' {
                    Write-Host "`nCancelled." -ForegroundColor Yellow
                    return  # User cancelled, exit to main menu
                }
            }
        }
    }

    # Get all selected items
    $selectedItems = @()
    foreach ($path in $selections.Keys) {
        if ($selections[$path]) {
            $selectedItems += $path
        }
    }

    # Check for "All Projects"
    $countAll = $false
    for ($i = 0; $i -lt $menuOptions.Count; $i++) {
        if ($selectedIndexes[$i] -and $menuOptions[$i].Name -eq "All Projects") {
            $countAll = $true
            break
        }
    }

    if ($selectedItems.Count -eq 0 -and -not $countAll) {
        Write-Host "`nNo items selected." -ForegroundColor Yellow
        Invoke-StandardPause
        Start-CodeCount
        return
    }

    Clear-Host
    Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  CODE LINE COUNTER - RESULTS               ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    # Count all projects if selected
    if ($countAll) {
        Write-Host "Counting: All Projects" -ForegroundColor Yellow
        Write-Host "Executing: python $countScriptPath --config `"$configPath`" `"$devRoot`"" -ForegroundColor Gray
        Write-Host ""
        python $countScriptPath --config "$configPath" "$devRoot"
        Write-Host ""

        # If there are also individual items selected, pause before showing them
        if ($selectedItems.Count -gt 0) {
            Invoke-StandardPause -Message "Press Enter to view individual project counts..."
        }
    }

    # Count each selected item with pagination
    $itemCount = $selectedItems.Count
    $currentItem = 0
    foreach ($itemPath in $selectedItems) {
        $currentItem++
        $relativePath = $itemPath.Replace($devRoot + "\", "")

        Write-Host "───────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host "Project $currentItem of $itemCount" -ForegroundColor Gray
        Write-Host "───────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host ""

        Write-Host "Counting: $relativePath" -ForegroundColor Yellow
        Write-Host "Executing: python $countScriptPath --config `"$configPath`" `"$itemPath`"" -ForegroundColor Gray
        Write-Host ""
        python $countScriptPath --config "$configPath" "$itemPath"
        Write-Host ""

        # Pause between items (but not after the last one)
        if ($currentItem -lt $itemCount) {
            $continue = Invoke-StandardPause -Message "Press Enter to continue (or Q/Esc to quit viewing more)..."
            if (-not $continue) {
                Write-Host "`nSkipping remaining projects..." -ForegroundColor Yellow
                break
            }
        }
    }

    Invoke-StandardPause
    Start-CodeCount
}

# Helper function to get OneDrive executable path
function Get-OneDrivePath {
    # Try multiple possible OneDrive locations
    $possiblePaths = @(
        "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe",           # Personal install
        "${env:ProgramFiles}\Microsoft OneDrive\OneDrive.exe",          # System-wide install
        "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe"      # 32-bit install on 64-bit system
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    return $null
}

# Helper function to pause OneDrive sync
function Suspend-OneDriveSync {
    <#
    .SYNOPSIS
    Shuts down OneDrive temporarily to pause sync

    .DESCRIPTION
    Uses OneDrive.exe /shutdown to stop OneDrive completely.
    Returns $true if successful, $false otherwise.

    .EXAMPLE
    if (Suspend-OneDriveSync) {
        # Do work that benefits from paused sync
        Resume-OneDriveSync
    }
    #>

    try {
        $oneDrivePath = Get-OneDrivePath

        if (-not $oneDrivePath) {
            Write-Host "  ⚠️  OneDrive not found in any standard location" -ForegroundColor Yellow
            return $false
        }

        # Shutdown OneDrive completely
        & $oneDrivePath /shutdown
        Start-Sleep -Milliseconds 500  # Brief pause to let it shut down

        Write-Host "  ⏸️  OneDrive sync paused" -ForegroundColor Cyan
        return $true
    }
    catch {
        Write-Host "  ⚠️  Error pausing OneDrive: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

# Helper function to resume OneDrive sync
function Resume-OneDriveSync {
    <#
    .SYNOPSIS
    Resumes OneDrive sync after being shut down

    .DESCRIPTION
    Starts OneDrive.exe with /background flag to resume sync.
    Returns $true if successful, $false otherwise.

    .EXAMPLE
    Resume-OneDriveSync
    #>

    try {
        $oneDrivePath = Get-OneDrivePath

        if (-not $oneDrivePath) {
            Write-Host "  ⚠️  OneDrive not found in any standard location" -ForegroundColor Yellow
            return $false
        }

        # Start OneDrive in background mode without elevation
        # Use runas /trustlevel:0x20000 to launch without inheriting admin privileges
        # This avoids the "OneDrive can't be run using full administrator rights" error
        Start-Process "runas.exe" -ArgumentList "/trustlevel:0x20000 `"$oneDrivePath /background`"" -WindowStyle Hidden

        Write-Host "  ▶️  OneDrive sync resumed" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "  ⚠️  Error resuming OneDrive: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

# Helper function to get backup script path
function Get-BackupScriptPath {
    # Use $PSScriptRoot to get the actual script directory (handles project renames automatically)
    $backupScriptPath = Join-Path $PSScriptRoot "modules\backup-dev\backup-dev.ps1"

    if (-not (Test-Path $backupScriptPath)) {
        Write-Host "backup-dev.ps1 not found at: $backupScriptPath" -ForegroundColor Red
    Invoke-StandardPause
        return $null
    }

    return $backupScriptPath
}

# Helper function to execute backup with parameters
function Get-LastBackupTimestamp {
    # Read from backup-history.log which maintains history of last 10 backups (newest first)
    $backupHistoryPath = Join-Path $PSScriptRoot "modules\backup-dev\backup-history.log"
    if (Test-Path $backupHistoryPath) {
        try {
            # Read the file and find the most recent FULL backup timestamp
            # Format: === Backup: 2025-12-23 12:44:34 | Mode: FULL ===
            # Note: File is ordered newest first, so we want the FIRST match
            $content = Get-Content $backupHistoryPath -Raw

            # Find all FULL backup timestamps (newest first in file)
            $timestamps = [regex]::Matches($content, '=== Backup: (.+?) \| Mode: FULL ===')

            if ($timestamps.Count -gt 0) {
                # Get the most recent FULL backup timestamp (first match, since newest is at top)
                $lastTimestamp = $timestamps[0].Groups[1].Value
                return [DateTime]::Parse($lastTimestamp)
            }
        }
        catch {
            return $null
        }
    }
    return $null
}

function Invoke-BackupScript {
    param(
        [string[]]$Arguments = @(),
        [string]$Description = "backup"
    )

    $backupScriptPath = Get-BackupScriptPath
    if (-not $backupScriptPath) { return }

    Write-Host ""
    if ($Arguments.Count -gt 0) {
        Write-Host "Executing: $backupScriptPath $($Arguments -join ' ')" -ForegroundColor Gray
    } else {
        Write-Host "Executing: $backupScriptPath" -ForegroundColor Gray
    }
    Write-Host ""

    try {
        if ($Arguments.Count -gt 0) {
            & $backupScriptPath @Arguments
        } else {
            & $backupScriptPath
        }
        Write-Host ""
        Write-Host "✅ $Description completed successfully!" -ForegroundColor Green
    }
    catch {
        Write-Host ""
        Write-Host "❌ Error during $Description : $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
    Invoke-StandardPause
}

function Start-CodeCountBrowser {
    # Renamed from Start-CodeCount - this is the interactive file browser
    Start-CodeCount
}

function Show-EditConfigsMenu {
    # Define edit configs submenu
    $defaultMenu = @(
        (New-MenuAction "PowerShell Profile" {
            Invoke-Expression "code '$($script:Config.paths.profilePath)'"
            Invoke-StandardPause
        }),
        (New-MenuAction "Okta YAML" {
            Invoke-Expression "code '$($script:Config.paths.oktaYamlPath)'"
            Invoke-StandardPause
        }),
        (New-MenuAction "VS Code Settings" {
            # VS Code settings path (Scoop installation)
            $vscodeSettingsPath = "C:\AppInstall\scoop\persist\vscode\data\user-data\User\settings.json"
            if (Test-Path $vscodeSettingsPath) {
                Invoke-Expression "code '$vscodeSettingsPath'"
            } else {
                Write-Host "VS Code settings not found at: $vscodeSettingsPath" -ForegroundColor Yellow
            }
            Invoke-StandardPause
        })
    )

    # Load menu from config (or use default if not customized)
    $editConfigsMenuItems = Get-MenuFromConfig -MenuTitle "Edit Configs" -DefaultMenuItems $defaultMenu

    do {
        $choice = Show-ArrowMenu -MenuItems $editConfigsMenuItems -Title "Edit Configs"

        if ($choice -eq -1) {
            Write-Host "Returning to Main Menu..." -ForegroundColor Cyan
            return
        }

        # Execute the selected action
        $selectedAction = $editConfigsMenuItems[$choice]
        & $selectedAction.Action
    } while ($true)
}

function Show-CodeCountMenu {
    # Define code count submenu
    $defaultMenu = @(
        (New-MenuAction "Count Lines (Browser)" {
            Start-CodeCountBrowser
        }),
        (New-MenuAction "Manage Exclusions" {
            Edit-LineCounterExclusions
        })
    )

    # Load menu from config (or use default if not customized)
    $codeCountMenuItems = Get-MenuFromConfig -MenuTitle "Code Count" -DefaultMenuItems $defaultMenu

    do {
        $choice = Show-ArrowMenu -MenuItems $codeCountMenuItems -Title "Code Count"

        if ($choice -eq -1) {
            Write-Host "Returning to Main Menu..." -ForegroundColor Cyan
            return
        }

        # Execute the selected action
        $selectedAction = $codeCountMenuItems[$choice]
        & $selectedAction.Action
    } while ($true)
}


function Start-BackupTestMode {
    Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  BACKUP - TEST MODE                        ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    Write-Host "Test mode will preview a limited number of operations." -ForegroundColor Yellow
    Write-Host "Minimum limit: 100 items (default if not specified)" -ForegroundColor Gray
    Write-Host ""

    $limit = Read-Host "Enter test limit (press Enter for default 100)"

    if ([string]::IsNullOrWhiteSpace($limit)) {
        Invoke-BackupScript -Arguments @("--test-mode") -Description "Test mode"
    } else {
        Invoke-BackupScript -Arguments @("--test-mode", $limit) -Description "Test mode"
    }
}

function Start-BackupCountMode {
    Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  BACKUP - COUNT MODE                       ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    Write-Host "This will count all files and directories, then exit." -ForegroundColor Yellow
    Write-Host ""

    Invoke-BackupScript -Arguments @("--count") -Description "Count"
}

function Start-BackupDevEnvironment {
    Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  BACKUP - FULL BACKUP                      ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    $backupScriptPath = Get-BackupScriptPath
    if (-not $backupScriptPath) { return }

    Write-Host "This will create a full backup of your development environment." -ForegroundColor Yellow
    Write-Host "⚠️  WARNING: This will copy and sync all files!" -ForegroundColor Red
    Write-Host ""

    $confirm = Read-Host "Continue with full backup? (Y/n)"

    if ($confirm.ToLower() -eq "n") {
        Write-Host "Backup cancelled." -ForegroundColor Yellow
    Invoke-StandardPause
        return
    }

    Invoke-BackupScript -Description "Full backup"
}

function Show-DeprecatedBackupFiles {
    Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  BACKUP - DEPRECATED FILES                 ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    Write-Host "This will scan for files in the backup that:" -ForegroundColor Yellow
    Write-Host "  1. No longer exist in the source (deleted files)" -ForegroundColor Gray
    Write-Host "  2. Match current exclusion patterns (newly excluded)" -ForegroundColor Gray
    Write-Host ""

    $backupScriptPath = Get-BackupScriptPath
    if (-not $backupScriptPath) { return }

    # Load configuration
    $scriptDir = Split-Path -Parent $backupScriptPath
    $rootDir = Split-Path -Parent (Split-Path -Parent $scriptDir)
    $configPath = Join-Path $rootDir "config.json"

    if (-not (Test-Path $configPath)) {
        Write-Host "❌ Config file not found at: $configPath" -ForegroundColor Red
        Invoke-StandardPause
        return
    }

    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    $source = $config.paths.backupSource
    $destination = Join-Path $env:USERPROFILE $config.paths.backupDestination

    # Verify paths exist
    if (-not (Test-Path $source)) {
        Write-Host "❌ Source path not found: $source" -ForegroundColor Red
        Invoke-StandardPause
        return
    }

    if (-not (Test-Path $destination)) {
        Write-Host "❌ Backup destination not found: $destination" -ForegroundColor Red
        Invoke-StandardPause
        return
    }

    Write-Host "Scanning for deprecated files..." -ForegroundColor Cyan
    Write-Host "  Source: $source" -ForegroundColor Gray
    Write-Host "  Backup: $destination" -ForegroundColor Gray
    Write-Host ""

    # Run robocopy in list-only mode with /MIR to see what would be deleted
    $tempLog = Join-Path $env:TEMP "backup-deprecated-scan.txt"
    $null = robocopy "$source" "$destination" /L /MIR /R:0 /W:0 /LOG:"$tempLog" /NP /NDL /XJ 2>&1

    # Parse log for EXTRA files (files that exist in destination but not source)
    $extraFiles = @()
    $extraDirs = @()
    if (Test-Path $tempLog) {
        $logContent = Get-Content $tempLog
        $extraFiles = @($logContent | Where-Object { $_ -match '\*EXTRA File' })
        $extraDirs = @($logContent | Where-Object { $_ -match '\*EXTRA Dir' })
    }

    $extraFileCount = $extraFiles.Count
    $extraDirCount = $extraDirs.Count

    # --- Scan for files matching exclusion patterns using Python (faster) ---
    $excludedInBackup = @()
    $excludedDirsInBackup = @()

    $scanScript = Join-Path $scriptDir "scan-excluded.py"
    $scanResultFile = Join-Path $scriptDir "backup-scan-result.json"

    # Clean up any stale scan result file from previous runs
    if (Test-Path $scanResultFile) {
        Remove-Item $scanResultFile -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path $scanScript) {
        Write-Host "Scanning backup for items matching exclusion patterns..." -ForegroundColor Cyan

        try {
            # Scan and save result to file (for delete script to use later)
            # Don't suppress stderr so we can see Python errors
            $pythonOutput = python "$scanScript" "$destination" "$configPath" --output "$scanResultFile" 2>&1

            # Check if command succeeded
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  Warning: Python scan failed with exit code $LASTEXITCODE" -ForegroundColor Yellow
                if ($pythonOutput) {
                    Write-Host "  Error output: $pythonOutput" -ForegroundColor Yellow
                }
                throw "Python scan-excluded.py failed"
            }

            # Verify the JSON file was created and is readable
            if (-not (Test-Path $scanResultFile)) {
                throw "Scan result file was not created at: $scanResultFile"
            }

            $scanData = Get-Content $scanResultFile -Raw | ConvertFrom-Json

            if ($scanData.directories) {
                $excludedDirsInBackup = @($scanData.directories)
            }
            if ($scanData.files) {
                $excludedInBackup = @($scanData.files)
            }

            Write-Host "  Found $($excludedDirsInBackup.Count) excluded directories, $($excludedInBackup.Count) excluded files" -ForegroundColor Gray
        }
        catch {
            Write-Host "  Warning: Could not scan for excluded files: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "  Check that your config.json has the correct structure: backupDev.exclusions.{directories,files}" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  Warning: scan-excluded.py not found at: $scanScript" -ForegroundColor Yellow
    }

    $excludedFileCount = $excludedInBackup.Count
    $excludedDirCount = $excludedDirsInBackup.Count

    # Check if anything was found
    $totalFiles = $extraFileCount + $excludedFileCount
    $totalDirs = $extraDirCount + $excludedDirCount

    if ($totalFiles -eq 0 -and $totalDirs -eq 0) {
        Write-Host "✅ No deprecated files found! Backup is clean." -ForegroundColor Green
        Remove-Item $tempLog -Force -ErrorAction SilentlyContinue
        Invoke-StandardPause
        return
    }

    # Display summary
    Write-Host "Found deprecated items:" -ForegroundColor Yellow
    if ($extraFileCount -gt 0 -or $extraDirCount -gt 0) {
        Write-Host "  Deleted from source:" -ForegroundColor White
        Write-Host "    Files: $extraFileCount" -ForegroundColor Gray
        Write-Host "    Directories: $extraDirCount" -ForegroundColor Gray
    }
    if ($excludedFileCount -gt 0 -or $excludedDirCount -gt 0) {
        Write-Host "Matching exclusion patterns:" -ForegroundColor Magenta
        Write-Host "    Files: $excludedFileCount" -ForegroundColor Gray
        Write-Host "    Directories: $excludedDirCount" -ForegroundColor Gray
    }
    Write-Host ""

    # Show first 20 items as preview
    Write-Host "Preview (first 20 items):" -ForegroundColor Cyan
    $previewCount = 0

    # Show deleted files/dirs first
    foreach ($item in ($extraFiles + $extraDirs)) {
        if ($previewCount -ge 20) { break }
        if ($item -match '\*EXTRA (File|Dir)\s+(.+)$') {
            $type = $matches[1]
            $path = $matches[2].Trim()
            if ($type -eq "File") {
                Write-Host "  [F] $path" -ForegroundColor Gray
            } else {
                Write-Host "  [D] $path" -ForegroundColor DarkGray
            }
            $previewCount++
        }
    }

    # Show excluded items
    foreach ($dir in $excludedDirsInBackup) {
        if ($previewCount -ge 20) { break }
        Write-Host "  [D] $dir" -ForegroundColor Magenta
        $previewCount++
    }
    foreach ($file in $excludedInBackup) {
        if ($previewCount -ge 20) { break }
        Write-Host "  [F] $file" -ForegroundColor Magenta
        $previewCount++
    }

    if (($totalFiles + $totalDirs) -gt 20) {
        Write-Host "  ... and $(($totalFiles + $totalDirs) - 20) more" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "Options:" -ForegroundColor Cyan
    Write-Host "  1. View full list in VS Code" -ForegroundColor White
    Write-Host "  2. Clean deprecated files (DELETE them from backup)" -ForegroundColor Red
    Write-Host "  3. Cancel" -ForegroundColor Gray
    Write-Host ""

    $choice = Read-Host "Select option (1-3)"

    switch ($choice) {
        "1" {
            # Create a readable report
            $reportPath = Join-Path $env:TEMP "backup-deprecated-files.txt"
            $report = @()
            $report += "Deprecated Backup Files Report"
            $report += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            $report += "Source: $source"
            $report += "Backup: $destination"
            $report += ""
            $report += "Summary:"
            $report += "  Deleted from source:"
            $report += "    Files: $extraFileCount"
            $report += "    Directories: $extraDirCount"
            $report += "  Matching exclusion patterns:"
            $report += "    Files: $excludedFileCount"
            $report += "    Directories: $excludedDirCount"
            $report += ""
            $report += "=" * 80
            $report += ""

            if ($extraDirs.Count -gt 0) {
                $report += "DELETED DIRECTORIES ($extraDirCount):"
                $report += "-" * 80
                foreach ($item in $extraDirs) {
                    if ($item -match '\*EXTRA Dir\s+(.+)$') {
                        $report += "  $($matches[1].Trim())"
                    }
                }
                $report += ""
            }

            if ($extraFiles.Count -gt 0) {
                $report += "DELETED FILES ($extraFileCount):"
                $report += "-" * 80
                foreach ($item in $extraFiles) {
                    if ($item -match '\*EXTRA File\s+(.+)$') {
                        $report += "  $($matches[1].Trim())"
                    }
                }
                $report += ""
            }

            if ($excludedDirsInBackup.Count -gt 0) {
                $report += "EXCLUDED DIRECTORIES ($excludedDirCount):"
                $report += "-" * 80
                foreach ($dir in $excludedDirsInBackup) {
                    $report += "  $dir"
                }
                $report += ""
            }

            if ($excludedInBackup.Count -gt 0) {
                $report += "EXCLUDED FILES ($excludedFileCount):"
                $report += "-" * 80
                foreach ($file in $excludedInBackup) {
                    $report += "  $file"
                }
            }

            Set-Content -Path $reportPath -Value $report
            Invoke-Expression "code '$reportPath'"
            Write-Host "✅ Report opened in VS Code" -ForegroundColor Green
        }
        "2" {
            Write-Host ""
            Write-Host "⚠️  WARNING: This will PERMANENTLY DELETE $($totalFiles + $totalDirs) items from:" -ForegroundColor Red
            Write-Host "  $destination" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "This action CANNOT be undone!" -ForegroundColor Red
            Write-Host ""
            $confirm = Read-Host "Type 'DELETE' to confirm"

            if ($confirm -eq "DELETE") {
                Write-Host ""
                Write-Host "Cleaning deprecated files..." -ForegroundColor Yellow
                Write-Host ""

                # Pause OneDrive sync for faster deletion
                $oneDrivePaused = Suspend-OneDriveSync
                Write-Host ""

                $script:deletedDirs = 0
                $script:deletedFiles = 0

                # First, use robocopy to clean up files deleted from source
                if ($extraFileCount -gt 0 -or $extraDirCount -gt 0) {
                    Write-Host "Removing items deleted from source..." -ForegroundColor Cyan

                    # Create a temporary log for the cleanup operation
                    $cleanupLog = Join-Path $env:TEMP "backup-cleanup.txt"

                    # Start robocopy in background with verbose logging
                    $cleanupJob = Start-Job -ScriptBlock {
                        param($src, $dst, $log)
                        # Use /TEE to write to both log and stdout for progress monitoring
                        $cmd = "robocopy `"$src`" `"$dst`" /MIR /R:3 /W:5 /LOG:`"$log`" /NP /XJ /X 2>&1"
                        Invoke-Expression $cmd
                    } -ArgumentList $source, $destination, $cleanupLog

                    $robocopyDeletedDirs = 0
                    $robocopyDeletedFiles = 0
                    $startTime = Get-Date
                    $totalExpected = $extraDirCount + $extraFileCount
                    $spinnerChars = @('|', '/', '-', '\')
                    $spinnerIndex = 0
                    $lastLogSize = 0

                    # Monitor job progress with activity indicator
                    while ($cleanupJob.State -eq 'Running') {
                        Start-Sleep -Milliseconds 250

                        $elapsed = (Get-Date) - $startTime
                        $elapsedStr = "{0:mm\:ss}" -f $elapsed
                        $spinner = $spinnerChars[$spinnerIndex % 4]
                        $spinnerIndex++

                        # Try to read current progress from log file
                        $currentProcessed = 0
                        if (Test-Path $cleanupLog) {
                            try {
                                # Check file size as activity indicator
                                $logFile = Get-Item $cleanupLog -ErrorAction SilentlyContinue
                                if ($logFile) {
                                    $currentLogSize = $logFile.Length
                                    if ($currentLogSize -ne $lastLogSize) {
                                        $lastLogSize = $currentLogSize

                                        # Try to count EXTRA entries
                                        $logStream = [System.IO.FileStream]::new($cleanupLog, 'Open', 'Read', 'ReadWrite')
                                        $reader = New-Object System.IO.StreamReader($logStream)
                                        $logContent = $reader.ReadToEnd()
                                        $reader.Close()
                                        $logStream.Close()

                                        $currentProcessed = ([regex]::Matches($logContent, '\*EXTRA')).Count
                                    }
                                }
                            } catch {
                                # Log locked, continue with spinner
                            }
                        }

                        # Show progress with spinner
                        if ($totalExpected -gt 0 -and $currentProcessed -gt 0) {
                            $pct = [math]::Min([math]::Floor(($currentProcessed / $totalExpected) * 100), 100)
                            Write-Host "`r  $spinner Progress: $pct% | Processed: $currentProcessed / $totalExpected | Elapsed: $elapsedStr" -NoNewline -ForegroundColor Yellow
                        } else {
                            Write-Host "`r  $spinner Working... | Expected: $totalExpected items | Elapsed: $elapsedStr" -NoNewline -ForegroundColor Yellow
                        }
                    }

                    # Wait for job to complete
                    $null = Receive-Job $cleanupJob -Wait -AutoRemoveJob

                    # Final count from robocopy log
                    if (Test-Path $cleanupLog) {
                        try {
                            $logContent = Get-Content $cleanupLog -Raw -ErrorAction SilentlyContinue
                            # Count EXTRA Dir and EXTRA File separately
                            $robocopyDeletedDirs = ([regex]::Matches($logContent, '\*EXTRA Dir')).Count
                            $robocopyDeletedFiles = ([regex]::Matches($logContent, '\*EXTRA File')).Count
                        } catch {
                            # Use expected counts as fallback
                            $robocopyDeletedDirs = $extraDirCount
                            $robocopyDeletedFiles = $extraFileCount
                        }
                        Remove-Item $cleanupLog -Force -ErrorAction SilentlyContinue
                    }

                    Write-Host "`r                                                                                        " -NoNewline
                    Write-Host "`r  Removed $robocopyDeletedDirs deleted dirs, $robocopyDeletedFiles deleted files" -ForegroundColor Gray

                    $script:deletedDirs += $robocopyDeletedDirs
                    $script:deletedFiles += $robocopyDeletedFiles
                }

                # Then, delete excluded items (files that exist in source but are now excluded)
                if ($excludedDirsInBackup.Count -gt 0 -or $excludedInBackup.Count -gt 0) {
                    Write-Host "Removing items matching exclusion patterns..." -ForegroundColor Cyan

                    # Use Python delete script with scan result file
                    $deleteScript = Join-Path $scriptDir "delete-excluded.py"
                    $scanResultFile = Join-Path $scriptDir "backup-scan-result.json"
                    $deleteResultFile = Join-Path $scriptDir "backup-delete-result.json"

                    if ((Test-Path $deleteScript) -and (Test-Path $scanResultFile)) {
                        try {
                            # Run delete script directly - output streams to console in real-time
                            # Use Start-Process with -Wait and -NoNewWindow for live progress display
                            $null = Start-Process -FilePath "python" `
                                -ArgumentList "`"$deleteScript`" `"$destination`" `"$scanResultFile`" --output `"$deleteResultFile`"" `
                                -NoNewWindow -Wait -PassThru

                            # Read result from output file
                            if (Test-Path $deleteResultFile) {
                                $deleteData = Get-Content $deleteResultFile -Raw | ConvertFrom-Json
                                $excludedDeletedDirs = $deleteData.deleted_dirs
                                $excludedDeletedFiles = $deleteData.deleted_files

                                # Check for errors
                                if ($deleteData.errors -and $deleteData.errors.Count -gt 0) {
                                    $errorCount = $deleteData.errors.Count
                                    Write-Host ""
                                    Write-Host "  ⚠️  Warning: $errorCount items failed to delete" -ForegroundColor Yellow

                                    # Show first 5 errors inline
                                    $displayCount = [Math]::Min(5, $errorCount)
                                    for ($i = 0; $i -lt $displayCount; $i++) {
                                        Write-Host "    $($deleteData.errors[$i])" -ForegroundColor Gray
                                    }

                                    if ($errorCount -gt 5) {
                                        Write-Host "    ... and $($errorCount - 5) more errors" -ForegroundColor DarkGray
                                    }

                                    # Save full error list to file for review
                                    $errorLogPath = Join-Path $scriptDir "backup-deletion-errors.log"
                                    $errorReport = @()
                                    $errorReport += "Backup Deletion Errors"
                                    $errorReport += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                                    $errorReport += "Backup: $destination"
                                    $errorReport += ""
                                    $errorReport += "Total Errors: $errorCount"
                                    $errorReport += "=" * 80
                                    $errorReport += ""
                                    foreach ($err in $deleteData.errors) {
                                        $errorReport += $err
                                    }
                                    Set-Content -Path $errorLogPath -Value $errorReport
                                    Write-Host "    Full error log saved to: $errorLogPath" -ForegroundColor Cyan
                                    Write-Host ""
                                }

                                Remove-Item $deleteResultFile -Force -ErrorAction SilentlyContinue
                            }

                            # Clean up scan result file
                            Remove-Item $scanResultFile -Force -ErrorAction SilentlyContinue
                        } catch {
                            Write-Host "  Warning: Python deletion failed ($_), using fallback method..." -ForegroundColor Yellow
                            # Fall through to PowerShell fallback
                            $useFallback = $true
                        }
                    } else {
                        $useFallback = $true
                    }

                    # PowerShell fallback
                    if ($useFallback) {
                        $excludedDeletedDirs = 0
                        $excludedDeletedFiles = 0
                        $totalItems = $excludedDirsInBackup.Count + $excludedInBackup.Count
                        $processed = 0

                        foreach ($dir in $excludedDirsInBackup) {
                            $fullPath = Join-Path $destination $dir
                            if (Test-Path $fullPath) {
                                try {
                                    Remove-Item -Path $fullPath -Recurse -Force -ErrorAction Stop
                                    $excludedDeletedDirs++
                                } catch {
                                    Write-Host "  Failed to delete: $dir" -ForegroundColor Red
                                }
                            }
                            $processed++
                            $pct = [math]::Floor(($processed / $totalItems) * 100)
                            Write-Host "`r  Progress: $pct% | Deleted: $excludedDeletedDirs dirs, $excludedDeletedFiles files" -NoNewline -ForegroundColor Yellow
                        }

                        foreach ($file in $excludedInBackup) {
                            $fullPath = Join-Path $destination $file
                            if (Test-Path $fullPath) {
                                try {
                                    Remove-Item -Path $fullPath -Force -ErrorAction Stop
                                    $excludedDeletedFiles++
                                } catch {
                                    Write-Host "  Failed to delete: $file" -ForegroundColor Red
                                }
                            }
                            $processed++
                            $pct = [math]::Floor(($processed / $totalItems) * 100)
                            Write-Host "`r  Progress: $pct% | Deleted: $excludedDeletedDirs dirs, $excludedDeletedFiles files" -NoNewline -ForegroundColor Yellow
                        }
                        Write-Host ""
                    }

                    Write-Host "  Removed $excludedDeletedDirs excluded dirs, $excludedDeletedFiles excluded files" -ForegroundColor Gray

                    $script:deletedDirs += $excludedDeletedDirs
                    $script:deletedFiles += $excludedDeletedFiles
                }

            # Resume OneDrive sync
            if ($oneDrivePaused) {
                Write-Host ""
                Resume-OneDriveSync
            }

            Write-Host ""
            Write-Host "✅ Cleanup complete! Total deleted: $($script:deletedDirs) dirs, $($script:deletedFiles) files" -ForegroundColor Green
        } else {
            Write-Host "Cleanup cancelled." -ForegroundColor Yellow
        }
    }
    default {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
    }
    }

    Remove-Item $tempLog -Force -ErrorAction SilentlyContinue
    Invoke-StandardPause
}

function Open-BackupDetailedLog {
    $backupScriptPath = Get-BackupScriptPath
    if (-not $backupScriptPath) { return }

    $scriptDir = Split-Path -Parent $backupScriptPath
    $detailedLog = Join-Path $scriptDir "backup-dev.log"

    if (Test-Path $detailedLog) {
        Invoke-Expression "code '$detailedLog'"
    } else {
        Write-Host "No detailed log found at: $detailedLog" -ForegroundColor Yellow
    }
    Invoke-StandardPause
}

function Open-BackupHistoryLog {
    $backupScriptPath = Get-BackupScriptPath
    if (-not $backupScriptPath) { return }

    $scriptDir = Split-Path -Parent $backupScriptPath
    $historyLog = Join-Path $scriptDir "backup-history.log"

    if (Test-Path $historyLog) {
        Invoke-Expression "code '$historyLog'"
    } else {
        Write-Host "No history log found at: $historyLog" -ForegroundColor Yellow
    }
    Invoke-StandardPause
}

function Show-BackupDevMenu {
    # Define backup submenu
    $defaultMenu = @(
        (New-MenuAction "Dry Run (Simulate Backup)" {
            Start-BackupDryRun
        }),
        (New-MenuAction "Count Mode (Quantify Source)" {
            Start-BackupCountMode
        }),
        (New-MenuAction "Test Mode (Limited Preview)" {
            Start-BackupTestMode
        }),
        (New-MenuAction "Full Backup" {
            Start-BackupDevEnvironment
        }),
        (New-MenuAction "View Detailed Log" {
            Open-BackupDetailedLog
        }),
        (New-MenuAction "View Backup History" {
            Open-BackupHistoryLog
        }),
        (New-MenuAction "Scan Deprecated Files" {
            Show-DeprecatedBackupFiles
        }),
        (New-MenuAction "Manage Exclusions" {
            Edit-BackupExclusions
        })
    )

    # Load menu from config (or use default if not customized)
    $backupMenuItems = Get-MenuFromConfig -MenuTitle "Backup Dev Environment" -DefaultMenuItems $defaultMenu

    do {
        # Get last backup timestamp for header
        $lastBackup = Get-LastBackupTimestamp
        $headerLines = @()
        if ($lastBackup) {
            $timeAgo = (Get-Date) - $lastBackup
            if ($timeAgo.Days -gt 0) {
                $timeAgoStr = "$($timeAgo.Days) day(s) ago"
            } elseif ($timeAgo.Hours -gt 0) {
                $timeAgoStr = "$($timeAgo.Hours) hour(s) ago"
            } else {
                $timeAgoStr = "$($timeAgo.Minutes) minute(s) ago"
            }
            $headerLines = @(
                "Last full backup: $($lastBackup.ToString('yyyy-MM-dd HH:mm:ss')) ($timeAgoStr)"
            )
        } else {
            $headerLines = @("Last full backup: Never")
        }

        $choice = Show-ArrowMenu -MenuItems $backupMenuItems -Title "Backup Dev Environment" -HeaderLines $headerLines

        if ($choice -eq -1) {
            Write-Host "Returning to Main Menu..." -ForegroundColor Cyan
            return
        }

        # Execute the selected action
        $selectedAction = $backupMenuItems[$choice]
        & $selectedAction.Action

    } while ($true)
}

function Show-MainMenu {
    # Initialize default connection settings
    $global:awsInstance = $script:Config.defaultConnection.instance
    $global:remoteIP = $script:Config.defaultConnection.remoteIP
    $global:localPort = $script:Config.defaultConnection.localPort
    $global:remotePort = $script:Config.defaultConnection.remotePort

    # Define default menu
    $defaultMenu = @(
        (New-MenuAction "Ping Google" {
            Start-InteractivePing -Target "google.com"
    Invoke-StandardPause
        }),
        (New-MenuAction "IP Config" {
            Show-NetworkConfiguration
    Invoke-StandardPause
        }),
        (New-MenuAction "AWS Login" {
            Start-AwsWorkflow
        }),
        (New-MenuAction "Edit Configs" {
            Show-EditConfigsMenu
        }),
        (New-MenuAction "Whitelist Links Folder" {
            Invoke-Expression "icacls '$($script:Config.paths.linksPath)' /t /setintegritylevel m"
    Invoke-StandardPause
        }),
        (New-MenuAction "Meraki Backup" {
            Start-MerakiBackup
        }),
        (New-MenuAction "Code Count" {
            Show-CodeCountMenu
        }),
        (New-MenuAction "Backup Dev Environment" {
            Show-BackupDevMenu
        }),
        (New-MenuAction "Package Manager" {
            Show-PackageManagerMenu
        })
    )

    # Load menu from config (or use default if not customized)
    $menuItems = Get-MenuFromConfig -MenuTitle "Main Menu" -DefaultMenuItems $defaultMenu

    do {
        $choice = Show-ArrowMenu -MenuItems $menuItems -Title "Main Menu"

        if ($choice -eq -1) {
            Write-Host "Exiting script. Goodbye!" -ForegroundColor Cyan
            Start-Sleep -Seconds 1
            Restore-ConsoleState
            break
        }

        # Execute the selected action
        $selectedAction = $menuItems[$choice]
        & $selectedAction.Action

    } while ($true)
}

function Start-AwsWorkflow {
    # Step 1: Choose AWS Account/Environment
    Show-AwsAccountMenu
}

function Invoke-AwsAuthentication {
    param(
        [string]$Environment,
        [string]$Region,
        [string]$OktaCommand,
        [string]$ProfileName = $null
    )

    try {
        # Set AWS region for this session
        $env:AWS_DEFAULT_REGION = $Region

        Write-Host "Executing: $OktaCommand" -ForegroundColor Gray

        # Validate command is not empty
        if ([string]::IsNullOrWhiteSpace($OktaCommand)) {
            throw "Okta command is empty or null"
        }

        # Execute directly in current session instead of spawning new process
        Invoke-Expression $OktaCommand

        Write-Host "Authentication completed successfully!" -ForegroundColor Green
        Write-Host "Current AWS Region: $Region" -ForegroundColor Cyan

        # Store current environment context and AWS profile name
        $global:currentAwsEnvironment = $Environment
        $global:currentAwsRegion = $Region
        $global:currentAwsProfile = if ($ProfileName) { $ProfileName } else { $Environment }

        # For manual login, try to get account info
        if ($Environment -eq "manual") {
            try {
                $accountInfo = aws sts get-caller-identity --query "Account" --output text 2>$null
                if ($accountInfo) {
                    Write-Host "Connected to AWS Account: $accountInfo" -ForegroundColor Cyan
                }
            }
            catch {
                # Ignore if we can't get account info
            }
        }

        # Pause to allow user to see any authentication messages/errors
        Write-Host ""
        Write-Host "Continuing to Instance Management (press any key to continue immediately)..." -ForegroundColor Yellow
        Write-Host ""

        # Wait for 5 seconds with spinner and countdown
        $timeout = 5
        $spinnerChars = @('|', '/', '-', '\')
        $spinnerIndex = 0
        $timer = [Diagnostics.Stopwatch]::StartNew()

        while ($timer.Elapsed.TotalSeconds -lt $timeout) {
            if ([Console]::KeyAvailable) {
                $null = [Console]::ReadKey($true)
                break
            }

            # Calculate remaining time
            $remaining = [math]::Ceiling($timeout - $timer.Elapsed.TotalSeconds)

            # Display spinner and countdown
            $spinner = $spinnerChars[$spinnerIndex % 4]
            Write-Host "`r$spinner Continuing in $remaining seconds... " -NoNewline -ForegroundColor Cyan

            $spinnerIndex++
            Start-Sleep -Milliseconds 100
        }
        $timer.Stop()

        # Clear the countdown line
        Write-Host "`r                                        " -NoNewline
        Write-Host "`r" -NoNewline

        # Go directly to Instance Management (AWS Actions menu deprecated)
        Show-InstanceManagementMenu

        # After returning from Instance Management, return to account menu
        return
    }
    catch {
        Write-Host "Authentication failed: $($_.Exception.Message)" -ForegroundColor Red
    Invoke-StandardPause
        return
    }
}

function Select-AwsRole {
    param(
        [string]$Environment,
        [array]$AvailableRoles,
        [string]$PreferredRole
    )

    Write-Host ""
    Write-Host "Multiple roles available for $Environment" -ForegroundColor Yellow
    Write-Host ""

    # Create menu items for each role
    $roleMenuItems = @()
    foreach ($role in $AvailableRoles) {
        $displayText = if ($role -eq $PreferredRole) {
            "$role (Current Preference)"
        } else {
            $role
        }
        $roleMenuItems += New-MenuAction $displayText { $role }.GetNewClosure()
    }

    $choice = Show-ArrowMenu -MenuItems $roleMenuItems -Title "Select AWS Role"

    if ($choice -eq -1) {
        return $null
    }

    return $AvailableRoles[$choice]
}

function Set-PreferredRole {
    param(
        [string]$Environment,
        [string]$Role
    )

    # Store the selected role preference in config.json
    $configPath = Join-Path $PSScriptRoot "config.json"
    $config = Get-Content $configPath -Raw | ConvertFrom-Json

    if ($config.environments.$Environment.PSObject.Properties['preferredRole']) {
        $config.environments.$Environment.preferredRole = $Role
    } else {
        $config.environments.$Environment | Add-Member -NotePropertyName 'preferredRole' -NotePropertyValue $Role -Force
    }

    # Save back to config.json
    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
}

function Start-AwsLoginForAccount {
    param(
        [string]$Environment,
        [string]$Region,
        [string]$PreselectedRole = $null
    )

    Write-Host "Authenticating with AWS Account: $Environment ($Region)" -ForegroundColor Cyan

    # Check if this account has multiple roles configured
    $envConfig = $script:Config.environments.$Environment
    $selectedRole = $PreselectedRole

    # If no role was preselected and account has multiple roles, prompt user
    if (-not $selectedRole -and $envConfig.PSObject.Properties['availableRoles'] -and $envConfig.availableRoles.Count -gt 1) {
        # Multiple roles available - prompt user to select
        $preferredRole = if ($envConfig.PSObject.Properties['preferredRole']) { $envConfig.preferredRole } else { $envConfig.availableRoles[0] }

        $selectedRole = Select-AwsRole -Environment $Environment -AvailableRoles $envConfig.availableRoles -PreferredRole $preferredRole

        if (-not $selectedRole) {
            Write-Host "Role selection cancelled. Returning to menu." -ForegroundColor Yellow
            return
        }

        # If user selected a different role than the current preference, update it
        if ($selectedRole -ne $preferredRole) {
            Set-PreferredRole -Environment $Environment -Role $selectedRole
            Write-Host "✓ Updated preferred role to: $selectedRole" -ForegroundColor Green
        }

        Write-Host "Using role: $selectedRole" -ForegroundColor Cyan
    }
    elseif ($selectedRole) {
        Write-Host "Using role: $selectedRole" -ForegroundColor Cyan
    }

    # Build okta command using the appropriate profile
    $oktaProfile = $null
    if ($selectedRole -and $envConfig.PSObject.Properties['oktaProfileMap']) {
        # Use the role-specific profile from the mapping
        $oktaProfile = $envConfig.oktaProfileMap.$selectedRole
        if ($oktaProfile) {
            Write-Host "Using Okta profile: $oktaProfile" -ForegroundColor Gray
            $oktaCommand = "okta-aws-cli web --profile $oktaProfile"
        } else {
            Write-Host "Warning: No profile mapping found for role $selectedRole, using default profile" -ForegroundColor Yellow
            $oktaCommand = "okta-aws-cli web --profile $Environment"
            $oktaProfile = $Environment
        }
    } else {
        $oktaCommand = "okta-aws-cli web --profile $Environment"
        $oktaProfile = $Environment
    }

    # Add session duration if configured
    if ($envConfig.PSObject.Properties['sessionDuration']) {
        $oktaCommand += " --aws-session-duration $($envConfig.sessionDuration)"
        Write-Host "Using session duration: $($envConfig.sessionDuration)" -ForegroundColor Gray
    }

    Invoke-AwsAuthentication -Environment $Environment -Region $Region -OktaCommand $oktaCommand -ProfileName $oktaProfile
}

function Start-ManualAwsLogin {
    Write-Host "Manual AWS Login - You will select account in browser" -ForegroundColor Cyan

    $oktaCommand = "okta-aws-cli web"
    Invoke-AwsAuthentication -Environment "manual" -Region "unknown" -OktaCommand $oktaCommand
}

function Backup-ConfigFile {
    param([string]$FilePath)

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = "$FilePath.backup-$timestamp"

    try {
        Copy-Item -Path $FilePath -Destination $backupPath -Force
        return $backupPath
    }
    catch {
        Write-Host "Warning: Could not create backup of $FilePath" -ForegroundColor Yellow
        return $null
    }
}

function Parse-AwsCredentialsFile {
    $credsPath = Join-Path $env:USERPROFILE ".aws\credentials"

    if (-not (Test-Path $credsPath)) {
        Write-Host "AWS credentials file not found at: $credsPath" -ForegroundColor Red
        return @()
    }

    $content = Get-Content $credsPath -Raw
    $profiles = @()

    # Parse profiles from credentials file
    $profileMatches = [regex]::Matches($content, '\[([^\]]+)\]')

    foreach ($match in $profileMatches) {
        $profileName = $match.Groups[1].Value
        $profiles += $profileName
    }

    return $profiles
}

function Get-OktaIdpMapping {
    $oktaYamlPath = $script:Config.paths.oktaYamlPath

    if (-not (Test-Path $oktaYamlPath)) {
        Write-Host "Okta YAML file not found at: $oktaYamlPath" -ForegroundColor Red
        return @{}
    }

    $content = Get-Content $oktaYamlPath -Raw
    $idpMap = @{}

    # Parse IDP mappings: "arn:aws:iam::123456789012:saml-provider/CFA-OKTA-PROD": "friendlyname"
    $idpMatches = [regex]::Matches($content, '"arn:aws:iam::(\d+):saml-provider/[^"]+"\s*:\s*"([^"]+)"')

    foreach ($match in $idpMatches) {
        $accountId = $match.Groups[1].Value
        $friendlyName = $match.Groups[2].Value
        $idpMap[$accountId] = $friendlyName
    }

    return $idpMap
}

function Get-AccountRolesFromProfile {
    param([string]$ProfileName)

    # Try to get account ID and role from the profile by doing a quick STS call
    try {
        $identity = aws sts get-caller-identity --profile $ProfileName --output json 2>$null | ConvertFrom-Json
        if ($identity -and $identity.Arn) {
            # Parse ARN: arn:aws:sts::123456789012:assumed-role/RoleName/session
            if ($identity.Arn -match 'arn:aws:sts::(\d+):assumed-role/([^/]+)/') {
                return @{
                    AccountId = $matches[1]
                    Role = $matches[2]
                    Valid = $true
                }
            }
        }
    }
    catch {
        # Profile might be expired or invalid
    }

    return @{ Valid = $false }
}

function Sync-AwsAccountsFromOkta {
    Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "║  SYNC AWS ACCOUNTS FROM OKTA               ║" -ForegroundColor Magenta
    Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Magenta

    Write-Host "This will:" -ForegroundColor Yellow
    Write-Host "  1. Authenticate to Okta and collect all available AWS profiles" -ForegroundColor White
    Write-Host "  2. Parse your AWS credentials to discover accounts and roles" -ForegroundColor White
    Write-Host "  3. Compare with your current config.json" -ForegroundColor White
    Write-Host "  4. Show you what will change" -ForegroundColor White
    Write-Host "  5. Update config.json and okta.yaml (after confirmation)" -ForegroundColor White
    Write-Host ""

    $confirm = Read-Host "Continue with sync? (Y/n)"
    if ($confirm.ToLower() -eq "n") {
        Write-Host "Sync cancelled." -ForegroundColor Yellow
    Invoke-StandardPause
        return
    }

    # Step 1: Backup current config files
    Write-Host "`n══ Step 1: Backing up configuration files ══" -ForegroundColor Cyan
    $configPath = Join-Path $PSScriptRoot "config.json"
    $oktaYamlPath = $script:Config.paths.oktaYamlPath

    $configBackup = Backup-ConfigFile -FilePath $configPath
    $oktaBackup = Backup-ConfigFile -FilePath $oktaYamlPath

    if ($configBackup) {
        Write-Host "✓ Config backup: $configBackup" -ForegroundColor Green
    }
    if ($oktaBackup) {
        Write-Host "✓ Okta YAML backup: $oktaBackup" -ForegroundColor Green
    }

    # Step 2: Run okta-aws-cli to collect all profiles
    Write-Host "`n══ Step 2: Authenticating to Okta ══" -ForegroundColor Cyan
    Write-Host "Running: okta-aws-cli web --all-profiles --aws-session-duration 3600" -ForegroundColor Gray
    Write-Host "This will open your browser for authentication..." -ForegroundColor Yellow
    Write-Host ""

    # Always use 1-hour session duration to avoid re-authentication
    $oktaOutput = okta-aws-cli web --all-profiles --aws-session-duration 3600 2>&1 | Out-String
    Write-Host $oktaOutput

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: okta-aws-cli failed with exit code $LASTEXITCODE" -ForegroundColor Red
    Invoke-StandardPause
        return
    }

    # Step 3: Parse okta-aws-cli output to discover accounts
    Write-Host "`n══ Step 3: Parsing Okta output for discovered accounts ══" -ForegroundColor Cyan

    # Get IDP mappings from okta.yaml
    $idpMap = Get-OktaIdpMapping

    # Parse "Updated profile" lines from okta output
    # Example: Updated profile "exampleaccount-CFA-OKTA-PROD-Admin" in credentials file
    $discoveredAccounts = @{}
    $profileMatches = [regex]::Matches($oktaOutput, 'Updated profile "([^"]+)"')

    Write-Host "Found $($profileMatches.Count) profile(s) from Okta" -ForegroundColor Green
    Write-Host ""

    foreach ($match in $profileMatches) {
        $profileName = $match.Groups[1].Value

        # Parse profile name format: friendlyname-CFA-OKTA-PROD-RoleName
        # or: friendlyname-CFA-OKTA-PROD-RoleName
        if ($profileName -match '^(.+?)-CFA-OKTA-PROD-(.+)$') {
            $friendlyName = $matches[1]
            $roleName = $matches[2]

            # Try to find account ID from okta.yaml idps section (reverse lookup with normalization)
            # $idpMap is @{ accountId => friendlyName }, so we need to find the key by value
            # Normalize both sides by removing hyphens/underscores and lowercasing
            $accountId = $null
            $normalizedFriendly = ($friendlyName -replace '-', '' -replace '_', '').ToLower()

            foreach ($acctId in $idpMap.Keys) {
                $normalizedMapName = ($idpMap[$acctId] -replace '-', '' -replace '_', '').ToLower()
                if ($normalizedMapName -eq $normalizedFriendly) {
                    $accountId = $acctId
                    # Use the friendly name from okta.yaml (preferred naming)
                    $friendlyName = $idpMap[$acctId]
                    break
                }
            }

            if (-not $accountId) {
                # Try to get account ID from AWS credentials file
                try {
                    $identity = aws sts get-caller-identity --profile $profileName --output json 2>$null | ConvertFrom-Json
                    if ($identity -and $identity.Account) {
                        $accountId = $identity.Account
                        Write-Host "  Discovered account ID from credentials: $friendlyName ($accountId) - Role: $roleName" -ForegroundColor Cyan

                        # Add to IDP map for future use
                        $idpMap[$accountId] = $friendlyName
                    } else {
                        Write-Host "  Warning: Could not determine account ID for profile: $profileName" -ForegroundColor Yellow
                        continue
                    }
                } catch {
                    Write-Host "  Warning: Could not determine account ID for profile: $profileName" -ForegroundColor Yellow
                    continue
                }
            }

            if (-not $discoveredAccounts.ContainsKey($accountId)) {
                $discoveredAccounts[$accountId] = @{
                    FriendlyName = $friendlyName
                    Profiles = @()
                    Roles = @()
                    RoleMaxDurations = @{}
                }
            }

            $discoveredAccounts[$accountId].Profiles += $profileName
            if ($discoveredAccounts[$accountId].Roles -notcontains $roleName) {
                $discoveredAccounts[$accountId].Roles += $roleName
            }

            Write-Host "  Discovered: $friendlyName ($accountId) - Role: $roleName" -ForegroundColor Green
        }
    }

    # Step 3.5: Discover role max session durations
    Write-Host "`n══ Step 3.5: Discovering role session durations ══" -ForegroundColor Cyan
    Write-Host ""

    foreach ($accountId in $discoveredAccounts.Keys) {
        $info = $discoveredAccounts[$accountId]

        foreach ($roleName in $info.Roles) {
            # Find a profile that uses this role
            $sampleProfile = $info.Profiles | Where-Object { $_ -match "-${roleName}$" } | Select-Object -First 1

            if ($sampleProfile) {
                try {
                    Write-Host "  Querying role: $roleName in $($info.FriendlyName)..." -ForegroundColor Gray -NoNewline

                    $roleInfo = aws iam get-role --role-name $roleName --profile $sampleProfile --output json 2>$null | ConvertFrom-Json

                    if ($roleInfo -and $roleInfo.Role.MaxSessionDuration) {
                        $maxDuration = $roleInfo.Role.MaxSessionDuration
                        $info.RoleMaxDurations[$roleName] = $maxDuration

                        $hours = [math]::Floor($maxDuration / 3600)
                        $minutes = [math]::Floor(($maxDuration % 3600) / 60)

                        if ($minutes -gt 0) {
                            Write-Host " ${hours}h ${minutes}m ($maxDuration seconds)" -ForegroundColor Green
                        } else {
                            Write-Host " ${hours}h ($maxDuration seconds)" -ForegroundColor Green
                        }
                    } else {
                        Write-Host " using default 1h (3600 seconds)" -ForegroundColor Yellow
                        $info.RoleMaxDurations[$roleName] = 3600
                    }
                } catch {
                    Write-Host " error, using default 1h" -ForegroundColor Yellow
                    $info.RoleMaxDurations[$roleName] = 3600
                }
            } else {
                # No profile found for this role (shouldn't happen, but fallback)
                $info.RoleMaxDurations[$roleName] = 3600
            }
        }
    }

    # Step 4: Show discovered accounts summary
    Write-Host "`n══ Step 4: Discovered Accounts Summary ══" -ForegroundColor Cyan
    Write-Host ""

    foreach ($accountId in $discoveredAccounts.Keys) {
        $info = $discoveredAccounts[$accountId]
        Write-Host "Account $accountId ($($info.FriendlyName))`:" -ForegroundColor Yellow
        Write-Host "  Roles: $($info.Roles -join ', ')" -ForegroundColor White
        Write-Host "  Profiles: $($info.Profiles -join ', ')" -ForegroundColor Gray
        Write-Host ""
    }

    # Step 5: Compare with existing config and update
    Write-Host "`n══ Step 5: Updating configuration files ══" -ForegroundColor Cyan
    Write-Host ""

    # Load current config (IDP mappings already loaded earlier)
    $config = Get-Content $configPath -Raw | ConvertFrom-Json

    # Track changes
    $newAccounts = @()
    $updatedAccounts = @()

    # Process each discovered account
    foreach ($accountId in $discoveredAccounts.Keys) {
        $info = $discoveredAccounts[$accountId]

        # Use friendly name from discovered accounts
        $friendlyName = $info.FriendlyName

        # Try to find existing environment for this account
        $existingEnv = $null
        $wrongKeyEnv = $null
        $matchByName = $null

        foreach ($envKey in $config.environments.PSObject.Properties.Name) {
            $env = $config.environments.$envKey
            if ($env.PSObject.Properties['accountId'] -and $env.accountId -eq $accountId) {
                $existingEnv = $envKey
                # Check if the key name needs to be updated to match Okta friendly name
                if ($envKey -ne $friendlyName) {
                    $wrongKeyEnv = $envKey
                }
                break
            }
        }

        # If not found by accountId, try to find by matching the friendly name pattern
        # (handles cases where old entry exists without accountId)
        if (-not $existingEnv) {
            foreach ($envKey in $config.environments.PSObject.Properties.Name) {
                # Check if the key is similar to friendly name (case-insensitive, ignore hyphens)
                $normalizedKey = ($envKey -replace '-', '' -replace '_', '').ToLower()
                $normalizedFriendly = ($friendlyName -replace '-', '' -replace '_', '').ToLower()

                if ($normalizedKey -eq $normalizedFriendly) {
                    $matchByName = $envKey
                    break
                }
            }
        }

        # Check for duplicate entries - ALWAYS check for normalized name matches
        $duplicateEntry = $null
        $normalizedFriendly = ($friendlyName -replace '-', '' -replace '_', '').ToLower()

        foreach ($envKey in $config.environments.PSObject.Properties.Name) {
            # Skip the entry we already found (if any)
            if ($existingEnv -and $envKey -eq $existingEnv) {
                continue
            }

            # Check for normalized name match
            $normalizedKey = ($envKey -replace '-', '' -replace '_', '').ToLower()
            if ($normalizedKey -eq $normalizedFriendly) {
                $duplicateEntry = $envKey
                break
            }
        }

        # If we found an account with wrong key name, rename it
        if ($wrongKeyEnv) {
            Write-Host "  Renaming account $accountId from '$wrongKeyEnv' to '$friendlyName'" -ForegroundColor Yellow

            # Check if target name already exists (might be a duplicate without accountId)
            $targetExists = $config.environments.PSObject.Properties[$friendlyName]

            if ($targetExists) {
                # Merge: Keep the one with more data, add accountId and roles to it
                Write-Host "    Merging with existing '$friendlyName' entry" -ForegroundColor Gray

                # Add accountId if missing
                if (-not $config.environments.$friendlyName.PSObject.Properties['accountId']) {
                    $config.environments.$friendlyName | Add-Member -NotePropertyName 'accountId' -NotePropertyValue $accountId -Force
                }

                # Add roles if missing
                if (-not $config.environments.$friendlyName.PSObject.Properties['availableRoles']) {
                    $config.environments.$friendlyName | Add-Member -NotePropertyName 'availableRoles' -NotePropertyValue $info.Roles -Force
                    $config.environments.$friendlyName | Add-Member -NotePropertyName 'preferredRole' -NotePropertyValue $info.Roles[0] -Force
                }

                # Add profile map if missing
                if (-not $config.environments.$friendlyName.PSObject.Properties['oktaProfileMap']) {
                    $config.environments.$friendlyName | Add-Member -NotePropertyName 'oktaProfileMap' -NotePropertyValue @{} -Force
                }

                foreach ($role in $info.Roles) {
                    $profileName = $info.Profiles | Where-Object { $_ -match $role } | Select-Object -First 1
                    if ($profileName) {
                        $config.environments.$friendlyName.oktaProfileMap[$role] = $profileName
                    }
                }

                # Remove the old wrong-key entry
                $config.environments.PSObject.Properties.Remove($wrongKeyEnv)
                $updatedAccounts += $friendlyName
            }
            else {
                # Rename: Just change the key name
                $oldEnv = $config.environments.$wrongKeyEnv
                $config.environments | Add-Member -NotePropertyName $friendlyName -NotePropertyValue $oldEnv -Force
                $config.environments.PSObject.Properties.Remove($wrongKeyEnv)

                # Update display name
                $displayName = $friendlyName -creplace '([a-z])([A-Z])', '$1 $2' `
                    -replace '-', ' ' `
                    -replace '\b\w', { $_.Value.ToUpper() }
                $config.environments.$friendlyName.displayName = $displayName

                $updatedAccounts += $friendlyName
            }

            $existingEnv = $friendlyName
        }
        # If we found a duplicate (same account ID exists with different key), merge them
        elseif ($duplicateEntry) {
            Write-Host "  Merging duplicate entries for account $accountId" -ForegroundColor Yellow

            # Always prefer the entry that matches the Okta friendly name
            $keepEntry = $null
            $removeEntry = $null

            if ($existingEnv -eq $friendlyName) {
                # existingEnv matches Okta name - keep it
                $keepEntry = $existingEnv
                $removeEntry = $duplicateEntry
            }
            elseif ($duplicateEntry -eq $friendlyName) {
                # duplicateEntry matches Okta name - keep it
                $keepEntry = $duplicateEntry
                $removeEntry = $existingEnv
            }
            else {
                # Neither matches exactly, keep the one closer to friendlyName
                $keepEntry = $existingEnv
                $removeEntry = $duplicateEntry
            }

            Write-Host "    Keeping '$keepEntry' (matches Okta name) and removing '$removeEntry'" -ForegroundColor Gray

            # Merge configuration from removeEntry into keepEntry
            $keep = $config.environments.$keepEntry
            $remove = $config.environments.$removeEntry

            # Preserve better display name, boxes, instances from either entry
            if (-not $keep.displayName -or $keep.displayName -like "*$accountId*") {
                if ($remove.displayName -and $remove.displayName -notlike "*$accountId*") {
                    $keep.displayName = $remove.displayName
                }
            }

            # Merge boxes if the one being removed has more
            if ($remove.boxes.Count -gt $keep.boxes.Count) {
                $keep.boxes = $remove.boxes
            }

            # Merge instances - take any that aren't empty
            if ($remove.PSObject.Properties['instances']) {
                foreach ($instKey in $remove.instances.PSObject.Properties.Name) {
                    $removeValue = $remove.instances.$instKey
                    $keepValue = if ($keep.instances.PSObject.Properties[$instKey]) { $keep.instances.$instKey } else { $null }

                    if ($removeValue -and -not $keepValue) {
                        # Add the property if it doesn't exist
                        if (-not $keep.instances.PSObject.Properties[$instKey]) {
                            $keep.instances | Add-Member -NotePropertyName $instKey -NotePropertyValue $removeValue -Force
                        } else {
                            $keep.instances.$instKey = $removeValue
                        }
                    }
                }
            }

            # Merge actions if the one being removed has more
            if ($remove.actions.Count -gt $keep.actions.Count) {
                $keep.actions = $remove.actions
            }

            # Remove the duplicate entry
            $config.environments.PSObject.Properties.Remove($removeEntry)
            $updatedAccounts += $keepEntry
            $existingEnv = $keepEntry
        }
        # If we found a match by name (without accountId), update it
        elseif ($matchByName) {
            Write-Host "  Updating account $accountId - adding accountId to existing '$matchByName' entry" -ForegroundColor Yellow

            # Add accountId
            $config.environments.$matchByName | Add-Member -NotePropertyName 'accountId' -NotePropertyValue $accountId -Force

            # Add roles if missing
            if (-not $config.environments.$matchByName.PSObject.Properties['availableRoles']) {
                $config.environments.$matchByName | Add-Member -NotePropertyName 'availableRoles' -NotePropertyValue $info.Roles -Force
                $config.environments.$matchByName | Add-Member -NotePropertyName 'preferredRole' -NotePropertyValue $info.Roles[0] -Force
            }

            # Set session duration based on preferred role's max duration
            $preferredRole = $config.environments.$matchByName.preferredRole
            $sessionDuration = "3600"  # Default
            if ($info.RoleMaxDurations.ContainsKey($preferredRole)) {
                $sessionDuration = $info.RoleMaxDurations[$preferredRole].ToString()
            }
            if (-not $config.environments.$matchByName.PSObject.Properties['sessionDuration']) {
                $config.environments.$matchByName | Add-Member -NotePropertyName 'sessionDuration' -NotePropertyValue $sessionDuration -Force
            } else {
                $config.environments.$matchByName.sessionDuration = $sessionDuration
            }

            # Add profile map if missing
            if (-not $config.environments.$matchByName.PSObject.Properties['oktaProfileMap']) {
                $config.environments.$matchByName | Add-Member -NotePropertyName 'oktaProfileMap' -NotePropertyValue @{} -Force
            }

            foreach ($role in $info.Roles) {
                $profileName = $info.Profiles | Where-Object { $_ -match $role } | Select-Object -First 1
                if ($profileName) {
                    $config.environments.$matchByName.oktaProfileMap[$role] = $profileName
                }
            }

            $updatedAccounts += $matchByName
            $existingEnv = $matchByName
        }

        if ($existingEnv -and -not $wrongKeyEnv -and -not $matchByName) {
            # Account exists - check if it needs updating
            $needsUpdate = $false

            # Check for role updates
            $currentRoles = if ($config.environments.$existingEnv.PSObject.Properties['availableRoles']) {
                $config.environments.$existingEnv.availableRoles
            } else {
                @()
            }

            $newRoles = $info.Roles | Where-Object { $_ -notin $currentRoles }

            if ($newRoles.Count -gt 0) {
                Write-Host "  Updating account $accountId ($existingEnv) - adding roles: $($newRoles -join ', ')" -ForegroundColor Yellow
                $needsUpdate = $true

                # Update available roles
                $allRoles = @($currentRoles) + @($newRoles) | Sort-Object -Unique
                $config.environments.$existingEnv.availableRoles = $allRoles
            } else {
                $allRoles = $currentRoles
            }

            # Always ensure oktaProfileMap exists and has entries for ALL roles
            if (-not $config.environments.$existingEnv.PSObject.Properties['oktaProfileMap']) {
                $config.environments.$existingEnv | Add-Member -NotePropertyName 'oktaProfileMap' -NotePropertyValue @{} -Force
            }

            # Check for missing profile mappings
            $missingMappings = @()
            foreach ($role in $allRoles) {
                $hasMapping = $config.environments.$existingEnv.oktaProfileMap.PSObject.Properties[$role]
                if (-not $hasMapping) {
                    $profileName = $info.Profiles | Where-Object { $_ -match $role } | Select-Object -First 1
                    if ($profileName) {
                        $config.environments.$existingEnv.oktaProfileMap | Add-Member -NotePropertyName $role -NotePropertyValue $profileName -Force
                        $missingMappings += $role
                        $needsUpdate = $true
                    }
                }
            }

            if ($missingMappings.Count -gt 0) {
                Write-Host "  Added missing profile mappings for roles: $($missingMappings -join ', ')" -ForegroundColor Yellow
            }

            # Update display name from Okta friendly name if needed
            $oktaDisplayName = $friendlyName -creplace '([a-z])([A-Z])', '$1 $2' `
                -replace '-', ' ' `
                -replace '\b\w', { $_.Value.ToUpper() }

            $currentDisplayName = if ($config.environments.$existingEnv.PSObject.Properties['displayName']) {
                $config.environments.$existingEnv.displayName
            } else {
                ""
            }

            if ($currentDisplayName -ne $oktaDisplayName) {
                Write-Host "  Updating display name for $existingEnv from '$currentDisplayName' to '$oktaDisplayName'" -ForegroundColor Yellow
                $config.environments.$existingEnv.displayName = $oktaDisplayName
                $needsUpdate = $true
            }

            # Set session duration based on preferred role's max duration
            $preferredRole = $config.environments.$existingEnv.preferredRole
            $sessionDuration = "3600"  # Default
            if ($info.RoleMaxDurations.ContainsKey($preferredRole)) {
                $sessionDuration = $info.RoleMaxDurations[$preferredRole].ToString()
            }

            if (-not $config.environments.$existingEnv.PSObject.Properties['sessionDuration'] -or
                $config.environments.$existingEnv.sessionDuration -ne $sessionDuration) {
                if (-not $config.environments.$existingEnv.PSObject.Properties['sessionDuration']) {
                    $config.environments.$existingEnv | Add-Member -NotePropertyName 'sessionDuration' -NotePropertyValue $sessionDuration -Force
                } else {
                    $config.environments.$existingEnv.sessionDuration = $sessionDuration
                }
                $needsUpdate = $true
            }

            if ($needsUpdate) {
                $updatedAccounts += $existingEnv
            }
            else {
                Write-Host "  Account $accountId ($existingEnv) - already up to date" -ForegroundColor Green
            }
        }
        else {
            # New account - create entry with friendly name
            $envName = $friendlyName
            Write-Host "  New account discovered: $accountId - '$friendlyName' (creating as $envName)" -ForegroundColor Cyan

            # Convert friendly name to display name (capitalize words, add spaces)
            $displayName = $friendlyName -creplace '([a-z])([A-Z])', '$1 $2' `
                -replace '-', ' ' `
                -replace '\b\w', { $_.Value.ToUpper() }

            # Create basic environment entry
            $newEnv = @{
                displayName = $displayName
                region = "us-east-1"
                accountId = $accountId
                availableRoles = $info.Roles
                preferredRole = $info.Roles[0]
                oktaProfileMap = @{}
                defaultRemoteIP = ""
                defaultRemotePort = ""
                defaultLocalPort = ""
                instances = @{
                    "jump-box" = ""
                }
                boxes = @()
                actions = @("instanceManagement")
            }

            # Set session duration based on preferred role's max duration
            $preferredRole = $newEnv.preferredRole
            $sessionDuration = "3600"  # Default
            if ($info.RoleMaxDurations.ContainsKey($preferredRole)) {
                $sessionDuration = $info.RoleMaxDurations[$preferredRole].ToString()
            }
            $newEnv.sessionDuration = $sessionDuration

            # Create profile map
            foreach ($role in $info.Roles) {
                $profileName = $info.Profiles | Where-Object { $_ -match $role } | Select-Object -First 1
                if ($profileName) {
                    $newEnv.oktaProfileMap[$role] = $profileName
                }
            }

            # Add to config
            $config.environments | Add-Member -NotePropertyName $envName -NotePropertyValue $newEnv -Force
            $newAccounts += @{
                Name = $envName
                DisplayName = $displayName
            }
        }
    }

    # Update okta.yaml (idps, roles, and profiles) to match discovered accounts
    Write-Host "`n══ Step 6: Updating okta.yaml ══" -ForegroundColor Cyan
    Write-Host ""

    $oktaYamlContent = Get-Content $oktaYamlPath -Raw
    $idpsAdded = @()
    $rolesAdded = @()
    $profilesAdded = @()

    # Step 6a: Update IDP section
    Write-Host "Checking IDP section..." -ForegroundColor Gray
    foreach ($accountId in $discoveredAccounts.Keys) {
        $friendlyName = $discoveredAccounts[$accountId].FriendlyName
        $idpArn = "arn:aws:iam::${accountId}:saml-provider/CFA-OKTA-PROD"

        # Check if IDP entry exists
        if ($oktaYamlContent -notmatch [regex]::Escape("`"$idpArn`"")) {
            # Find the idps section and add the entry
            $idpEntry = "`n    `"$idpArn`": `"$friendlyName`""

            # Insert before the roles section
            if ($oktaYamlContent -match '(?s)(  idps:.*?)(  roles:)') {
                $oktaYamlContent = $oktaYamlContent -replace '(  idps:.*?)(  roles:)', "`$1$idpEntry`n`n`$2"
                $idpsAdded += $friendlyName
                Write-Host "  ✓ Added IDP: $friendlyName (account $accountId)" -ForegroundColor Green
            }
        }
    }

    # Step 6b: Update roles section
    Write-Host "Checking roles section..." -ForegroundColor Gray
    foreach ($accountId in $discoveredAccounts.Keys) {
        foreach ($roleName in $discoveredAccounts[$accountId].Roles) {
            $roleArn = "arn:aws:iam::${accountId}:role/${roleName}"

            # Check if role entry exists
            if ($oktaYamlContent -notmatch [regex]::Escape("`"$roleArn`"")) {
                # Normalize role display name
                $displayName = $roleName
                if ($roleName -match '^(admin|Admin)$') {
                    $displayName = "Admin"
                } elseif ($roleName -match '^(devops|DevOps|Devops)$') {
                    $displayName = "devops"
                }

                $roleEntry = "`n    `"$roleArn`": `"$displayName`""

                # Insert before the profiles section
                if ($oktaYamlContent -match '(?s)(  roles:.*?)(  profiles:)') {
                    $oktaYamlContent = $oktaYamlContent -replace '(  roles:.*?)(  profiles:)', "`$1$roleEntry`n`n`$2"
                    $rolesAdded += "$roleName (account $accountId)"
                    Write-Host "  ✓ Added role: $displayName for account $accountId" -ForegroundColor Green
                }
            }
        }
    }

    # Step 6c: Update profiles section
    Write-Host "Checking profiles section..." -ForegroundColor Gray
    $profilesUpdated = @()

    foreach ($accountId in $discoveredAccounts.Keys) {
        $info = $discoveredAccounts[$accountId]
        $friendlyName = $info.FriendlyName

        foreach ($profileName in $info.Profiles) {
            # Extract role from profile name: friendlyname-CFA-OKTA-PROD-RoleName
            if ($profileName -match '-CFA-OKTA-PROD-(.+)$') {
                $roleName = $matches[1]

                # Get max session duration for this role (discovered in Step 3.5)
                $maxDuration = 3600  # Default to 1 hour
                if ($info.RoleMaxDurations.ContainsKey($roleName)) {
                    $maxDuration = $info.RoleMaxDurations[$roleName]
                }

                # Check if profile already exists
                if ($oktaYamlContent -match "(?m)^\s+${profileName}:") {
                    # Profile exists - check if session duration needs updating
                    $profilePattern = "(?ms)(^\s+${profileName}:.*?aws-session-duration:\s*)(\d+)"
                    if ($oktaYamlContent -match $profilePattern) {
                        $currentDuration = $matches[2]
                        if ($currentDuration -ne $maxDuration.ToString()) {
                            # Update session duration
                            $oktaYamlContent = $oktaYamlContent -replace $profilePattern, "`${1}$maxDuration"
                            $profilesUpdated += "$profileName (${currentDuration}s → ${maxDuration}s)"
                            Write-Host "  ✓ Updated profile: $profileName session duration: ${currentDuration}s → ${maxDuration}s" -ForegroundColor Cyan
                        }
                    }
                } else {
                    # Profile doesn't exist - add it
                    # Create profile entry
                    $profileEntry = @"

    ${profileName}:
      aws-iam-idp: "arn:aws:iam::${accountId}:saml-provider/CFA-OKTA-PROD"
      aws-iam-role: "arn:aws:iam::${accountId}:role/${roleName}"
      aws-session-duration: $maxDuration
"@
                    $oktaYamlContent = $oktaYamlContent.TrimEnd() + $profileEntry + "`n"
                    $profilesAdded += $profileName
                    Write-Host "  ✓ Added profile: $profileName (${maxDuration}s session)" -ForegroundColor Green
                }
            }
        }
    }

    # Save changes if any were made
    $totalChanges = $idpsAdded.Count + $rolesAdded.Count + $profilesAdded.Count + $profilesUpdated.Count
    if ($totalChanges -gt 0) {
        Write-Host ""
        Write-Host "Saving changes to okta.yaml..." -ForegroundColor Yellow
        Set-Content -Path $oktaYamlPath -Value $oktaYamlContent -Encoding UTF8
        Write-Host "✓ Okta.yaml updated:" -ForegroundColor Green
        if ($idpsAdded.Count -gt 0) {
            Write-Host "  - Added $($idpsAdded.Count) IDP mapping(s)" -ForegroundColor Cyan
        }
        if ($rolesAdded.Count -gt 0) {
            Write-Host "  - Added $($rolesAdded.Count) role(s)" -ForegroundColor Cyan
        }
        if ($profilesAdded.Count -gt 0) {
            Write-Host "  - Added $($profilesAdded.Count) profile(s)" -ForegroundColor Cyan
        }
        if ($profilesUpdated.Count -gt 0) {
            Write-Host "  - Updated $($profilesUpdated.Count) profile(s) with new session durations" -ForegroundColor Cyan
        }
    } else {
        Write-Host "  No changes needed in okta.yaml - all sections are up to date" -ForegroundColor Green
    }

    # Save updated config.json
    if ($newAccounts.Count -gt 0 -or $updatedAccounts.Count -gt 0) {
        Write-Host ""
        Write-Host "Saving changes to config.json..." -ForegroundColor Yellow

        # Remove the old menu-based persistence for AWS accounts (no longer used)
        if ($config.PSObject.Properties['menus'] -and
            $config.menus.PSObject.Properties['Select AWS Account/Environment']) {
            $config.menus.PSObject.Properties.Remove('Select AWS Account/Environment')
            Write-Host "  - Removed deprecated AWS account menu data" -ForegroundColor Gray
        }

        $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
        Write-Host "✓ Config.json updated" -ForegroundColor Green

        Write-Host ""
        Write-Host "═══════════════════════════════════════════" -ForegroundColor Green
        Write-Host "Summary of Changes:" -ForegroundColor Yellow
        if ($newAccounts.Count -gt 0) {
            Write-Host "  New Accounts Added: $($newAccounts.Count)" -ForegroundColor Cyan
            foreach ($acc in $newAccounts) {
                Write-Host "    - $($acc.DisplayName) ($($acc.Name))" -ForegroundColor White
            }
        }
        if ($updatedAccounts.Count -gt 0) {
            Write-Host "  Accounts Updated: $($updatedAccounts.Count)" -ForegroundColor Cyan
            foreach ($acc in $updatedAccounts) {
                Write-Host "    - $acc" -ForegroundColor White
            }
        }
        Write-Host "═══════════════════════════════════════════" -ForegroundColor Green
        Write-Host ""

        # Reload configuration
        Update-ScriptConfiguration

        Write-Host "✓ Account list has been updated and reloaded!" -ForegroundColor Green
        Write-Host ""
    }
    else {
        Write-Host "No changes needed - all accounts are up to date." -ForegroundColor Green
        Write-Host ""
    }

    Invoke-StandardPause
}

function Show-AwsAccountMenu {
    # Helper function to create a menu item for an environment+role
    function New-AwsAccountMenuItem {
        param($envKey, $env, $role = $null)

        $friendlyName = $envKey
        $accountId = if ($env.PSObject.Properties['accountId']) { $env.accountId } else { "" }

        # Check for custom display name first
        $customName = Get-AwsAccountCustomName -Environment $envKey -Role $role

        if ($customName) {
            # Use custom name as-is
            $displayText = $customName
        } else {
            # Build default display text
            if ($role) {
                $displayText = if ($accountId) {
                    "$friendlyName ($accountId) - Role: $role"
                } else {
                    "$friendlyName - Role: $role"
                }
            } else {
                $displayText = if ($accountId) {
                    "$friendlyName ($accountId)"
                } else {
                    $env.displayName
                }
            }
        }

        return @{
            Text = $displayText
            HighlightPos = 0
            HighlightChar = $friendlyName[0]
            Environment = $envKey
            Region = $env.region
            Role = $role
        }
    }

    # Build a hashtable for quick lookup of all items by env:role key
    $allItemsLookup = @{}
    $specialItems = @()

    foreach ($envKey in $script:Config.environments.PSObject.Properties.Name) {
        $env = $script:Config.environments.$envKey

        # Skip manual - it will be added at the end
        if ($envKey -eq "manual") {
            $customName = Get-AwsAccountCustomName -Environment $envKey -Role $null
            $specialItems += @{
                Text = if ($customName) { $customName } else { $env.displayName }
                HighlightPos = $env.highlightPos
                HighlightChar = $env.highlightChar
                Environment = $envKey
                Region = $env.region
                Role = $null
            }
            continue
        }

        # Check if account has multiple roles
        if ($env.PSObject.Properties['availableRoles'] -and $env.availableRoles.Count -gt 0) {
            # Create a menu item for each role
            foreach ($role in $env.availableRoles) {
                $item = New-AwsAccountMenuItem -envKey $envKey -env $env -role $role
                $lookupKey = "${envKey}:${role}"
                $allItemsLookup[$lookupKey] = $item
            }
        } else {
            # No roles defined - create single item with account name
            $item = New-AwsAccountMenuItem -envKey $envKey -env $env
            $lookupKey = $envKey
            $allItemsLookup[$lookupKey] = $item
        }
    }

    # Build the final menu in the correct order
    $accountItems = @()
    $savedOrder = Get-AwsAccountMenuOrder

    if ($savedOrder) {
        # Use saved order
        foreach ($key in $savedOrder) {
            if ($allItemsLookup.ContainsKey($key)) {
                $accountItems += $allItemsLookup[$key]
                # Remove from lookup so we can add any new items at the end
                $allItemsLookup.Remove($key)
            }
        }

        # Add any new items that weren't in the saved order (sorted alphabetically)
        if ($allItemsLookup.Count -gt 0) {
            $newItems = $allItemsLookup.Values | Sort-Object -Property { $_['Text'] }
            $accountItems += $newItems
        }
    } else {
        # No saved order - use default alphabetical sort
        $accountItems = $allItemsLookup.Values | Sort-Object -Property { $_['Text'] }
    }

    # Add special items at the end
    $accountItems += $specialItems

    # Add sync option at the very end
    $accountItems += @{
        Text = "═══ Sync AWS Accounts from Okta ═══"
        HighlightPos = 0
        HighlightChar = "S"
        Environment = "sync"
        Region = ""
        Role = $null
    }

    do {
        $choice = Show-ArrowMenu -MenuItems $accountItems -Title "Select AWS Account/Environment"

        if ($choice -eq -1) {
            Write-Host "Returning to Main Menu..." -ForegroundColor Cyan
            return
        }

        $selectedAccount = $accountItems[$choice]

        if ($selectedAccount.Environment -eq "sync") {
            Sync-AwsAccountsFromOkta
            # Continue loop to return to AWS menu after sync
            continue
        }
        elseif ($selectedAccount.Environment -eq "manual") {
            Start-ManualAwsLogin
            # Continue loop to return to AWS menu after manual login
            continue
        }
        else {
            # Pass the role to the login function
            Start-AwsLoginForAccount -Environment $selectedAccount.Environment -Region $selectedAccount.Region -PreselectedRole $selectedAccount.Role
            # Continue loop to return to AWS menu after authentication/actions
            continue
        }
    } while ($true)
}

function Start-CommandPrompt {
    Write-Host "Dropping to command prompt. Type 'exit' to return." -ForegroundColor Yellow
    Invoke-Expression "pwsh -noe -wd '$PSScriptRoot'"
}

function Get-CurrentInstanceId {
    param([string]$InstanceType = "jump-box")

    # Check if there's a per-account override set
    if ($global:currentAwsEnvironment -and $global:accountDefaultInstances.ContainsKey($global:currentAwsEnvironment)) {
        $accountDefault = $global:accountDefaultInstances[$global:currentAwsEnvironment]
        if ($accountDefault.ContainsKey($InstanceType)) {
            return $accountDefault[$InstanceType]
        }
    }

    # Otherwise fall back to configuration - build configs inline
    $configs = @{}

    # Build configurations from JSON config
    foreach ($envKey in $script:Config.environments.PSObject.Properties.Name) {
        $env = $script:Config.environments.$envKey
        $configs[$envKey] = @{}

        foreach ($instanceKey in $env.instances.PSObject.Properties.Name) {
            $configs[$envKey][$instanceKey] = $env.instances.$instanceKey
        }
    }

    # Add default fallback
    $configs["default"] = @{
        "jump-box" = $script:Config.defaultConnection.instance
    }

    # Use the built configs
    if ($global:currentAwsEnvironment -and $configs.ContainsKey($global:currentAwsEnvironment)) {
        $envConfig = $configs[$global:currentAwsEnvironment]
        if ($envConfig.ContainsKey($InstanceType)) {
            return $envConfig[$InstanceType]
        } else {
            # Default to first available instance in environment
            return $envConfig.Values | Select-Object -First 1
        }
    } else {
        return $configs["default"]["jump-box"]
    }
}

function Get-CurrentDefaultRemoteIP {
    # Get the default RemoteIP from the current environment's config
    if ($global:currentAwsEnvironment -and $script:Config.environments.PSObject.Properties[$global:currentAwsEnvironment]) {
        $envConfig = $script:Config.environments.$global:currentAwsEnvironment
        if ($envConfig.defaultRemoteIP) {
            return $envConfig.defaultRemoteIP
        }
    }
    return $null
}

function Start-AlohaRemoteAccess {
    Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  ALOHA REMOTE ACCESS                       ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    # Display current instance settings using the shared function (without pause)
    Write-Host "Current Instance Settings:" -ForegroundColor Cyan
    Write-Host "  Environment: $global:currentAwsEnvironment" -ForegroundColor White
    Write-Host "  Region: $global:currentAwsRegion" -ForegroundColor White

    # Get default instance ID and name
    $defaultInstanceId = Get-CurrentInstanceId
    if ($defaultInstanceId) {
        $defaultInstanceName = Get-InstanceNameById -InstanceId $defaultInstanceId
        if ($defaultInstanceName) {
            Write-Host "  Instance ID: $defaultInstanceId ($defaultInstanceName)" -ForegroundColor White
        } else {
            Write-Host "  Instance ID: $defaultInstanceId" -ForegroundColor White
        }
    } else {
        Write-Host "  Instance ID: (not configured)" -ForegroundColor DarkGray
    }

    # Get current configuration
    $envConfig = $script:Config.environments.$global:currentAwsEnvironment

    # Display remote host configuration if available
    Write-Host ""
    Write-Host "Default Remote Host Info:" -ForegroundColor Cyan

    # Get remote host instance ID
    $remoteHostInstanceId = ""
    if ($envConfig.instances.PSObject.Properties['remote-host']) {
        $remoteHostInstanceId = $envConfig.instances.'remote-host'
    }

    $hasConfig = $false
    if ($remoteHostInstanceId) {
        $remoteHostInstanceName = Get-InstanceNameById -InstanceId $remoteHostInstanceId
        if ($remoteHostInstanceName) {
            Write-Host "  Remote Host Instance ID: $remoteHostInstanceId ($remoteHostInstanceName)" -ForegroundColor White
        } else {
            Write-Host "  Remote Host Instance ID: $remoteHostInstanceId" -ForegroundColor White
        }
        $hasConfig = $true
    } else {
        Write-Host "  Remote Host Instance ID: (not configured)" -ForegroundColor DarkGray
    }

    $remoteIP = if ($envConfig.PSObject.Properties['defaultRemoteIP']) { $envConfig.defaultRemoteIP } else { "" }
    $remotePort = if ($envConfig.PSObject.Properties['defaultRemotePort']) { $envConfig.defaultRemotePort } else { "" }
    $localPort = if ($envConfig.PSObject.Properties['defaultLocalPort']) { $envConfig.defaultLocalPort } else { "" }

    if ($remoteIP) {
        Write-Host "  Remote IP: $remoteIP" -ForegroundColor White
    } else {
        Write-Host "  Remote IP: (not configured)" -ForegroundColor DarkGray
    }

    if ($remotePort) {
        Write-Host "  Remote Port: $remotePort" -ForegroundColor White
    } else {
        Write-Host "  Remote Port: (not configured)" -ForegroundColor DarkGray
    }

    if ($localPort) {
        Write-Host "  Local Port: $localPort" -ForegroundColor White
    } else {
        Write-Host "  Local Port: (not configured)" -ForegroundColor DarkGray
    }

    Write-Host ""

    # Check if configuration exists
    if (-not $hasConfig -or -not $remoteIP -or -not $remotePort -or -not $localPort) {
        Write-Host "Remote host configuration is incomplete." -ForegroundColor Yellow
        Write-Host "You need to set the default remote host info first." -ForegroundColor Yellow
        Write-Host ""
        $configure = Read-Host "Configure remote host settings now? (Y/n)"
        if ($configure.ToLower() -ne "n") {
            Set-DefaultRemoteHostInfo
            # Restart this function to show updated settings
            Start-AlohaRemoteAccess
            return
        } else {
            Write-Host "Cannot proceed without remote host configuration." -ForegroundColor Red
    Invoke-StandardPause
            return
        }
    }

    # Prompt to use current settings or modify
    $useSettings = Read-Host "Use these settings? (Y/n/m to modify)"

    if ($useSettings.ToLower() -eq "n") {
        Write-Host "Aloha remote access cancelled." -ForegroundColor Yellow
    Invoke-StandardPause
        return
    }

    if ($useSettings.ToLower() -eq "m") {
        Write-Host ""
        Set-DefaultRemoteHostInfo
        # Restart this function to show updated settings
        Start-AlohaRemoteAccess
        return
    }

    # Set global variables for aloha connection
    # Use the default instance ID for SSM connection, and remote IP for port forwarding target
    $global:awsInstance = $defaultInstanceId
    $global:remoteIP = $remoteIP
    $global:remotePort = $remotePort
    $global:localPort = $localPort

    # Ask if this is an RDP connection (default to Yes)
    Write-Host ""
    $isRdp = Read-Host "Is this an RDP connection? (Y/n)"
    $isRdpBool = $isRdp.ToLower() -ne "n"

    # Start the Aloha connection
    Start-AlohaConnection -IsRdp $isRdpBool
}

function Show-InstanceManagementMenu {
    # Define default menu
    $defaultMenu = @(
        (New-MenuAction "List Running Instances" { Get-RunningInstances }),
        (New-MenuAction "Set Default Instance ID" { Set-DefaultInstanceId }),
        (New-MenuAction "Set Default Remote Host Info" { Set-DefaultRemoteHostInfo }),
        (New-MenuAction "View Current Instance Settings" { Show-CurrentInstanceSettings }),
        (New-MenuAction "Test Instance Connectivity" { Test-InstanceConnectivity }),
        (New-MenuAction "Get VPN Connections" { Get-VpnConnections }),
        (New-MenuAction "Aloha Remote Access" { Start-AlohaRemoteAccess })
    )

    # Load menu from config (or use default if not customized)
    $instanceItems = Get-MenuFromConfig -MenuTitle "Instance Management" -DefaultMenuItems $defaultMenu

    do {
        # Build AWS context header
        $headerLines = @()
        if ($global:currentAwsEnvironment -and $global:currentAwsRegion) {
            $accountInfo = ""

            # Try to get account ID from config
            if ($script:Config.environments.$global:currentAwsEnvironment.PSObject.Properties['accountId']) {
                $accountId = $script:Config.environments.$global:currentAwsEnvironment.accountId
                $accountInfo = "$global:currentAwsEnvironment (Account: $accountId) - Region: $global:currentAwsRegion"
            } else {
                $accountInfo = "$global:currentAwsEnvironment - Region: $global:currentAwsRegion"
            }

            # Use ANSI color codes for header (yellow text)
            $headerLines += "`e[33mAWS Context: $accountInfo`e[0m"
            $headerLines += ""  # Blank line for spacing
        }

        $choice = Show-ArrowMenu -MenuItems $instanceItems -Title "Instance Management" -HeaderLines $headerLines

        if ($choice -eq -1) {
            return
        }

        # Execute the selected action
        $selectedAction = $instanceItems[$choice]
        & $selectedAction.Action

    } while ($true)
}

function Get-Ec2InstanceInfo {
    param(
        [string]$InstanceId = $null,
        [string]$State = "running",
        [string]$Title = "EC2 Instances"
    )

    Write-Host "Getting $Title..." -ForegroundColor Cyan
    Write-Host ""

    # Build profile parameter using the stored AWS profile name
    $profileParam = if ($global:currentAwsProfile) {
        "--profile $global:currentAwsProfile"
    } else {
        ""
    }

    # Check if credentials are still valid using the correct profile
    try {
        $credCheckCmd = "aws sts get-caller-identity $profileParam 2>&1"
        $null = Invoke-Expression $credCheckCmd
        if ($LASTEXITCODE -ne 0) {
            Write-Host "AWS credentials have expired or are invalid." -ForegroundColor Red
            Write-Host "Please re-authenticate using 'Change AWS Account' option." -ForegroundColor Yellow
    Invoke-StandardPause
            return
        }
    }
    catch {
        Write-Host "Unable to verify AWS credentials." -ForegroundColor Red
    Invoke-StandardPause
        return
    }

    try {
        Write-Host "$Title`:" -ForegroundColor Green

        # Display current AWS account context
        if ($global:currentAwsEnvironment -and $global:currentAwsRegion) {
            $accountInfo = ""

            # Try to get account ID from config
            if ($script:Config.environments.$global:currentAwsEnvironment.PSObject.Properties['accountId']) {
                $accountId = $script:Config.environments.$global:currentAwsEnvironment.accountId
                $accountInfo = "$global:currentAwsEnvironment (Account: $accountId) - Region: $global:currentAwsRegion"
            } else {
                $accountInfo = "$global:currentAwsEnvironment - Region: $global:currentAwsRegion"
            }

            Write-Host "AWS Context: $accountInfo" -ForegroundColor Yellow
        }

        # Get the default instance ID for highlighting
        $defaultInstanceId = Get-CurrentInstanceId

        # Capture AWS output
        $awsOutput = if ($InstanceId) {
            # Get specific instance
            Invoke-Expression "aws ec2 describe-instances $profileParam --instance-ids $InstanceId --query 'Reservations[0].Instances[0].[InstanceId,State.Name,Tags[?Key==``Name``].Value|[0],PrivateIpAddress,InstanceType]' --output table" 2>&1 | Out-String
        } else {
            # Get all instances with optional state filter
            if ($State -eq "all") {
                Invoke-Expression "aws ec2 describe-instances $profileParam --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==``Name``].Value|[0],State.Name,PrivateIpAddress,InstanceType]' --output table" 2>&1 | Out-String
            } else {
                Invoke-Expression "aws ec2 describe-instances $profileParam --filters 'Name=instance-state-name,Values=$State' --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==``Name``].Value|[0],State.Name,PrivateIpAddress,InstanceType]' --output table" 2>&1 | Out-String
            }
        }

        if ($LASTEXITCODE -ne 0) {
            # Show the output (likely contains error message)
            Write-Host $awsOutput
            if ($InstanceId) {
                Write-Host "Instance not found or not accessible." -ForegroundColor Red
            } else {
                Write-Host "No instances found or unable to retrieve instances." -ForegroundColor Yellow
            }
        } else {
            # Parse and display the output with highlighting and markers
            $defaultRemoteIP = Get-CurrentDefaultRemoteIP
            $lines = $awsOutput -split "`n"
            foreach ($line in $lines) {
                # Skip empty lines
                if ([string]::IsNullOrWhiteSpace($line)) { continue }

                # Check if this line contains the default instance ID or remote IP
                $hasDefaultInstance = $line -match $defaultInstanceId
                $hasDefaultHost = $defaultRemoteIP -and $line -match [regex]::Escape($defaultRemoteIP)

                # Add markers
                if ($hasDefaultInstance -and $hasDefaultHost) {
                    Write-Host "*+ $line" -ForegroundColor Yellow
                } elseif ($hasDefaultInstance) {
                    Write-Host "*  $line" -ForegroundColor Yellow
                } elseif ($hasDefaultHost) {
                    Write-Host "+  $line" -ForegroundColor Cyan
                } else {
                    Write-Host "   $line"
                }
            }
            # Add legend closer to the table
            Write-Host "   Legend: * = Default Instance | + = Default Host | *+ = Both" -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Host "Error retrieving instances: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
    Invoke-StandardPause
}

function Get-RunningInstances {
    Get-Ec2InstanceInfo -State "running" -Title "Running EC2 Instances"
}

function Get-Ec2InstancesData {
    param(
        [string]$State = "running"
    )

    # Build profile parameter using the stored AWS profile name
    $profileParam = if ($global:currentAwsProfile) {
        "--profile $global:currentAwsProfile"
    } else {
        ""
    }

    # Check if credentials are still valid using the correct profile
    try {
        $credCheckCmd = "aws sts get-caller-identity $profileParam 2>&1"
        $null = Invoke-Expression $credCheckCmd
        if ($LASTEXITCODE -ne 0) {
            Write-Host "AWS credentials have expired or are invalid." -ForegroundColor Red
            Write-Host "Please re-authenticate using 'Change AWS Account' option." -ForegroundColor Yellow
            return @()
        }
    }
    catch {
        Write-Host "Unable to verify AWS credentials." -ForegroundColor Red
        return @()
    }

    try {
        # Get instances as JSON for parsing
        $jsonOutput = if ($State -eq "all") {
            Invoke-Expression "aws ec2 describe-instances $profileParam --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==``Name``].Value|[0],State.Name,PrivateIpAddress,InstanceType]' --output json" 2>&1
        } else {
            Invoke-Expression "aws ec2 describe-instances $profileParam --filters 'Name=instance-state-name,Values=$State' --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==``Name``].Value|[0],State.Name,PrivateIpAddress,InstanceType]' --output json" 2>&1
        }

        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error retrieving instances from AWS." -ForegroundColor Red
            return @()
        }

        # Parse JSON and convert to objects
        $rawData = $jsonOutput | ConvertFrom-Json
        $instances = @()

        # Handle case where there's only one instance (rawData is a single array, not array of arrays)
        if ($rawData -and $rawData[0] -is [string]) {
            # Single instance - $rawData is the instance array itself
            $instances += [PSCustomObject]@{
                InstanceId = $rawData[0]
                Name = if ($rawData[1]) { $rawData[1] } else { "(no name)" }
                State = $rawData[2]
                PrivateIpAddress = $rawData[3]
                InstanceType = $rawData[4]
            }
        } else {
            # Multiple instances - iterate over array of arrays
            foreach ($item in $rawData) {
                $instances += [PSCustomObject]@{
                    InstanceId = $item[0]
                    Name = if ($item[1]) { $item[1] } else { "(no name)" }
                    State = $item[2]
                    PrivateIpAddress = $item[3]
                    InstanceType = $item[4]
                }
            }
        }

        return $instances
    }
    catch {
        Write-Host "Error parsing instance data: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

function Select-Ec2Instance {
    param(
        [string]$State = "running",
        [string]$Title = "Select EC2 Instance"
    )

    Write-Host "Getting instances..." -ForegroundColor Cyan
    $instances = Get-Ec2InstancesData -State $State

    if ($instances.Count -eq 0) {
        Write-Host "No instances found." -ForegroundColor Yellow
    Invoke-StandardPause
        return $null
    }

    # Build header lines for display in menu
    $headerLines = @()

    # Add AWS account context to header
    if ($global:currentAwsEnvironment -and $global:currentAwsRegion) {
        $accountInfo = ""

        # Try to get account ID from config
        if ($script:Config.environments.$global:currentAwsEnvironment.PSObject.Properties['accountId']) {
            $accountId = $script:Config.environments.$global:currentAwsEnvironment.accountId
            $accountInfo = "$global:currentAwsEnvironment (Account: $accountId) - Region: $global:currentAwsRegion"
        } else {
            $accountInfo = "$global:currentAwsEnvironment - Region: $global:currentAwsRegion"
        }

        # Use ANSI color codes for yellow text
        $yellowCode = "`e[93m"
        $resetCode = "`e[0m"
        $headerLines += "${yellowCode}AWS Context: $accountInfo${resetCode}"
    }

    # Add legend to header
    $grayCode = "`e[90m"
    $resetCode = "`e[0m"
    $headerLines += "${grayCode}   Legend: * = Default Instance | + = Default Host | *+ = Both${resetCode}"

    # Get defaults for highlighting
    $defaultInstanceId = Get-CurrentInstanceId
    $defaultRemoteIP = Get-CurrentDefaultRemoteIP

    # Create menu items from instances - using simple strings for Show-ArrowMenu
    $menuItems = @()
    foreach ($instance in $instances) {
        $displayText = "$($instance.InstanceId) | $($instance.Name) | $($instance.PrivateIpAddress) | $($instance.State) | $($instance.InstanceType)"

        # Determine if this is a default (for visual indicator)
        $isDefaultInstance = $instance.InstanceId -eq $defaultInstanceId
        $isDefaultIP = $defaultRemoteIP -and $instance.PrivateIpAddress -eq $defaultRemoteIP

        if ($isDefaultInstance -and $isDefaultIP) {
            $displayText = "*+ $displayText"
        } elseif ($isDefaultInstance) {
            $displayText = "*  $displayText"
        } elseif ($isDefaultIP) {
            $displayText = "+  $displayText"
        } else {
            $displayText = "   $displayText"
        }

        $menuItems += $displayText
    }

    # Add "None" option at the end
    $menuItems += "<None - No Instance Configured>"

    $choice = Show-ArrowMenu -MenuItems $menuItems -Title $Title -HeaderLines $headerLines

    if ($choice -eq -1) {
        # User pressed Q - return a special marker to indicate cancellation
        return @{ Cancelled = $true }
    }

    # If user selected "None" (last item), return null
    if ($choice -eq $menuItems.Count - 1) {
        return $null
    }

    return $instances[$choice]
}

function Set-DefaultInstanceId {
    $currentDefault = Get-CurrentInstanceId
    Write-Host "Current default instance for $global:currentAwsEnvironment`: $currentDefault" -ForegroundColor Cyan
    Write-Host ""

    # Use interactive selection
    $selectedInstance = Select-Ec2Instance -State "running" -Title "Select Default Instance"

    # Check if user cancelled (pressed Q)
    if ($selectedInstance -is [hashtable] -and $selectedInstance.Cancelled) {
        Write-Host "Selection cancelled - no changes made." -ForegroundColor Yellow
    Invoke-StandardPause
        return
    }

    if (-not $selectedInstance) {
        Write-Host "Selected: None" -ForegroundColor Yellow
        $newInstanceId = $null
    } else {
        $newInstanceId = $selectedInstance.InstanceId
        Write-Host ""
        Write-Host "Selected: $newInstanceId ($($selectedInstance.Name) - $($selectedInstance.PrivateIpAddress))" -ForegroundColor Cyan
    }

    Write-Host ""

    # Store per-account default instance in config
    $configPath = Join-Path $PSScriptRoot "config.json"
    $config = Get-Content $configPath -Raw | ConvertFrom-Json

    # Ensure the environment exists in config
    if (-not $config.environments.$global:currentAwsEnvironment) {
        Write-Host "Error: Environment '$global:currentAwsEnvironment' not found in config." -ForegroundColor Red
    Invoke-StandardPause
        return
    }

    # Update the instances.jump-box value (set to null or empty if none selected)
    if ($newInstanceId) {
        $config.environments.$global:currentAwsEnvironment.instances.'jump-box' = $newInstanceId
    } else {
        $config.environments.$global:currentAwsEnvironment.instances.'jump-box' = ""
    }

    # Save back to config.json with proper formatting
    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8

    # Reload configuration to pick up changes
    Update-ScriptConfiguration

    # Also update the in-memory cache for immediate effect
    if (-not $global:accountDefaultInstances.ContainsKey($global:currentAwsEnvironment)) {
        $global:accountDefaultInstances[$global:currentAwsEnvironment] = @{}
    }

    if ($newInstanceId) {
        $global:accountDefaultInstances[$global:currentAwsEnvironment]["jump-box"] = $newInstanceId
        Write-Host "✓ Updated default instance for account '$global:currentAwsEnvironment' to: $newInstanceId" -ForegroundColor Green
    } else {
        $global:accountDefaultInstances[$global:currentAwsEnvironment]["jump-box"] = ""
        Write-Host "✓ Cleared default instance for account '$global:currentAwsEnvironment'" -ForegroundColor Green
    }

    Write-Host "✓ Changes saved to config.json" -ForegroundColor Green
    Write-Host ""

    Invoke-StandardPause
}

function Set-DefaultRemoteHostInfo {
    Write-Host "Set Default Remote Host Information for $global:currentAwsEnvironment" -ForegroundColor Cyan
    Write-Host ""

    # Step 1: Select an EC2 instance
    Write-Host "Step 1: Select the EC2 instance to connect through" -ForegroundColor Yellow
    $selectedInstance = Select-Ec2Instance -State "running" -Title "Select Instance for Remote Connection"

    # Check if user cancelled (pressed Q)
    if ($selectedInstance -is [hashtable] -and $selectedInstance.Cancelled) {
        Write-Host "Selection cancelled - no changes made." -ForegroundColor Yellow
    Invoke-StandardPause
        return
    }

    if (-not $selectedInstance) {
        Write-Host "Selected: None - Clearing remote host configuration" -ForegroundColor Yellow
        $newInstanceId = ""
        $newRemoteIP = ""
        $newRemotePort = ""
        $newLocalPort = ""

        Write-Host ""
        $confirm = Read-Host "Clear all remote host settings for this account? (y/N)"
        if ($confirm.ToLower() -ne "y") {
            Write-Host "Configuration not changed." -ForegroundColor Yellow
    Invoke-StandardPause
            return
        }
    } else {
        $newInstanceId = $selectedInstance.InstanceId
        $newRemoteIP = $selectedInstance.PrivateIpAddress

        Write-Host ""
        Write-Host "Selected Instance: $newInstanceId ($($selectedInstance.Name))" -ForegroundColor Green
        Write-Host "Using Instance IP: $newRemoteIP" -ForegroundColor Cyan
        Write-Host ""

        # Step 2: Prompt for Remote Port
        Write-Host "Step 2: Enter Remote Port" -ForegroundColor Yellow

        # Get current remote port from config
        $envConfig = $script:Config.environments.$global:currentAwsEnvironment
        $currentRemotePort = if ($envConfig.PSObject.Properties['defaultRemotePort']) { $envConfig.defaultRemotePort } else { "" }

        if ($currentRemotePort) {
            $newRemotePort = Read-Host "Enter Remote Port [$currentRemotePort]"
        } else {
            $newRemotePort = Read-Host "Enter Remote Port"
        }
        if ([string]::IsNullOrWhiteSpace($newRemotePort)) {
            $newRemotePort = if ($currentRemotePort) { $currentRemotePort } else { "3389" }
        }

        # Step 3: Prompt for Local Port
        Write-Host ""
        Write-Host "Step 3: Enter Local Port" -ForegroundColor Yellow

        # Get current local port from config
        $currentLocalPort = if ($envConfig.PSObject.Properties['defaultLocalPort']) { $envConfig.defaultLocalPort } else { "" }

        if ($currentLocalPort) {
            $newLocalPort = Read-Host "Enter Local Port [$currentLocalPort]"
        } else {
            $newLocalPort = Read-Host "Enter Local Port"
        }
        if ([string]::IsNullOrWhiteSpace($newLocalPort)) {
            $newLocalPort = if ($currentLocalPort) { $currentLocalPort } else { "8388" }
        }

        # Summary
        Write-Host ""
        Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "Configuration Summary:" -ForegroundColor Yellow
        Write-Host "  Environment: $global:currentAwsEnvironment" -ForegroundColor White
        Write-Host "  Instance ID: $newInstanceId" -ForegroundColor White
        Write-Host "  Instance Name: $($selectedInstance.Name)" -ForegroundColor White
        Write-Host "  Remote IP: $newRemoteIP" -ForegroundColor White
        Write-Host "  Remote Port: $newRemotePort" -ForegroundColor White
        Write-Host "  Local Port: $newLocalPort" -ForegroundColor White
        Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host ""

        $confirm = Read-Host "Save this configuration? (Y/n)"
        if ($confirm.ToLower() -eq "n") {
            Write-Host "Configuration not saved." -ForegroundColor Yellow
    Invoke-StandardPause
            return
        }
    }

    # Store configuration in config.json
    $configPath = Join-Path $PSScriptRoot "config.json"
    $config = Get-Content $configPath -Raw | ConvertFrom-Json

    # Ensure the environment exists in config
    if (-not $config.environments.$global:currentAwsEnvironment) {
        Write-Host "Error: Environment '$global:currentAwsEnvironment' not found in config." -ForegroundColor Red
    Invoke-StandardPause
        return
    }

    # Update the configuration values - use separate field for remote host instance
    if ($config.environments.$global:currentAwsEnvironment.instances.PSObject.Properties['remote-host']) {
        $config.environments.$global:currentAwsEnvironment.instances.'remote-host' = $newInstanceId
    } else {
        $config.environments.$global:currentAwsEnvironment.instances | Add-Member -NotePropertyName 'remote-host' -NotePropertyValue $newInstanceId -Force
    }
    $config.environments.$global:currentAwsEnvironment.defaultRemoteIP = $newRemoteIP

    # Update default connection settings if they exist
    if ($config.environments.$global:currentAwsEnvironment.PSObject.Properties['defaultRemotePort']) {
        $config.environments.$global:currentAwsEnvironment.defaultRemotePort = $newRemotePort
    } else {
        $config.environments.$global:currentAwsEnvironment | Add-Member -NotePropertyName 'defaultRemotePort' -NotePropertyValue $newRemotePort -Force
    }

    if ($config.environments.$global:currentAwsEnvironment.PSObject.Properties['defaultLocalPort']) {
        $config.environments.$global:currentAwsEnvironment.defaultLocalPort = $newLocalPort
    } else {
        $config.environments.$global:currentAwsEnvironment | Add-Member -NotePropertyName 'defaultLocalPort' -NotePropertyValue $newLocalPort -Force
    }

    # Save back to config.json with proper formatting
    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8

    # Reload configuration to pick up changes
    Update-ScriptConfiguration

    # Also update the in-memory cache for immediate effect
    if (-not $global:accountDefaultInstances.ContainsKey($global:currentAwsEnvironment)) {
        $global:accountDefaultInstances[$global:currentAwsEnvironment] = @{}
    }
    $global:accountDefaultInstances[$global:currentAwsEnvironment]["remote-host"] = $newInstanceId

    Write-Host ""
    if ($newInstanceId) {
        Write-Host "✓ Configuration saved successfully!" -ForegroundColor Green
        Write-Host "✓ Instance ID: $newInstanceId" -ForegroundColor Green
        Write-Host "✓ Remote Host: ${newRemoteIP}:${newRemotePort}" -ForegroundColor Green
        Write-Host "✓ Local Port: $newLocalPort" -ForegroundColor Green
    } else {
        Write-Host "✓ Remote host configuration cleared for account '$global:currentAwsEnvironment'" -ForegroundColor Green
    }
    Write-Host "✓ Changes saved to config.json" -ForegroundColor Green
    Write-Host ""

    Invoke-StandardPause
}

function Get-InstanceNameById {
    param(
        [string]$InstanceId
    )

    if (-not $InstanceId) {
        return $null
    }

    # Build profile parameter using the stored AWS profile name
    $profileParam = if ($global:currentAwsProfile) {
        "--profile $global:currentAwsProfile"
    } else {
        ""
    }

    try {
        # Query AWS for the instance name tag
        $nameTag = Invoke-Expression "aws ec2 describe-instances $profileParam --instance-ids $InstanceId --query 'Reservations[0].Instances[0].Tags[?Key==``Name``].Value' --output text 2>&1"

        if ($LASTEXITCODE -eq 0 -and $nameTag -and $nameTag -ne "None") {
            return $nameTag
        }
    }
    catch {
        # Silently fail if we can't get the name
    }

    return $null
}

function Show-CurrentInstanceSettings {
    Write-Host "Current Instance Settings:" -ForegroundColor Cyan
    Write-Host "  Environment: $global:currentAwsEnvironment" -ForegroundColor White
    Write-Host "  Region: $global:currentAwsRegion" -ForegroundColor White

    # Get default instance ID and name
    $defaultInstanceId = Get-CurrentInstanceId
    if ($defaultInstanceId) {
        $defaultInstanceName = Get-InstanceNameById -InstanceId $defaultInstanceId
        if ($defaultInstanceName) {
            Write-Host "  Instance ID: $defaultInstanceId ($defaultInstanceName)" -ForegroundColor White
        } else {
            Write-Host "  Instance ID: $defaultInstanceId" -ForegroundColor White
        }
    } else {
        Write-Host "  Instance ID: (not configured)" -ForegroundColor DarkGray
    }

    # Display remote host configuration if available
    if ($global:currentAwsEnvironment -and $script:Config.environments.PSObject.Properties[$global:currentAwsEnvironment]) {
        $envConfig = $script:Config.environments.$global:currentAwsEnvironment

        Write-Host ""
        Write-Host "Default Remote Host Info:" -ForegroundColor Cyan

        # Get remote host instance ID
        $remoteHostInstanceId = ""
        if ($envConfig.instances.PSObject.Properties['remote-host']) {
            $remoteHostInstanceId = $envConfig.instances.'remote-host'
        }

        if ($remoteHostInstanceId) {
            $remoteHostInstanceName = Get-InstanceNameById -InstanceId $remoteHostInstanceId
            if ($remoteHostInstanceName) {
                Write-Host "  Remote Host Instance ID: $remoteHostInstanceId ($remoteHostInstanceName)" -ForegroundColor White
            } else {
                Write-Host "  Remote Host Instance ID: $remoteHostInstanceId" -ForegroundColor White
            }
        } else {
            Write-Host "  Remote Host Instance ID: (not configured)" -ForegroundColor DarkGray
        }

        $remoteIP = if ($envConfig.PSObject.Properties['defaultRemoteIP']) { $envConfig.defaultRemoteIP } else { "" }
        $remotePort = if ($envConfig.PSObject.Properties['defaultRemotePort']) { $envConfig.defaultRemotePort } else { "" }
        $localPort = if ($envConfig.PSObject.Properties['defaultLocalPort']) { $envConfig.defaultLocalPort } else { "" }

        if ($remoteIP) {
            Write-Host "  Remote IP: $remoteIP" -ForegroundColor White
        } else {
            Write-Host "  Remote IP: (not configured)" -ForegroundColor DarkGray
        }

        if ($remotePort) {
            Write-Host "  Remote Port: $remotePort" -ForegroundColor White
        } else {
            Write-Host "  Remote Port: (not configured)" -ForegroundColor DarkGray
        }

        if ($localPort) {
            Write-Host "  Local Port: $localPort" -ForegroundColor White
        } else {
            Write-Host "  Local Port: (not configured)" -ForegroundColor DarkGray
        }
    }

    Invoke-StandardPause
}

function Test-InstanceConnectivity {
    $instanceId = Get-CurrentInstanceId
    Get-Ec2InstanceInfo -InstanceId $instanceId -Title "Instance Connectivity Test"
}

function New-AlohaWrapperScript {
    <#
    .SYNOPSIS
    Creates a wrapper script for Aloha connections that displays instructions and handles errors.

    .PARAMETER Command
    The Aloha command to execute

    .PARAMETER AdditionalMessage
    Optional additional message to display in the banner (e.g., browser URL for non-RDP)

    .OUTPUTS
    Returns the path to the created wrapper script file
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Command,

        [Parameter(Mandatory=$false)]
        [string]$AdditionalMessage = ""
    )

    # Build the wrapper script content
    $wrapperScript = @"
`$ErrorActionPreference = 'Continue'
Write-Host ''
Write-Host '═══════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host '  ALOHA CONNECTION - IMPORTANT INSTRUCTIONS' -ForegroundColor Yellow
Write-Host '═══════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''
Write-Host '  When Aloha asks: Would you like to quit? (y/N)' -ForegroundColor White
Write-Host '  → Press ENTER or type N to keep connection alive' -ForegroundColor Green
Write-Host '  → DO NOT type Y or close this window!' -ForegroundColor Red
Write-Host ''
"@

    # Add additional message if provided (e.g., browser URL for non-RDP connections)
    if ($AdditionalMessage) {
        $wrapperScript += @"

Write-Host '  $AdditionalMessage' -ForegroundColor Cyan
"@
    }

    # Add command display and execution logic
    $wrapperScript += @"

Write-Host '  Command: $Command' -ForegroundColor Gray
Write-Host ''
Write-Host '═══════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

try {
    # Run Aloha command - run directly to allow interactive prompts
    Invoke-Expression "$Command"
} catch {
    Write-Host ''
    Write-Host 'Error running Aloha: `$(`$_.Exception.Message)' -ForegroundColor Red
}
"@

    # Save wrapper script to temp file
    $tempScript = Join-Path $env:TEMP "aloha_wrapper_$(Get-Date -Format 'yyyyMMddHHmmss').ps1"
    $wrapperScript | Out-File -FilePath $tempScript -Encoding UTF8

    return $tempScript
}

function Start-AlohaConnection {
    param([bool]$IsRdp = $false)

    Write-Host "Connecting to $global:remoteIP via Aloha..." -ForegroundColor Green

    # Build base aloha command with -y flag to auto-answer continue prompt
    # Don't use --rdp flag as Aloha's RDP launcher uses deprecated /console flag
    # Include AWS profile if available
    if ($global:currentAwsProfile -and $global:currentAwsProfile -ne "manual") {
        $Command = "aloha -i $global:awsInstance --localPort $global:localPort -f -r $global:remoteIP --remotePort $global:remotePort -y --profile $global:currentAwsProfile"
    } else {
        $Command = "aloha -i $global:awsInstance --localPort $global:localPort -f -r $global:remoteIP --remotePort $global:remotePort -y"
    }
    if ($IsRdp) {
        # Ask about RDP Manager for RDP connections
        $rdpChoice = Read-Host "Launch RDP Manager after connection? (Y/n)"

        Write-Host "Launching Aloha in new window: $Command" -ForegroundColor Green

        # Create wrapper script using helper function
        $tempScript = New-AlohaWrapperScript -Command $Command

        # Launch in new PowerShell window with custom title and no profile to avoid Oh-My-Posh conflicts
        $windowTitle = "Aloha Connection - $global:remoteIP"
        Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile", "-Command", "`$Host.UI.RawUI.WindowTitle = '$windowTitle'; & '$tempScript'" -WindowStyle Normal

        if ($rdpChoice -eq "" -or $rdpChoice.ToLower() -eq "y") {
            # Monitor Aloha output and launch RDP Manager when connection is ready
            Write-Host "Monitoring Aloha connection..." -ForegroundColor Cyan

            # Create a background job to monitor for port availability
            $monitorScript = @"
`$rdcManagerPath = '$($script:Config.paths.rdcManagerPath)'
`$localPort = $global:localPort

# Wait up to 30 seconds for the local port to become available
`$timeout = 30
`$elapsed = 0
`$connected = `$false

Write-Host 'Waiting for Aloha tunnel to establish on port '`$localPort'...' -ForegroundColor Gray

while (`$elapsed -lt `$timeout -and -not `$connected) {
    Start-Sleep -Seconds 1
    `$elapsed++

    # Check if the local port is listening
    try {
        `$listener = Get-NetTCPConnection -LocalPort `$localPort -State Listen -ErrorAction SilentlyContinue
        if (`$listener) {
            `$connected = `$true
            Write-Host 'Connection established! Launching RDP Manager...' -ForegroundColor Green
        }
    } catch {
        # Port not available yet, continue waiting
    }
}

if (`$connected) {
    Start-Sleep -Milliseconds 500
    Start-Process "`$rdcManagerPath"
} else {
    Write-Host 'Timeout waiting for connection. Port '`$localPort' did not become available.' -ForegroundColor Yellow
}
"@

            # Save monitor script
            $monitorScriptPath = Join-Path $env:TEMP "aloha_monitor_$(Get-Date -Format 'yyyyMMddHHmmss').ps1"
            $monitorScript | Out-File -FilePath $monitorScriptPath -Encoding UTF8

            # Start monitoring job in background with minimized window
            Start-Process -FilePath "pwsh" -ArgumentList "-Command", "`$Host.UI.RawUI.WindowTitle = 'RDP Manager Launcher'; & '$monitorScriptPath'" -WindowStyle Minimized
        }
    }
    else {
        # For web interfaces (SSH, HTTPS, etc.), launch tunnel in new window
        Write-Host "Launching Aloha in new window: $Command" -ForegroundColor Green
        Write-Host "Tunnel will be established. Connect via browser to: https://localhost:$global:localPort" -ForegroundColor Cyan

        # Create wrapper script using helper function with browser URL message
        $browserUrl = "Connect via browser to: https://localhost:$global:localPort"
        $tempScript = New-AlohaWrapperScript -Command $Command -AdditionalMessage $browserUrl

        # Launch in new PowerShell window with custom title and no profile to avoid Oh-My-Posh conflicts
        $windowTitle = "Aloha Connection - $global:remoteIP"
        Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile", "-Command", "`$Host.UI.RawUI.WindowTitle = '$windowTitle'; & '$tempScript'" -WindowStyle Normal
    }

    # Auto-continue timer with option to press Enter
    Invoke-TimedPause -TimeoutSeconds 30 -Message "Returning to menu"
}

function Get-VpnConnections {
    Write-Host "Getting VPN connections..." -ForegroundColor Cyan
    Write-Host ""

    # Build profile parameter using the stored AWS profile name
    $profileParam = if ($global:currentAwsProfile) {
        "--profile $global:currentAwsProfile"
    } else {
        ""
    }

    # Check if credentials are still valid using the correct profile
    try {
        $credCheckCmd = "aws sts get-caller-identity $profileParam 2>&1"
        $null = Invoke-Expression $credCheckCmd
        if ($LASTEXITCODE -ne 0) {
            Write-Host "AWS credentials have expired or are invalid." -ForegroundColor Red
            Write-Host "Please re-authenticate using 'Change AWS Account' option." -ForegroundColor Yellow
    Invoke-StandardPause
            return
        }
    }
    catch {
        Write-Host "Unable to verify AWS credentials." -ForegroundColor Red
    Invoke-StandardPause
        return
    }

    $searchString = Read-Host "Enter search string for VPN connections"

    if ([string]::IsNullOrWhiteSpace($searchString)) {
        Write-Host "No search string provided. Returning to menu." -ForegroundColor Yellow
        return
    }

    Write-Host "Searching for VPN connections containing: '$searchString'" -ForegroundColor Green
    Write-Host ""

    try {
        # Execute AWS CLI command to get VPN connections with profile parameter
        $vpnCmd = "aws ec2 describe-vpn-connections $profileParam --query 'VpnConnections[].{Name:Tags[?Key==``Name``].Value | [0],VpnConnectionId:VpnConnectionId}' --output text"
        $allVpnOutput = Invoke-Expression $vpnCmd

        # Filter results by search string
        $vpnOutput = $allVpnOutput -split "`n" | Where-Object { $_ -match $searchString }

        if ($vpnOutput) {
            Write-Host "VPN Connection Results:" -ForegroundColor Green
            Write-Host ""

            # Display header
            Write-Host ("{0,-40} {1}" -f "NAME", "VPN CONNECTION ID") -ForegroundColor Cyan
            Write-Host ("{0,-40} {1}" -f "----", "-----------------") -ForegroundColor Cyan

            # Parse and display VPN connections
            $vpnConnections = @()
            foreach ($line in $vpnOutput) {
                if ($line.Trim()) {
                    $parts = $line.Trim() -split "`t"
                    if ($parts.Length -ge 2) {
                        $name = $parts[0]
                        $id = $parts[1]

                        # Display formatted row
                        Write-Host ("{0,-40} {1}" -f $name, $id) -ForegroundColor White

                        # Store for later processing
                        $vpnConnections += @{
                            Name = $name
                            Id = $id
                        }
                    }
                }
            }

            Write-Host ""
            Write-Host "Total VPN connections found: $($vpnConnections.Count)" -ForegroundColor Green
            Write-Host ""

            # Ask about FortiGate configs
            if ($vpnConnections.Count -gt 0) {
                $configChoice = Read-Host "Pull FortiGate configurations for $($vpnConnections.Count) VPN connection(s)? (Y/n)"
                if ($configChoice -eq "" -or $configChoice.ToLower() -eq "y") {
                    Get-FortiGateConfigs -VpnConnections $vpnConnections
                }
            }
        }
        else {
            Write-Host "No VPN connections found matching '$searchString'" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "Error retrieving VPN connections: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Pause before returning to Instance Management menu
    Write-Host ""
    Invoke-StandardPause
}

function Get-FortiGateConfigs {
    param([array]$VpnConnections)

    Write-Host "Downloading FortiGate configurations for $($VpnConnections.Count) VPN connection(s)..." -ForegroundColor Cyan
    Write-Host ""

    # Build profile parameter using the stored AWS profile name
    $profileParam = if ($global:currentAwsProfile) {
        "--profile $global:currentAwsProfile"
    } else {
        ""
    }

    # Create output directory for configs
    # Use configured path if available, otherwise fall back to script directory
    if ($script:Config.paths.PSObject.Properties.Name -contains "vpnOutputPath" -and $script:Config.paths.vpnOutputPath) {
        $configOutputDir = $script:Config.paths.vpnOutputPath
    } else {
        # Fallback to script directory for backward compatibility
        $configOutputDir = Join-Path $PSScriptRoot "vpn_output"
    }

    if (-not (Test-Path $configOutputDir)) {
        New-Item -ItemType Directory -Path $configOutputDir -Force | Out-Null
    }

    $successCount = 0
    $failCount = 0

    foreach ($vpn in $VpnConnections) {
        $vpnId = $vpn.Id
        $vpnName = $vpn.Name

        Write-Host "Downloading config for: $vpnName ($vpnId)..." -ForegroundColor White

        try {
            # Download FortiGate-specific VPN configuration using AWS CLI
            $configFile = Join-Path $configOutputDir "$vpnName.txt"

            # Get the FortiGate device sample configuration from AWS
            # Device type ID 7125681a is for FortiGate
            $awsCommand = "aws ec2 get-vpn-connection-device-sample-configuration $profileParam --no-paginate --vpn-connection-id `"$vpnId`" --vpn-connection-device-type-id `"7125681a`" --internet-key-exchange-version `"ikev1`" --output text"
            $config = Invoke-Expression $awsCommand

            if ($config -and $config -ne "None" -and $LASTEXITCODE -eq 0) {
                # Save configuration to file
                $config | Out-File -FilePath $configFile -Encoding UTF8
                Write-Host "  Success - Saved to: $configFile" -ForegroundColor Green
                $successCount++
            }
            else {
                Write-Host "  Failed - No configuration available for $vpnName" -ForegroundColor Yellow
                $failCount++
            }
        }
        catch {
            Write-Host "  Failed - Error downloading config: $($_.Exception.Message)" -ForegroundColor Red
            $failCount++
        }

        Write-Host ""
    }

    # Summary
    Write-Host "Download Summary:" -ForegroundColor Cyan
    Write-Host "  Success: $successCount" -ForegroundColor Green
    Write-Host "  Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Yellow" } else { "Green" })
    Write-Host "  Output directory: $configOutputDir" -ForegroundColor Cyan
    Write-Host ""
}

# ==========================================
# ABOUT MENU
# ==========================================

function Show-AboutMenu {
    Clear-Host
    Write-Host ""
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host "  About PowerShell Console" -ForegroundColor Cyan
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host ""

    # Version Information
    Write-Host "Version Information:" -ForegroundColor Yellow
    Write-Host "  Console Version:  " -ForegroundColor Gray -NoNewline
    Write-Host $script:ConsoleVersion -ForegroundColor White

    # Get config version
    $configPath = Join-Path $PSScriptRoot "config.json"
    $configVersion = "unknown"
    if (Test-Path $configPath) {
        try {
            $config = Get-Content $configPath -Raw | ConvertFrom-Json
            $configVersion = $config.configVersion
        } catch {
            $configVersion = "error"
        }
    }
    Write-Host "  Config Version:   " -ForegroundColor Gray -NoNewline
    Write-Host $configVersion -ForegroundColor White

    if ($script:Environment) {
        Write-Host "  Environment:      " -ForegroundColor Gray -NoNewline
        Write-Host "[$script:Environment]" -ForegroundColor $script:EnvColor
    }
    Write-Host ""

    # Links
    Write-Host "Links:" -ForegroundColor Yellow
    Write-Host "  Repository:       " -ForegroundColor Gray -NoNewline
    Write-Host "https://github.com/Gronsten/powershell-console" -ForegroundColor Blue
    Write-Host "  Sponsor:          " -ForegroundColor Gray -NoNewline
    Write-Host "https://github.com/sponsors/Gronsten" -ForegroundColor Magenta
    Write-Host ""

    # Quick Help
    Write-Host "Command-line Options:" -ForegroundColor Yellow
    Write-Host "  .\console.ps1 --version    Display version information" -ForegroundColor Gray
    Write-Host "  .\console.ps1 --help       Display command-line help" -ForegroundColor Gray
    Write-Host ""

    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host ""
    Invoke-StandardPause
}

# --- Script Execution Start ---
# Only run main menu if script is executed directly (not sourced)
if ($MyInvocation.InvocationName -ne '.') {
    Show-MainMenu
}

