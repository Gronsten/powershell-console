# PowerShell Console - Architecture Guide

**Version:** 1.10.0
**Last Updated:** 2025-11-20
**Purpose:** Technical architecture reference for Claude AI assistant sessions

---

## Table of Contents

1. [Overview](#overview)
2. [Project Structure](#project-structure)
3. [Core Architecture](#core-architecture)
4. [Configuration System](#configuration-system)
5. [Major Subsystems](#major-subsystems)
6. [DEV/PROD Environment Model](#devprod-environment-model)
7. [Key Functions Reference](#key-functions-reference)
8. [Data Flow Diagrams](#data-flow-diagrams)
9. [External Dependencies](#external-dependencies)
10. [Common Development Patterns](#common-development-patterns)

---

## Overview

### What is PowerShell Console?

A comprehensive, interactive PowerShell management console (6,200+ lines) for:
- **AWS Infrastructure Management** - Multi-account AWS management with Okta SSO
- **Package Management** - Unified interface for Scoop, npm, pip, winget
- **Remote Access** - Automated AWS SSM port forwarding and RDP integration
- **Development Utilities** - Code counting, environment backups, network tools
- **System Administration** - Network diagnostics, configuration editing

### Core Design Principles

1. **Single-File Architecture** - All core functionality in [console.ps1](console.ps1:1) (~6,200 lines)
2. **JSON-Driven Configuration** - All settings in [config.json](config.json:1) with schema versioning
3. **Interactive Menu System** - Arrow-key navigation with persistent customization
4. **Environment Separation** - DEV (_dev/) for development, PROD (_prod/) for stable usage
5. **Modular Features** - Optional modules in modules/ directory
6. **Backward Compatibility** - Graceful fallback for old config schemas

---

## Project Structure

```
/root/AppInstall/dev/powershell-console/
├── _dev/                          # Development environment (Git repository)
│   ├── console.ps1               # Main application (6,200 lines, 69 functions)
│   ├── config.json               # User configuration (runtime, user-specific)
│   ├── config.example.json       # Template configuration (checked into Git)
│   ├── CHANGELOG.md              # Version history and release notes
│   ├── README.md                 # User documentation
│   ├── SETUP.md                  # Installation/configuration guide
│   ├── ARCHITECTURE.md           # This file - technical reference
│   ├── .gitignore                # Git exclusions (includes config.json)
│   │
│   ├── modules/                  # Optional feature modules
│   │   ├── aws-prompt-indicator/ # Oh-My-Posh AWS session indicator
│   │   │   ├── AwsPromptIndicator.psm1
│   │   │   ├── aws-prompt-theme.omp.json
│   │   │   ├── quick-term-aws.omp.json
│   │   │   └── README.md
│   │   └── backup-dev/           # Development environment backup utility
│   │       ├── backup-dev.ps1
│   │       ├── backup-dev.log
│   │       ├── backup-history.log
│   │       └── README.md
│   │
│   ├── scripts/                  # Utility scripts
│   │   ├── aws-logout.ps1        # Clean AWS credential logout
│   │   ├── count-lines.py        # Python-based line counter
│   │   └── README.md
│   │
│   ├── resources/                # Static data files
│   │   ├── npm-packages.json     # npm package database (3.6M+ packages)
│   │   └── README.md
│   │
│   └── .github/                  # GitHub Actions workflows
│       └── workflows/
│
├── _prod/                         # Production environment (user's daily driver)
│   ├── console.ps1               # Same as _dev (copied during upgrade)
│   ├── config.json               # PROD config (preserved during upgrades)
│   ├── [other files...]          # Mirror of _dev/ structure
│   └── vpn_output/               # Default VPN config export directory
│
└── upgrade-prod.ps1               # Smart upgrade script (not in Git repo)
    # Features:
    # - Downloads GitHub releases
    # - Smart config merge (preserves user values, adds new schema fields)
    # - Automatic REPOS.md version update
    # - PROD→DEV config sync (keeps DEV testing current)
```

### File Size Reference

- **console.ps1**: ~264KB, 6,212 lines
- **config.json**: ~12KB (user-specific, varies)
- **config.example.json**: ~6KB (template)
- **CHANGELOG.md**: ~64KB (comprehensive history)

---

## Core Architecture

### Application Flow

```
console.ps1 Execution Flow:
┌─────────────────────────────────────────────────┐
│ 1. Parameter Handling (--version, --help)       │
│    Lines 1-78                                    │
└────────────────┬────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────┐
│ 2. Console Initialization                       │
│    Lines 80-126                                  │
│    - UTF-8 encoding setup                       │
│    - Environment detection (DEV/PROD/UNKNOWN)   │
│    - Window title configuration                 │
│    - Original state preservation for cleanup    │
└────────────────┬────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────┐
│ 3. Configuration Loading                        │
│    Lines 128-249                                 │
│    - Import-Configuration (line 131)            │
│    - Load config.json into $script:Config       │
│    - Menu persistence functions                 │
└────────────────┬────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────┐
│ 4. Function Definitions (69 functions)          │
│    Lines 250-6100                                │
│    - Package management                         │
│    - AWS authentication                         │
│    - Menu system                                │
│    - Network utilities                          │
│    - Remote access (Aloha)                      │
│    - Instance management                        │
└────────────────┬────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────┐
│ 5. Main Menu Loop                               │
│    Lines 6100-6212                               │
│    - Show-ArrowMenu with Main Menu items        │
│    - Loop until Ctrl+X or exit selected        │
│    - Restore-ConsoleState on exit               │
└─────────────────────────────────────────────────┘
```

### Environment Detection

```powershell
# Lines 12-23: Automatic environment detection from path
$scriptPath = $PSScriptRoot
if ($scriptPath -match '[\\/]_dev[\\/]?$') {
    $script:Environment = "DEV"       # Yellow indicator
} elseif ($scriptPath -match '[\\/]_prod[\\/]?$') {
    $script:Environment = "PROD"      # Green indicator
} else {
    $script:Environment = "UNKNOWN"   # Red indicator
}
```

**Display**: `[DEV]` / `[PROD]` / `[UNKNOWN]` in window title and startup banner

---

## Configuration System

### Config Schema Architecture

**Two Configuration Files:**

1. **config.example.json** (Git-tracked)
   - Template with placeholder values
   - Defines schema structure
   - Updated with new features in development
   - Used by upgrade-prod.ps1 for schema reference

2. **config.json** (Git-ignored)
   - User's actual configuration
   - Contains real paths, AWS account IDs, custom settings
   - Separate files in _dev/ and _prod/ directories
   - Never committed to Git

### Config Schema Structure

```json
{
  "paths": {
    // File system paths
    "workingDirectory": "C:\\path\\to\\powershell-console",
    "profilePath": "C:\\Users\\...\\Microsoft.PowerShell_profile.ps1",
    "oktaYamlPath": "C:\\Users\\...\\.okta\\okta.yaml",
    "rdcManagerPath": "C:\\path\\to\\RDCMan.exe",
    "linksPath": "C:\\Users\\...\\Favorites\\Links\\",
    "devRoot": "C:\\path\\to\\dev",
    "vpnOutputPath": "C:\\path\\to\\vpn_output"  // v1.9.3+ (optional)
  },

  "defaultConnection": {
    // Default port forwarding settings
    "instance": "",
    "remoteIP": "",
    "localPort": "8443",
    "remotePort": "443"
  },

  "aws": {
    "defaultRegion": "us-east-1",
    "fortiGateDeviceTypeId": "7125681a"  // Optional
  },

  "environments": {
    // Dynamic: populated by AWS account sync
    // Structure: see "AWS Environment Schema" below
  },

  "actionDefinitions": {
    // Maps action IDs to menu entries
    "instanceManagement": {
      "text": "Instance Management",
      "highlightPos": 0,
      "highlightChar": "I",
      "function": "Show-InstanceManagementMenu"
    }
    // ... more actions
  },

  "standardActions": [
    // Common actions available across accounts
    {
      "text": "Change AWS Account",
      "highlightPos": 7,
      "highlightChar": "C",
      "function": "Show-AwsAccountMenu"
    }
  ],

  "menus": {
    // Customizable menu definitions
    "Main Menu": [ /* items */ ],
    "Package Manager": [ /* items */ ],
    "Instance Management": [ /* items */ ]
  },

  "awsAccountMenuOrder": [
    // Custom AWS account menu order
    "accountkey:RoleName",
    "anotheraccount:Admin"
  ],

  "awsPromptIndicator": {
    // Optional module configuration
    "directoryMappings": {
      "C:\\path\\to\\project": "123456789012"
    }
  },

  "lineCounter": {
    // Code line counter exclusion rules (scripts/count-lines.py)
    "globalExclusions": {
      "extensions": [".log", ".vsix"],        // File extensions to exclude everywhere
      "pathPatterns": ["log"]                 // Path segments to exclude (case-insensitive)
    },
    "projectExclusions": {
      "project-name": {
        "files": ["package-lock.json"],       // Exact filenames to exclude
        "filePatterns": ["temp_*"],           // Filename patterns (wildcards supported)
        "extensions": [".csv"],               // Project-specific extensions to exclude
        "pathPatterns": ["backup", "_prod"],  // Path segments to exclude
        "includeOnly": ["main.py"],           // Whitelist mode: only count these files
        "excludeAll": true                    // Exclude entire project from counts
      }
    }
  },

  "configVersion": "1.9.3"  // Schema version (not app version)
}
```

### AWS Environment Schema

```json
"accountkey": {
  // Required fields
  "displayName": "Friendly Account Name",
  "accountId": "123456789012",          // 12-digit AWS account ID
  "region": "us-east-1",

  // Multi-role authentication
  "availableRoles": ["Admin", "devops"],
  "preferredRole": "Admin",              // Last selected role
  "sessionDuration": "3600",             // Seconds (auto-discovered)

  // Okta profile mapping (generated by sync)
  "oktaProfileMap": {
    "Admin": "accountkey-OKTA-PROFILE-Admin",
    "devops": "accountkey-OKTA-PROFILE-devops"
  },

  // EC2 instance configuration
  "instances": {
    "jump-box": "i-0123456789abcdef0",    // Default bastion/jump instance
    "remote-host": "i-0fedcba9876543210"  // Default target instance
  },

  // Port forwarding defaults (for Aloha Remote Access)
  "defaultRemoteIP": "10.0.1.10",
  "defaultRemotePort": "3389",            // 3389=RDP, 443=HTTPS
  "defaultLocalPort": "8388",

  // Custom connection configurations
  "boxes": [
    {
      "name": "Custom Connection",
      "localPort": "8389",
      "remoteIP": "10.0.2.20",
      "remotePort": "3389"
    }
  ],

  // Available actions for this account
  "actions": [
    "instanceManagement",
    "alohaBox",
    "vpnConnections"
  ],

  // Custom menu names (optional)
  "customMenuNames": {
    "Admin": "Production Admin Access",
    "devops": "DevOps Role"
  },

  // Highlight configuration for menu display
  "highlightChar": "P",
  "highlightPos": 0
}
```

### Config Version Management

**configVersion field** tracks schema changes:
- Stored in config.json: `"configVersion": "1.9.3"`
- Updated when new fields are added to schema
- upgrade-prod.ps1 uses this to detect schema changes
- Separate from application version ($script:ConsoleVersion)

**Version Comparison Logic (upgrade-prod.ps1):**
```powershell
if ($prodConfigVersion -ne $newConfigVersion) {
    Write-Host "Config schema update detected" -ForegroundColor Yellow
    # Merge new fields from config.example.json
    # Preserve all existing user values
}
```

---

## Major Subsystems

### 1. Menu System

**Core Engine**: `Show-ArrowMenu` (lines ~900-1100)

**Features:**
- Arrow-key navigation (↑/↓)
- Keyboard shortcuts (highlighted characters)
- In-menu editing:
  - **Ctrl+Space**: Move items
  - **Ctrl+R**: Rename items
- Position memory (remembers last selection per menu)
- Multi-level navigation (ESC=back, Ctrl+X=exit)

**Menu Persistence:**
```powershell
Save-Menu -MenuTitle "Main Menu" -MenuItems $items
# Saves to config.json under "menus" section
# Format: { "text": "Item", "action": "scriptblock string" }

Get-MenuFromConfig -MenuTitle "Main Menu" -DefaultMenuItems $defaults
# Loads from config.json or returns defaults
# IMPORTANT (v1.10.0+): Merges new default items into saved configs
# This ensures code updates automatically add new menu options
```

**Menu Merging Behavior (v1.10.0+)**:
- If menu exists in config.json: Loads saved menu + merges any new default items
- New items from code updates are automatically appended to customized menus
- Prevents new features from being hidden when menu is customized
- Example: "Package Manager Cleanup" added in v1.10.0 appears even if menu was customized in v1.9.x

**Menu Position Memory:**
```powershell
Save-MenuPosition -MenuId "AWS-Account-Menu" -Position 5
Get-SavedMenuPosition -MenuId "AWS-Account-Menu"
# Stored in $script:MenuPositionMemory hashtable (session-scoped)
```

### 2. AWS Account Management

**Authentication Flow:**

```
1. User selects "AWS Login" from Main Menu
   └─> Start-AwsWorkflow (line ~3800)
       │
2. Show AWS Account Menu
   └─> Show-AwsAccountMenu (line ~4100)
       │ Reads: $script:Config.environments
       │ Builds menu dynamically
       │
3. User selects account + role
   └─> Invoke-AwsAuthentication (line ~4300)
       │ Reads: $env.oktaProfileMap[$role]
       │ Executes: okta-aws-cli web --profile <profile> --session-duration <duration>
       │ Sets: $global:currentAwsProfile, $global:currentAwsEnvironment
       │
4. Redirect to Instance Management or selected action
   └─> Show-InstanceManagementMenu (line ~5200)
```

**Account Synchronization:**

`Sync-AwsAccountsFromOkta` (line ~4500):
1. **Discovery**: `aws organizations list-accounts` (one-time Okta auth)
2. **Role Detection**: `aws iam list-roles` per account
3. **Session Duration**: Automatic discovery via `aws iam get-role`
4. **Config Update**: Creates/updates entries in `environments` section
5. **Okta YAML Update**: Adds missing profiles to ~/.okta/okta.yaml
6. **Backup**: Creates .backup files before modifications

**Key Global Variables:**
```powershell
$global:currentAwsProfile      # Current AWS profile name (from okta.yaml)
$global:currentAwsEnvironment  # Current environment key (from config.json)
$script:Config                 # Loaded configuration object
```

### 3. EC2 Instance Management

**Instance Selection**: `Select-Ec2Instance` (line ~5000)
- Uses `aws ec2 describe-instances` with current profile
- Filters: Running instances only
- Display: Name tag, Instance ID, Private IP, State, Type
- Arrow-key selection with Enter to confirm

**Default Instance Configuration:**
```powershell
Set-DefaultInstanceId
# Stores in: $script:Config.environments[$env].instances["jump-box"]
# Saves to: config.json

Set-DefaultRemoteHostInfo
# Stores in: $script:Config.environments[$env].defaultRemoteIP
#           $script:Config.environments[$env].defaultRemotePort
#           $script:Config.environments[$env].defaultLocalPort
```

**Running Instance Display**: `Get-RunningInstances` (line ~5100)
- Shows all running instances in current account/region
- Visual indicators: `[DEFAULT]` for jump-box, `[REMOTE HOST]` for remote-host
- Formatted table with Name, Instance ID, Private IP, State, Type

### 4. Aloha Remote Access (AWS SSM Port Forwarding)

**Purpose**: Automated AWS SSM port forwarding + RDP launcher

**Flow:**

```
Start-AlohaRemoteAccess (line ~5300)
  │ Prompts for: Local port, Remote IP, Remote port
  │ Uses defaults from config or user input
  │
  └─> Start-AlohaConnection (line ~5400)
      │
      ├─> Non-RDP Path (port != 3389)
      │   └─> New-AlohaWrapperScript (line ~5876)
      │       │ Creates temp .ps1 wrapper script
      │       │ Returns path to wrapper
      │   └─> Start-Process powershell -ArgumentList wrapper.ps1
      │       (Launches in NEW window, non-blocking)
      │
      └─> RDP Path (port == 3389)
          └─> New-AlohaWrapperScript (line ~5876)
              │ Creates temp .ps1 wrapper script
              │ Includes: SSM session start + RDP launcher
              └─> Start-Process powershell -ArgumentList wrapper.ps1
                  (Launches in NEW window with RDP integration)
```

**Wrapper Script**: `New-AlohaWrapperScript` (line ~5876)
- **Purpose**: Eliminates code duplication between RDP/non-RDP paths (v1.9.2)
- **Function**: Builds PowerShell script with:
  - Connection instructions
  - AWS SSM command execution
  - Optional additional messaging
  - Window stays open on completion
- **Returns**: Path to temporary .ps1 file

**Key SSM Command**:
```powershell
aws ssm start-session `
    --target $instanceId `
    --document-name AWS-StartPortForwardingSessionToRemoteHost `
    --parameters "localPortNumber=$localPort,host=$remoteIP,portNumber=$remotePort"
```

### 5. VPN Connection Management

**Get-VpnConnections** (line ~6100):
- Searches for VPN connections across AWS accounts
- Uses `aws ec2 describe-vpn-connections`
- Output formats:
  - Console table (Name, Connection ID)
  - Timestamped text file export
- **Export Location** (v1.9.3+):
  - Configurable: `$script:Config.paths.vpnOutputPath`
  - Fallback: `$PSScriptRoot\vpn_output` (backward compatible)

```powershell
# v1.9.3: Configurable output path
if ($script:Config.paths.PSObject.Properties.Name -contains "vpnOutputPath" -and
    $script:Config.paths.vpnOutputPath) {
    $configOutputDir = $script:Config.paths.vpnOutputPath
} else {
    # Fallback for old configs
    $configOutputDir = Join-Path $PSScriptRoot "vpn_output"
}
```

### 6. Package Management

**Unified Interface** for 4 package managers:
1. **Scoop** - Windows package manager
2. **npm** - Node.js global packages
3. **pip** - Python packages
4. **winget** - Windows Package Manager

**Update Management**: `Select-PackagesToUpdate` (line ~1500)
```
1. Check all package managers for available updates
   ├─> scoop status
   ├─> npm outdated -g --json
   ├─> pip list --outdated --format=json
   └─> winget upgrade --include-unknown

2. Combine results into unified list
   Format: "PackageName (Current → New) [Manager]"

3. Interactive checkbox selection
   └─> Show-CheckboxSelection (line ~1700)
       Arrow keys to navigate
       Spacebar to toggle selection
       'a' to select all
       Enter to confirm

4. Execute updates for selected packages
   Per-manager batch updates
```

**Package Search**:

- **npm Search** (line ~2100):
  - Ultra-fast (5x improvement in v1.2.3)
  - Uses local package database (~3.6M packages in resources/npm-packages.json)
  - PowerShell runspaces for parallel metadata fetching
  - Searches package names only (not descriptions)
  - Shows `[I]` indicator for installed packages
  - Auto-updates database if stale (>24 hours)

- **pip/PyPI Search** (line ~2300):
  - JSON API integration
  - Smart package discovery (python-X, X-python, pyX variations)
  - Shows version, summary, homepage

- **Installed Packages**: `Get-InstalledPackages` (line ~1400)
  - Lists all installed packages from all managers
  - Sorted alphabetically
  - Shows manager source for each package

### 7. Network Utilities

**Interactive Ping**: `Start-InteractivePing` (line ~800)
- Continuous ping with real-time latency display
- Color-coded status (Green=success, Red=timeout)
- Press 'Q' to quit
- Shows: Target, IP, Reply time, TTL

**Network Configuration**: `Show-NetworkConfiguration` (line ~900)
- Comprehensive network adapter display
- Shows: Status, Name, Description, Interface Index
- IP Addresses (IPv4/IPv6), DNS servers, DHCP status, Gateway
- Sorted: Status (Up first), IP type (routable first)
- Uses `Get-NetAdapter`, `Get-NetIPAddress`, `Get-NetIPConfiguration`

### 8. Development Utilities

**Code Line Counter**: `Start-CodeCount` (line ~3200)
- Python-based: scripts/count-lines.py
- **Configuration-driven exclusions** via config.json `lineCounter` section
- Features:
  - Global exclusions (apply to all projects)
  - Project-specific exclusions (files, extensions, path patterns)
  - Whitelist mode (includeOnly) for selective counting
  - Multiple encoding support (utf-8, latin-1, cp1252)
  - Interactive folder selection
  - CLI support for automation
- Execution: `python count-lines.py` (reads from config.json)
- Output: Color-coded table with included/excluded file counts per project
- Configuration: Edit `config.json` → `lineCounter` section to customize exclusions

**Backup Dev Environment**: `Start-BackupDevEnvironment` (line ~3300)
- Module: modules/backup-dev/backup-dev.ps1
- Features:
  - Two-pass operation (count → backup)
  - Multiple modes: full, test (limited ops), list-only, count-only
  - Visual progress indicators (spinner, percentage)
  - Dual logging: detailed log + rotating summary history (last 7)
  - Uses robocopy with /MIR flag (true synchronization)
  - GNU-style arguments (--test-mode, --list-only, --count, --help)
- Execution:
  ```powershell
  .\modules\backup-dev\backup-dev.ps1 --test-mode
  .\modules\backup-dev\backup-dev.ps1        # Full backup
  ```

---

## DEV/PROD Environment Model

### Purpose

**DEV (_dev/)**:
- Active development environment
- Git repository location (.git folder)
- All git operations run from here
- Config gets stale (never updated directly)

**PROD (_prod/)**:
- Stable production environment for daily use
- User's actual working console
- Config stays current via upgrade script
- Not a Git repository

### Upgrade Flow

**upgrade-prod.ps1** (parent directory, not in Git):

```
1. Fetch Release from GitHub
   └─> gh release view [version] --json tagName,name
       (Defaults to latest if no version specified)

2. Download Release Archive
   └─> gh release download $version -p "*.zip" -D $tempPath

3. Extract to Temporary Location
   └─> Expand-Archive -Path $zipPath -DestinationPath $tempPath

4. Detect Version Information
   ├─> Application Version (from console.ps1 header)
   │   $script:ConsoleVersion = "1.9.3"
   └─> Config Schema Version (from config.example.json)
       "configVersion": "1.9.3"

5. Smart Config Merge
   └─> If PROD configVersion != new configVersion:
       ├─> Load PROD config.json (user values)
       ├─> Load new config.example.json (schema reference)
       ├─> Merge-Configuration
       │   ├─> Add NEW fields from example (with placeholder values)
       │   ├─> Preserve ALL existing user values
       │   ├─> Track custom fields by category:
       │   │   ├─> Custom AWS Environments
       │   │   ├─> Custom Directory Mappings
       │   │   └─> Other Custom Fields
       │   └─> Create backup: config.json.backup
       └─> Display verbose merge summary

6. Copy Files to PROD
   └─> Selective copy (excludes .git, .github, *.md unless needed)

7. Update REPOS.md (Automatic)
   └─> Regex replacement of PROD version
       Pattern: (v[\d\.]+ \(DEV\), )v[\d\.]+ \(PROD\)
       Replace: $1v1.9.3 (PROD)

8. Sync PROD Config to DEV (Automatic)
   └─> Copy-Item $prodPath/config.json $devPath/config.json -Force
       Creates backup first: config.json.backup
       Purpose: Keeps DEV testing environment current with PROD schema
```

**Key Features:**
- **Preserves user customizations** during upgrades
- **No manual config editing required** (schema changes auto-merged)
- **Automatic REPOS.md tracking** (no manual version updates)
- **DEV stays current** (copies PROD config after successful upgrade)
- **Rollback capability** (creates .backup files)

### Config Merge Categories

**Custom AWS Environments**: User's AWS accounts not in example
```
[✓] Custom AWS Environments Preserved (green)
    - acme-prod (Admin, devops)
    - acme-dev (Admin)
```

**Custom Directory Mappings**: awsPromptIndicator.directoryMappings
```
[✓] Custom Directory Mappings Preserved (green)
    - /root/projects/acme-app → 123456789012
```

**Other Custom Fields**: Any other user additions
```
[~] Other Custom Fields Preserved (yellow)
    - environments.customaccount.customSetting = "value"
    (Review CHANGELOG.md for guidance on custom fields)
```

### Why PROD→DEV Sync?

**Problem**: DEV config.json never gets updated during development
- config.example.json gets new fields
- DEV config.json stays on old schema
- Testing doesn't reflect actual user experience

**Solution**: After PROD upgrade succeeds:
1. PROD config.json has fresh merged schema (all new fields + user values)
2. Copy PROD config → DEV config (with backup)
3. DEV environment now matches PROD schema
4. Testing reflects actual user configuration

---

## Key Functions Reference

### Configuration Functions (Lines 131-249)

| Function | Purpose | Returns |
|----------|---------|---------|
| `Import-Configuration` | Load config.json into PowerShell object | PSCustomObject |
| `Update-ScriptConfiguration` | Reload config after changes | void |
| `Save-Menu` | Persist menu customizations to config.json | void |
| `Get-MenuFromConfig` | Load menu from config or return defaults | Array |
| `Get-AwsAccountMenuOrder` | Get saved AWS account menu order | Array or $null |
| `Save-AwsAccountMenuOrder` | Save AWS account menu order | void |
| `Save-AwsAccountCustomName` | Save custom display name for account+role | void |
| `Get-AwsAccountCustomName` | Get custom display name | String or $null |

### Package Management Functions (Lines 250-900)

| Function | Purpose | Key Features |
|----------|---------|--------------|
| `Update-Check` | Check all package managers for updates | Returns combined update list |
| `Update-All` | Update all packages across all managers | Calls individual update functions |
| `Update-Scoop` | Update Scoop packages | Executes `scoop update *` |
| `Update-npm` | Update npm global packages | Parses `npm outdated -g --json` |
| `Update-Winget` | Update winget packages | Parses `winget upgrade` output |
| `Update-Pip` | Update pip packages | Uses `pip list --outdated --format=json` |
| `Get-InstalledPackages` | List all installed packages | Combines all package managers |
| `Select-PackagesToUpdate` | Interactive update selection | Checkbox interface |
| `Show-CheckboxSelection` | Generic checkbox selection UI | Arrow keys + spacebar |
| `Search-Packages` | Search for packages | npm (local DB) + pip (API) |

### Menu System Functions (Lines 900-1500)

| Function | Purpose | Key Features |
|----------|---------|--------------|
| `Show-ArrowMenu` | Core menu navigation engine | Arrow keys, shortcuts, Ctrl+Space, Ctrl+R |
| `New-MenuAction` | Create menu item with action | Returns hashtable with Text/Action |
| `Get-SavedMenuPosition` | Retrieve last menu position | Session-scoped memory |
| `Save-MenuPosition` | Store menu position | For position persistence |

### Network Utility Functions (Lines 800-900)

| Function | Purpose | Key Features |
|----------|---------|--------------|
| `Start-InteractivePing` | Continuous ping utility | Real-time display, press 'Q' to quit |
| `Show-NetworkConfiguration` | Display network adapter info | Comprehensive details, sorted display |
| `Convert-PrefixToSubnetMask` | Convert CIDR to subnet mask | Helper for network display |

### AWS Authentication Functions (Lines 3800-4900)

| Function | Purpose | Key AWS CLI Commands |
|----------|---------|---------------------|
| `Start-AwsWorkflow` | Main AWS login entry point | Entry to authentication flow |
| `Show-AwsAccountMenu` | Display AWS account selection | Reads $script:Config.environments |
| `Invoke-AwsAuthentication` | Execute Okta authentication | `okta-aws-cli web --profile X --session-duration Y` |
| `Sync-AwsAccountsFromOkta` | Discover accounts from Okta | `aws organizations list-accounts`, `aws iam list-roles` |
| `Get-AwsAccountDisplayName` | Build menu display name | Handles custom names, role info |

### EC2 Instance Management Functions (Lines 5000-5300)

| Function | Purpose | Key AWS CLI Commands |
|----------|---------|---------------------|
| `Show-InstanceManagementMenu` | Instance management menu | Menu navigation |
| `Get-RunningInstances` | List running EC2 instances | `aws ec2 describe-instances --filters Name=instance-state-name,Values=running` |
| `Select-Ec2Instance` | Interactive instance selection | Arrow-key selection with Enter |
| `Set-DefaultInstanceId` | Configure default jump box | Stores in config.json |
| `Set-DefaultRemoteHostInfo` | Configure remote host settings | Stores in config.json |
| `Show-CurrentInstanceSettings` | Display current config | Reads from config.json |
| `Test-InstanceConnectivity` | Test SSM connectivity | `aws ssm describe-instance-information` |

### Aloha Remote Access Functions (Lines 5300-6000)

| Function | Purpose | Key Features |
|----------|---------|--------------|
| `Start-AlohaRemoteAccess` | Main Aloha entry point | Prompts for connection details |
| `Start-AlohaConnection` | Core SSM port forwarding | RDP detection, wrapper generation |
| `New-AlohaWrapperScript` | Generate wrapper script | Builds temp .ps1 with SSM command (v1.9.2) |
| `Show-AlohaBoxMenu` | Aloha box selection menu | For pre-configured connections |

**Key AWS SSM Command**:
```powershell
aws ssm start-session `
    --target $instanceId `
    --document-name AWS-StartPortForwardingSessionToRemoteHost `
    --parameters "localPortNumber=$localPort,host=$remoteIP,portNumber=$remotePort"
```

### VPN Management Functions (Lines 6100-6200)

| Function | Purpose | Key AWS CLI Commands |
|----------|---------|---------------------|
| `Get-VpnConnections` | Search and export VPN connections | `aws ec2 describe-vpn-connections` |

**v1.9.3 Change**: Configurable output path with backward compatible fallback

### Development Utility Functions (Lines 3200-3500)

| Function | Purpose | External Script |
|----------|---------|----------------|
| `Start-CodeCount` | Count code lines | `python scripts/count-lines.py` |
| `Start-BackupDevEnvironment` | Backup dev directory | `.\modules\backup-dev\backup-dev.ps1` |
| `Start-MerakiBackup` | Meraki config backup | External Python script |

### Utility/Helper Functions (Throughout)

| Function | Purpose | Location |
|----------|---------|----------|
| `Invoke-StandardPause` | Standard "Press any key" pause | Used throughout |
| `Invoke-TimedPause` | Auto-continue with countdown | Used throughout |
| `Restore-ConsoleState` | Cleanup on exit | Line 109, called on script exit |

---

## Data Flow Diagrams

### AWS Authentication Data Flow

```
User Input (Account Selection)
        │
        ▼
┌───────────────────────────────────────────────┐
│ $script:Config.environments                    │
│   └─> accountkey                               │
│       ├─> oktaProfileMap["Admin"]              │
│       └─> sessionDuration                      │
└───────────────────┬───────────────────────────┘
                    │
                    ▼
┌───────────────────────────────────────────────┐
│ Invoke-AwsAuthentication                       │
│   └─> okta-aws-cli web                         │
│       --profile accountkey-OKTA-PROD-Admin     │
│       --session-duration 3600                  │
└───────────────────┬───────────────────────────┘
                    │
                    ▼
┌───────────────────────────────────────────────┐
│ ~/.aws/credentials                             │
│   [default] profile updated                    │
└───────────────────┬───────────────────────────┘
                    │
                    ▼
┌───────────────────────────────────────────────┐
│ Global State Variables                         │
│   $global:currentAwsProfile                    │
│   $global:currentAwsEnvironment                │
└───────────────────┬───────────────────────────┘
                    │
                    ▼
┌───────────────────────────────────────────────┐
│ AWS CLI Operations                             │
│   All subsequent aws commands use [default]    │
│   profile automatically                        │
└───────────────────────────────────────────────┘
```

### Config Merge Flow (upgrade-prod.ps1)

```
GitHub Release (v1.9.3)
        │
        ├─> console.ps1 (new code)
        └─> config.example.json (new schema)
                │
                ▼
        Merge-Configuration Function
                │
    ┌───────────┴───────────┐
    │                       │
    ▼                       ▼
PROD config.json      config.example.json
(User values)         (New schema fields)
    │                       │
    │  ┌──────────────────┐ │
    │  │ Field Comparison │ │
    │  └────────┬─────────┘ │
    │           │           │
    │  ┌────────▼─────────┐ │
    │  │ Exists in PROD?  │ │
    │  └────────┬─────────┘ │
    │           │           │
    │      ┌────┴────┐      │
    │      │ YES│ NO │      │
    │      │    │    │      │
    └──────┤    │    ├──────┘
           │    │    │
      Keep │    │ Add│ from example
      user │    │ new│ (placeholder)
     value │    │ field
           │    │    │
           └────┴────┘
                │
                ▼
      Merged config.json
    (All user values preserved,
     all new fields added)
                │
                ▼
    Save to PROD config.json
    (Create .backup first)
```

### Menu Position Memory Flow

```
User navigates menu → Position 5
        │
        ▼
Show-ArrowMenu detects selection
        │
        ▼
Save-MenuPosition "AWS-Account-Menu" 5
        │
        ▼
$script:MenuPositionMemory["AWS-Account-Menu"] = 5
(Session-scoped, not persisted to disk)
        │
User returns to menu
        │
        ▼
Get-SavedMenuPosition "AWS-Account-Menu"
        │
        ▼
Returns: 5
        │
        ▼
Show-ArrowMenu starts at position 5
(Menu cursor on previously selected item)
```

---

## External Dependencies

### Required Software

| Dependency | Purpose | Installation | Verification |
|------------|---------|-------------|--------------|
| **PowerShell 5.1+** or **PowerShell 7+** | Runtime environment | Built-in (Windows) or [Download](https://github.com/PowerShell/PowerShell) | `$PSVersionTable.PSVersion` |
| **AWS CLI v2** | AWS API interactions | [Download](https://aws.amazon.com/cli/) | `aws --version` |
| **okta-aws-cli** | Okta SSO authentication | `scoop install okta-aws-cli` or [GitHub](https://github.com/okta/okta-aws-cli) | `okta-aws-cli --version` |
| **Session Manager Plugin** | AWS SSM connections | [Download](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) | `session-manager-plugin --version` |

### Optional Software

| Dependency | Purpose | Installation |
|------------|---------|-------------|
| **Scoop** | Windows package manager | [scoop.sh](https://scoop.sh/) |
| **npm** | Node.js package manager | Comes with [Node.js](https://nodejs.org/) |
| **winget** | Windows Package Manager | Built-in (Win11) or Microsoft Store |
| **Python 3.x** | Line counter script | [python.org](https://www.python.org/) |
| **oh-my-posh** | Prompt theming (for aws-prompt-indicator) | `winget install JanDeDobbeleer.OhMyPosh` |
| **posh-git** | Git prompt integration | `Install-Module posh-git -Scope CurrentUser` |

### AWS IAM Permissions Required

For full functionality, AWS IAM roles must have:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeVpnConnections",
        "ssm:StartSession",
        "ssm:DescribeInstanceInformation",
        "organizations:ListAccounts",  // For sync feature
        "iam:ListRoles",                // For sync feature
        "iam:GetRole"                   // For session duration discovery
      ],
      "Resource": "*"
    }
  ]
}
```

**Note**: `organizations:*` and some `iam:*` actions only needed for `Sync-AwsAccountsFromOkta` feature.

---

## Common Development Patterns

### 1. Adding a New Menu Item

**Location**: [console.ps1](console.ps1:1), Main Menu section (~line 6100)

```powershell
# Step 1: Define menu item
$menuItems = Get-MenuFromConfig -MenuTitle "Main Menu" -DefaultMenuItems @(
    (New-MenuAction "Ping Google" {
        Start-InteractivePing -Target "google.com"
        pause
    }),
    # ... existing items ...
    (New-MenuAction "My New Feature" {  # <-- Add here
        Invoke-MyNewFunction
        pause
    })
)

# Step 2: Implement function (earlier in file)
function Invoke-MyNewFunction {
    Write-Host "My new feature!" -ForegroundColor Green
    # Implementation here
}
```

**Menu Persistence**: Changes saved to config.json automatically via Ctrl+Space/Ctrl+R

### 2. Adding a New Config Field

**Step 1**: Add to [config.example.json](config.example.json:1)
```json
{
  "paths": {
    "existingPath": "...",
    "myNewPath": "C:\\path\\to\\new\\location"
  }
}
```

**Step 2**: Update configVersion in config.example.json
```json
{
  "configVersion": "1.10.0"  // Increment from 1.9.3
}
```

**Step 3**: Access in code (with backward compatibility)
```powershell
# Check if field exists (for old configs)
if ($script:Config.paths.PSObject.Properties.Name -contains "myNewPath" -and
    $script:Config.paths.myNewPath) {
    $newPath = $script:Config.paths.myNewPath
} else {
    # Fallback for old configs
    $newPath = Join-Path $PSScriptRoot "default_location"
}
```

**Step 4**: Document in CHANGELOG.md
```markdown
### v1.10.0 (2025-XX-XX)

**Config Changes Required:**
- Added `paths.myNewPath` (string) - Path to new feature location

**New Features:**
- Feature description...
```

**Result**: upgrade-prod.ps1 will automatically merge this field into user's config during next upgrade

### 3. Adding a New Environment-Specific Setting

**Step 1**: Add to environment schema in [config.example.json](config.example.json:1)
```json
{
  "environments": {
    "acmeaccount": {
      "displayName": "ACME Account",
      "myNewSetting": "default value"  // <-- Add here
    }
  }
}
```

**Step 2**: Update sync function to populate it (if auto-discovered)
```powershell
# In Sync-AwsAccountsFromOkta function
$newEnvironment = @{
    displayName = $account.Name
    accountId = $account.Id
    # ... existing fields ...
    myNewSetting = "discovered value"  # <-- Add here
}
```

**Step 3**: Access in code
```powershell
$setting = $script:Config.environments[$global:currentAwsEnvironment].myNewSetting
```

### 4. Adding a New AWS CLI Operation

**Pattern**: Wrap AWS CLI calls with error handling

```powershell
function Get-MyAwsResource {
    param(
        [string]$ResourceId
    )

    # Check for active AWS session
    if (-not $global:currentAwsProfile) {
        Write-Host "Error: Not authenticated to AWS" -ForegroundColor Red
        return
    }

    Write-Host "Fetching resource: $ResourceId..." -ForegroundColor Yellow

    try {
        # Execute AWS CLI command
        $result = aws myservice describe-resources `
            --resource-id $ResourceId `
            --region $script:Config.environments[$global:currentAwsEnvironment].region `
            --output json | ConvertFrom-Json

        if ($LASTEXITCODE -ne 0) {
            throw "AWS CLI command failed with exit code $LASTEXITCODE"
        }

        # Process and display results
        $result | Format-Table -AutoSize

        return $result

    } catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "This may indicate expired credentials or insufficient permissions." -ForegroundColor Yellow
        return $null
    }
}
```

### 5. Working with Module Code

**aws-prompt-indicator module** (not loaded by console.ps1):
- **Location**: [modules/aws-prompt-indicator/](modules/aws-prompt-indicator/)
- **Loading**: Via PowerShell profile (not console.ps1)
- **Config**: Reads from console config.json
- **Usage**: See [modules/aws-prompt-indicator/README.md](modules/aws-prompt-indicator/README.md:1)

**backup-dev module**:
- **Location**: [modules/backup-dev/backup-dev.ps1](modules/backup-dev/backup-dev.ps1:1)
- **Invocation**: `Start-BackupDevEnvironment` in console.ps1
- **Execution**: `.\modules\backup-dev\backup-dev.ps1 [args]`
- **Standalone**: Can be run directly outside console.ps1

### 6. Version Bumping (Critical for Releases)

**Required Changes for Every Release:**

**1. Update console.ps1 header** (line 10):
```powershell
$script:ConsoleVersion = "1.10.0"  # From 1.9.3
```

**2. Update config.example.json** (if schema changed):
```json
{
  "configVersion": "1.10.0"  // Match app version if schema changed
}
```

**3. Update CHANGELOG.md**:
```markdown
### v1.10.0 (2025-XX-XX)

**New Features:**
- Feature description

**Bug Fixes:**
- Fix description

**Config Changes:**
- Document any new config fields
```

**4. Create PR with version bump included**:
```bash
# In _dev/ directory
git checkout -b feature/my-feature
# Make code changes
# Update version in console.ps1
# Update CHANGELOG.md
git add .
git commit -S -m "Add new feature and bump version to 1.10.0

- Feature implementation
- Version bump to 1.10.0
- Updated CHANGELOG

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
git push -u origin feature/my-feature
gh pr create --title "Add new feature (v1.10.0)" --body "..." --base main
```

**5. After PR merge, create GitHub release**:
```bash
gh release create v1.10.0 \
    --title "v1.10.0 - Feature Name" \
    --notes "Release notes from CHANGELOG.md"
```

### 7. Testing in DEV vs PROD

**DEV Testing** (_dev/ directory):
```powershell
cd /root/AppInstall/dev/powershell-console/_dev
.\console.ps1

# Window title shows: [DEV] PowerShell Console v1.9.3
# Banner shows: [DEV] PowerShell Console v1.9.3
```

**PROD Testing** (_prod/ directory):
```powershell
cd /root/AppInstall/dev/powershell-console/_prod
.\console.ps1

# Window title shows: [PROD] PowerShell Console v1.9.2
# Banner shows: [PROD] PowerShell Console v1.9.2
```

**Upgrade PROD to Test New Version**:
```powershell
cd /root/AppInstall/dev/powershell-console
.\upgrade-prod.ps1            # Latest release
.\upgrade-prod.ps1 -Version v1.9.3  # Specific version
```

---

## Troubleshooting Tips for Claude

### Common Issues When Developing

**1. "Function not found" errors**
- **Cause**: Functions must be defined before they're called
- **Solution**: Check function definition order in console.ps1
- **Pattern**: Utility functions at top, feature functions in middle, menu loop at bottom

**2. Config changes not reflecting**
- **Cause**: Config cached in `$script:Config`
- **Solution**: Call `Update-ScriptConfiguration` or restart console.ps1
- **Note**: Menu customizations save automatically, but path changes require reload

**3. AWS CLI commands failing**
- **Cause**: No active AWS session or expired credentials
- **Check**: `$global:currentAwsProfile` should be set
- **Solution**: Re-authenticate via "Change AWS Account" menu

**4. Menu items not persisting**
- **Cause**: config.json not writable or incorrect save call
- **Check**: File permissions, `Save-Menu` function calls
- **Note**: Only changes via Ctrl+Space/Ctrl+R are auto-saved

**5. Environment detection issues**
- **Cause**: Script running from unexpected location
- **Check**: `$PSScriptRoot` should end in `_dev` or `_prod`
- **Solution**: Run from correct directory

### Key Files to Check When Debugging

| Issue | Check File/Location |
|-------|-------------------|
| Config not loading | [config.json](config.json:1), line 131 (Import-Configuration) |
| AWS authentication failing | [config.json](config.json:1) environments section, ~/.okta/okta.yaml |
| Menu not working | Lines 900-1100 (Show-ArrowMenu function) |
| Package manager errors | Lines 250-900 (package management functions) |
| Aloha connection failing | Lines 5300-6000 (Aloha functions), AWS SSM permissions |
| VPN export path wrong | Lines 6100-6200, config.json paths.vpnOutputPath |

### Understanding Error Messages

**"RequestExpired" from AWS CLI**:
- AWS credentials have expired
- Solution: Re-authenticate via "Change AWS Account"

**"InvalidInstanceID" from AWS SSM**:
- Instance ID not found or incorrect region
- Check: `$script:Config.environments[$env].instances`
- Check: `$script:Config.environments[$env].region`

**"AccessDenied" from AWS CLI**:
- IAM role lacks required permissions
- Check: IAM policy includes necessary actions

**"Profile not found" from okta-aws-cli**:
- Profile name mismatch between config.json and okta.yaml
- Check: `$script:Config.environments[$env].oktaProfileMap`
- Solution: Re-run Sync-AwsAccountsFromOkta

---

## Additional Resources

- **[README.md](README.md:1)**: User-facing documentation, features, usage
- **[SETUP.md](SETUP.md:1)**: Installation and configuration guide
- **[CHANGELOG.md](CHANGELOG.md:1)**: Complete version history (~64KB)
- **CLAUDE.md**: Project-wide Claude instructions (parent directory)
- **REPOS.md**: Repository inventory (parent directory)

---

## Quick Reference: Key Line Numbers

| Feature | Approximate Line Range |
|---------|----------------------|
| Version constant | Line 10 |
| Environment detection | Lines 12-23 |
| Console initialization | Lines 80-126 |
| Config loading | Lines 128-249 |
| Package management | Lines 250-900 |
| Menu system | Lines 900-1500 |
| Network utilities | Lines 800-900 |
| AWS authentication | Lines 3800-4900 |
| EC2 instance management | Lines 5000-5300 |
| Aloha remote access | Lines 5300-6000 |
| VPN connections | Lines 6100-6200 |
| Main menu loop | Lines 6100-6212 |

**Note**: Line numbers approximate due to ongoing development. Use function names for reliable code location.

---

**End of Architecture Document**

*For questions about features, see [README.md](README.md:1). For setup help, see [SETUP.md](SETUP.md:1).*
