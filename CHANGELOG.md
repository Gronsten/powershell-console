# Changelog

All notable changes to this project have been documented during development.

## Table of Contents

- [Version History](#version-history)
- [Development Utilities](#development-utilities)
- [Menu System Enhancements](#menu-system-enhancements)
- [AWS Account Management](#aws-account-management)
- [Instance Management](#instance-management)
- [Remote Access Features](#remote-access-features)
- [Package Manager Integration](#package-manager-integration)
- [Network Utilities](#network-utilities)
- [User Experience Improvements](#user-experience-improvements)
- [Bug Fixes](#bug-fixes)
- [Code Cleanup](#code-cleanup)

---

## Version History

### v1.15.0 (2025-12-29)

**New Features:**
- **backup-dev: View Backup Logs** - Open logs directly in VS Code
  - New menu item: "View Detailed Log" - Opens most recent backup log
  - New menu item: "View Backup History" - Opens summary of last 10 backups
  - Similar to existing "PowerShell Profile Edit" and "Okta YAML Edit" menu items

- **backup-dev: Deprecated Files Management** - Find and clean old backup files
  - New menu item: "Show Deprecated Files" - Scan for files in backup but not in source
  - Preview first 20 deprecated items with counts
  - Option 1: View full list in VS Code (generates detailed report)
  - Option 2: Clean deprecated files with confirmation (requires typing "DELETE")
  - Progress bar during cleanup showing percentage and deleted counts
  - Useful when using `/E` mode (copy without mirror) to remove accumulated old files

**Bug Fixes:**
- **Fixed "TRUE" output after backup** - Added explicit `exit 0` at end of backup-dev.ps1
  - Problem: Script was returning `$logRotated = $true` value to console
  - Solution: Explicit exit code prevents unintended output

**Documentation:**
- **Clarified dry run vs count modes** - Both serve distinct purposes
  - COUNT mode: Quick scan, counts files/dirs, shows what needs copying, exits immediately
  - DRY RUN mode: Full simulation of backup without copying, detailed progress, slower but comprehensive

### v1.14.0 (2025-12-23)

**Config Changes Required:**
- Added `backupDev.exclusions` section for interactive exclusion management
- Migrated to unified exclusion structure: `backupDev.exclusions.{directories,files}`
- Config version: `config.11` → `config.12`
- **Action Required:** Add the `backupDev` section from `config.example.json` to your `config.json`

**New Features:**
- **backup-dev: Interactive Exclusion Management** - Manage exclusions without editing JSON
  - New menu item: "Manage Exclusions" in Backup Dev menu
  - Checkbox interface for viewing/removing exclusions
  - Add new exclusions with `+` key
  - Comma-separated bulk input support (add multiple patterns at once)
  - Real-time validation and duplicate detection
  - Auto-migrates old exclusion structure to new unified format
  - File: `modules/backup-dev/backup-exclusions.ps1`

- **line-counter: Interactive Exclusion Management** - Parallel implementation for code counting
  - New menu item: "Manage Exclusions" in Code Count menu
  - Same checkbox interface as backup-dev
  - Manage extensions and path patterns interactively
  - Comma-separated bulk input support
  - File: `modules/line-counter/line-counter-exclusions.ps1`
- **backup-dev: Configurable Exclusion System** - Exclude directories and files from backups
  - `excludeDirectories` - Array of directory names to exclude anywhere in tree (e.g., `node_modules`, `.git`, `bin`, `obj`)
  - `excludeFiles` - Array of file patterns to exclude with wildcard support (e.g., `*.log`, `*.tmp`, `*.vhdx`)
  - `customExclusions.directories` - User-defined directory exclusions
  - `customExclusions.files` - User-defined file exclusions
  - All exclusions combine (default + custom)
  - Dramatically reduces backup size and time (50-93% reduction in test scenarios)
  - Default exclusions include: development artifacts, IDE configs, build outputs, temporary files, VM images

- **backup-dev: Safer Default Backup Mode** - Changed from mirror to copy mode for safety
  - `mirrorMode` config option (default: `false`)
  - When `false` (default): Uses `/E` flag - copies files WITHOUT deleting extras (safer)
  - When `true`: Uses `/MIR` flag - exact mirror WITH deletions (dangerous, use with caution)
  - Clear warning displayed when mirror mode is enabled
  - Prevents accidental data loss from incomplete or corrupted source

- **backup-dev: Dry-Run Mode** - Safe testing without copying files
  - New `--dry-run` flag simulates full backup without copying (uses robocopy `/L` flag)
  - Shows complete progress tracking and statistics
  - Perfect for testing exclusions and backup behavior in DEV before running in PROD
  - Clearly indicates simulation mode with cyan-colored messages
  - Logs show "DRY-RUN" mode and `/L` flag in robocopy options

**Improvements:**
- **backup-history.log: Compact Summary Format** - Stores only statistics, not full file listings
  - Reduced log size from 16MB to <1KB per backup session
  - Tracks last 10 backups (increased from 7)
  - Mode tracking: FULL, DRY-RUN, TEST, COUNT
  - Inverted order: newest backups at top for easy viewing
  - Fixed `Get-LastBackupTimestamp` to read from backup-history.log and find last FULL backup only

- **count-lines.py: Relocated to Module Directory** - Better organization
  - Moved from `scripts/count-lines.py` to `modules/line-counter/count-lines.py`
  - Script now lives with its related PowerShell module
  - Added `--config` argument to explicitly specify config.json path
  - PowerShell passes config path explicitly (no more guessing from script location)

- **backup-dev: Better Progress Feedback** - Enhanced status messages
  - Displays configured exclusion status on startup
  - Shows backup mode (COPY vs MIRROR) with safety warnings
  - Clear visual indicators for safer copy mode (green) vs dangerous mirror mode (red)
  - "Last full backup" timestamp shown in menu (tracks FULL backups only, ignores TEST/DRY-RUN)

**Bug Fixes:**
- **Fixed Config Save Bug in Exclusion Management** - Saved to correct location
  - backup-exclusions.ps1 was creating duplicate config.json in module folder
  - line-counter-exclusions.ps1 used fragile relative path (`../../config.json`)
  - Both now use robust Split-Path pattern to find root config.json
  - Prevents duplicate config.json files in module directories

- **Fixed Robocopy Exclusion Flag Spacing** - Critical syntax error
  - `/XJ$exclusions` (no space) → `/XJ $exclusions` (with space)
  - `/XJ` is standalone flag, needs space before exclusion flags
  - Prevents command syntax errors

**UI/UX Improvements:**
- Removed unnecessary horizontal separator bars from Code Count and Backup Dev menus
- Cleaner menu appearance, consistent with rest of application

**Documentation:**
- **backup-dev README.md** - Complete rewrite with accurate information
  - Removed false claim about .gitignore pattern support
  - Documented actual exclusion system (robocopy `/XD` and `/XF` flags)
  - Added comprehensive configuration examples
  - Added safety notes about mirror mode
  - Documented how exclusions work (name-based matching, wildcards)

- **ARCHITECTURE.md** - Updated for count-lines.py relocation
  - Updated all path references to new location
  - Documented config path resolution approach

**Backward Compatibility:**
- No breaking changes - exclusion system gracefully handles configs without `backupDev` section
- Displays warning and uses junction point exclusions only (`/XJ`) when `backupDev` missing
- Existing backups continue to work without modification

### v1.13.3 (2025-12-04)

**Config Changes Required:**
- Added `.zip`, `.csv`, `.conf` to `lineCounter.globalExclusions.extensions`
- Added `backup` to `lineCounter.globalExclusions.pathPatterns`
- Config version: `config.10` → `config.11`

**New Features:**
- **Interactive Exclusion Management for count-lines** - Manage exclusions without editing JSON
  - `--show-exclusions` - Display current global and project-specific exclusions
  - `--manage` - Interactive menu for managing exclusions
  - `--add-ext .ext` - Add global extension exclusion via CLI
  - `--add-pattern pattern` - Add global path pattern exclusion via CLI
  - `--remove-ext .ext` - Remove global extension exclusion via CLI
  - `--remove-pattern pattern` - Remove global path pattern exclusion via CLI
  - Multiple operations in single command: `count-lines.py --add-ext .zip --add-pattern backup`
  - Validation and normalization of extensions (auto-adds dot prefix)
  - Sorted output for consistent display

**Bug Fixes:**
- **Fixed count-lines Missing File Types** - Restored ignored file types that were lost
  - Added `.zip` files to global exclusions (archive files)
  - Added `.csv` files to global exclusions (data files)
  - Added `.conf` files to global exclusions (configuration files)
  - Added `backup` path pattern to global exclusions (backup directories)
  - Note: `.vhdx`, `.avhdx`, and `.vsix` were already present
  - These files are now excluded from line counts across all projects by default

### v1.13.2 (2025-12-03)

**Code Cleanup: Remove Dead Code & Simplify Package Manager Cleanup**

This release significantly reduces code complexity by removing unused functions and simplifying the package manager cleanup workflow.

**Code Cleanup:**
- **Removed 6 Orphaned Update Functions** - Eliminated unused package update functions (364 lines removed)
  - Removed `Update-Check` - Never called, duplicate functionality of Select-PackagesToUpdate
  - Removed `Update-All` - Never called, no menu integration
  - Removed `Update-Scoop` - Only called by removed Update-All
  - Removed `Update-npm` - Only called by removed Update-All
  - Removed `Update-Winget` - Never called anywhere
  - Removed `Update-Pip` - Only called by removed Update-All
  - All functionality consolidated in `Select-PackagesToUpdate` (Manage Updates menu)

**Bug Fixes:**
- **Fixed Scoop Cleanup** - Removed duplicate cache clear and fixed prompt flow
  - Cache clear now only runs when user explicitly confirms (y/N prompt)
  - Previously ran automatically then asked for confirmation (redundant)
  - Updated prompt: "Clear cache (removes cached installers)? (y/N)"
- **Fixed Update-All Parameter Bug** - Removed invalid `$SkipCleanup` parameter usage
  - Update-All was passing parameter to Update-Scoop which no longer accepted it
  - Would have caused error if Update-All was ever called (it wasn't)

**Simplification:**
- **Simplified Package Manager Cleanup** - Replaced complex background job logic with direct commands
  - Removed 60+ lines of background job polling and output parsing code
  - Scoop now displays native progress bars directly (cleaner, more informative)
  - Cache clear operations moved from update functions to cleanup menu
  - Cleanup operations now properly separated from update operations

**Technical Details:**
- Net code reduction: 364 lines removed (389 deletions, 25 additions)
- Functions kept: `Get-NpmInstallInfo`, `Get-InstalledPackages`, `Select-PackagesToUpdate`
- Package update workflow: All handled by `Select-PackagesToUpdate` (checkbox UI for all 4 managers)
- Cleanup workflow: Direct command execution in `Invoke-PackageManagerCleanup`

**Impact:**
- Simpler, more maintainable codebase
- Clearer separation between updates and cleanup operations
- Better UX with native progress displays
- No functionality lost - all features still available via Manage Updates menu

### v1.13.1 (2025-12-02)

**Bug Fix: Scoop Progress Bar Artifacts + Real-time Progress Display**

**Bug Fixes:**
- **Fixed Scoop Progress Bar Bleed** - Eliminated visual artifacts during package cleanup
  - Scoop's progress bars use direct console API calls that bypass PowerShell stream redirection
  - Changed `scoop cleanup` and `scoop cache rm` commands to run in background jobs
  - Background jobs completely isolate console output, preventing progress bars from appearing
  - Maintains clean UI during package manager cleanup operations

**Enhancements:**
- **Real-time Progress Feedback** - Display cleanup progress from background jobs
  - Polls job output every 100ms to capture Scoop's cleanup messages
  - Shows "• Removing [app] [version]" for each package being cleaned
  - Cache removal shows file count updates every 10 files removed
  - Provides user feedback without exposing progress bar artifacts
  - Clean, readable progress display using Gray text with bullet points

**Technical Details:**
- **Problem**: Scoop writes progress bars using `[Console]::Write()` or VT100 escape sequences
- **Why stream redirection failed**: `2>&1 | Out-Null` only captures PowerShell streams, not direct console writes
- **Solution**: `Start-Job { scoop cleanup * 2>&1 }` runs in separate process with isolated console
- **Progress capture**: `Receive-Job` polls output stream and parses "Removing" messages
- **Performance**: Negligible overhead (~1-2 seconds) for operations that already take 10+ seconds

### v1.13.0 (2025-12-01)

**Major Release: Checkbox UI Centralization and Smart npm Management**

This release focuses on code quality improvements, UI consistency, and intelligent package management.

**New Features:**
- **Enhanced Checkbox Selection UI** - Centralized and flexible checkbox function
  - New `Show-CheckboxSelection` parameters for maximum flexibility:
    - `$UseClearHost` - Choose between cursor positioning (efficient) or Clear-Host (simple) rendering
    - `$CustomKeyHandler` - Inject custom key handling logic via scriptblock
    - `$CustomInstructions` - Add custom instruction lines to the UI
    - `$AllowAllItemsSelection` - Control whether items marked as "Installed" can be selected
  - Comprehensive PowerShell help documentation with examples
  - Supports both rendering modes for different use cases
  - Update selection UI migrated to use centralized function (~60 lines of code eliminated)

- **Smart npm Version Management** - Intelligent detection of npm installation method
  - New `Get-NpmInstallInfo` helper function detects:
    - Whether npm is Scoop-managed (checks if path contains '\scoop\')
    - CLI version (`npm --version`) vs Global version (`npm list -g npm`)
    - Whether npm package updates should be managed or delegated to Scoop
  - **Automatic Filtering**: npm package excluded from updates if Scoop-managed
    - Message displayed: "→ Skipping npm (managed by Scoop nodejs-lts)"
    - Prevents version conflicts when Scoop manages nodejs-lts package
    - Still shows npm if user explicitly installed global override
  - All other npm global packages remain unaffected (@anthropic-ai/claude-code, esbuild, etc.)

**UX Improvements:**
- **Lowercase Checkbox Indicators** - Changed `[X]` → `[x]` throughout for cleaner, more subtle appearance
  - Updated in 4 locations: Show-CheckboxSelection, Show-InlineBatchSelection, update UI, file browser
- **npm Cleanup Simplification** - Removed version check/update from cleanup function
  - Cleanup now only performs cache maintenance (clean + verify)
  - npm updates handled in proper update workflow (separation of concerns)
  - Removed "Update npm to latest? (Y/n)" prompt (~45 lines eliminated)
  - Removed note about Scoop managing npm version

**Bug Fixes:**
- **Checkbox Visual Artifacts** - Fixed issue where checkbox items appeared at top of screen during global package search
  - Separated initial draw logic for cursor positioning mode
  - Initial draw uses simple format, cursor positioning for updates
  - Prevents orphaned lines when console scrolls

**Code Quality:**
- **Reduced Duplication**: ~105 lines of duplicate/unnecessary code removed
- **Improved Maintainability**: Single source of truth for checkbox UI and npm detection
- **Better Documentation**: Comprehensive function documentation in ARCHITECTURE.md
- **Separation of Concerns**: Cleanup cleans, updates update, clear responsibilities

**Technical Details:**
- Console version: 1.12.0 → 1.13.0
- Config version: config.10 (no schema changes)
- New function: `Get-NpmInstallInfo` (lines 597-669)
- Enhanced function: `Show-CheckboxSelection` (lines 1276-1503)
- npm update check now uses smart filtering (lines 1002-1028)

**Files Changed:**
- `console.ps1`: Version update, Get-NpmInstallInfo function, enhanced Show-CheckboxSelection, npm filtering, checkbox indicators
- `ARCHITECTURE.md`: Updated version, documented enhanced functions with examples
- `CHANGELOG.md`: This entry

### v1.12.0 (2025-12-01)

**Major Release: UI Improvements and Standardization**

This release focuses on user experience improvements, standardization, and better backup tracking.

**New Features:**
- **About Menu** - Added comprehensive "About" menu accessible from Main Menu
  - Displays console version, config version, environment indicator
  - Shows repository link: https://github.com/Gronsten/powershell-console
  - Shows sponsor link: https://github.com/sponsors/Gronsten
  - Lists command-line options (--version, --help)
- **Smart Backup Tracking** - Backup timestamp now reads directly from backup-dev.log
  - No separate tracking file needed
  - Only tracks FULL backups (ignores COUNT and TEST modes)
  - Shows "Last full backup: TIMESTAMP (X days/hours/minutes ago)" in Backup menu
- **Backup Mode Detection** - backup-dev.ps1 now explicitly logs mode (FULL/TEST/COUNT)
  - Log format: `=== Backup started: 2025-12-01 12:40:51 | Mode: FULL ===`
  - Enables reliable detection of backup type

**UX Improvements:**
- **Environment Indicator** - Hidden for regular users
  - Only shows `[DEV]` or `[PROD]` when in _dev or _prod directories
  - Regular users see no environment indicator (cleaner UI)
- **Shorter Terminal Tab Title** - "PowerShell Console" → "Console"
  - Fits better in terminal tabs
  - Still shows environment when applicable: "Console [DEV] v1.12.0"
- **Standardized Pause Commands** - All pause operations now use `Invoke-StandardPause`
  - Supports Enter, Esc, and Q keys (previously only "any key")
  - Updated in 8 menu actions across Main Menu and Package Manager
  - Better user control and consistency
- **Enhanced Meraki Backup Menu** - Clear description when launching Meraki backup tool

**Config Changes (config.10):**
- ❌ **Removed**: `backupLogFile` field (log path is now fixed in backup script)
- ✅ **Updated**: All menu actions from `pause` to `Invoke-StandardPause`
- ℹ️ **Version Format Change**: Config version changed from semantic versioning (1.9.0) to prefixed integer (config.10)
  - Eliminates confusion between console version (1.12.0) and config version (config.10)
  - Increment by 1 when schema changes (e.g., config.10 → config.11)

**Technical Details:**
- Console version: 1.11.1 → 1.12.0 (semantic versioning for releases)
- Config version: 1.9.0 → config.10 (new prefix format for schema versions)
- `Get-LastBackupTimestamp` now parses mode from log: `| Mode: FULL ===`
- backup-dev.ps1 writes mode to first line of log for reliable detection
- Environment detection returns empty string for regular users (not "UNKNOWN")

**Files Changed:**
- `console.ps1`: Version update, environment logic, About menu, backup timestamp function
- `config.example.json`: Removed `backupLogFile`, updated pause commands, new config version format
- `modules/backup-dev/backup-dev.ps1`: Added mode tracking to log output
- `ARCHITECTURE.md`: Updated all version references, documented new functions
- `CHANGELOG.md`: This entry

### v1.11.1 (2025-11-29)

**Bug Fixes: Package Manager UI Improvements**

Fixed display issues and added pagination support for better package manager usability.

**Bug Fixes:**
- **Fixed Double Checkbox in Scoop Search** - Removed embedded `[ ]` from DisplayText property
  - Before: `> [ ] [ ] freebasic - 1.10.1 (main)`
  - After: `> [ ] freebasic - 1.10.1 (main)`
- **Fixed Line Clearing in Checkbox Selection** - Updated padding to always use full console width to prevent ghost characters

**Enhancements:**
- **Added Pagination to Winget Global Search** - Prevents results from running off screen
  - Batch size: 20 packages per page
  - Press M to fetch more batches
  - Shows "Showing X of Y | Selected: Z" progress
  - Selections preserved across all batches
  - Same UX pattern as npm search

**User Experience:**
- Consistent interaction pattern across all package managers (Scoop, npm, winget, pip)
- Better readability with clean checkbox display
- Manageable winget search results with pagination

### v1.11.0 (2025-11-29)

**Enhancement: Configuration-Driven Line Counter Exclusions**

Refactored line counter to use configuration-based exclusions instead of hardcoded rules, making it easier to customize which files/directories are excluded from counts.

**Config Changes Required:**
- **Updated configVersion to 1.9.0**
- Added new `lineCounter` section to config.json with the following structure:
  - `globalExclusions.extensions` - Array of file extensions to exclude everywhere (e.g., [".log", ".vsix", ".vhdx", ".avhdx"])
  - `globalExclusions.pathPatterns` - Array of path segments to exclude everywhere (case-insensitive)
  - `projectExclusions.<project-name>` - Project-specific exclusion rules:
    - `files` - Array of exact filenames to exclude
    - `filePatterns` - Array of filename patterns with wildcard support (e.g., "temp_*")
    - `extensions` - Array of file extensions to exclude for this project
    - `pathPatterns` - Array of path segments to exclude (case-insensitive)
    - `includeOnly` - Array of filenames to whitelist (excludes all others)
    - `excludeAll` - Boolean to exclude entire project from counts

**Enhancements:**
- **Configuration-Based Exclusions**: All exclusion rules now read from config.json instead of being hardcoded in count-lines.py
- **Flexible Pattern Matching**: Support for exact filenames, wildcards, extensions, and path patterns
- **Whitelist Mode**: Use `includeOnly` to selectively count specific files in a project
- **Per-Project Customization**: Each project under devRoot can have unique exclusion rules
- **Backward Compatible**: Fallback to default exclusions if lineCounter config is missing

**Migration Notes:**
- Existing hardcoded exclusions have been migrated to config.json
- To customize exclusions, edit config.json → lineCounter section
- See config.example.json for example configurations

**Technical Details:**
- Added `load_exclusion_config()` function to count-lines.py
- Refactored `should_exclude()` to accept config parameter
- Added `fnmatch` module for wildcard pattern matching
- Updated ARCHITECTURE.md with lineCounter config schema documentation

### v1.10.2 (2025-11-25)

**Enhancement: Version Display & Config Cleanup**

Improved version information display and cleaned up configuration template.

**Enhancements:**
- **Enhanced --version Switch**: Now displays both console version and config schema version
  - Added formatted output with aligned labels
  - Shows config version from config.json
  - Gracefully handles missing or malformed config files
  - Improved visual hierarchy with color-coded output

**Config Changes:**
- Updated configVersion to 1.8.1 in config.example.json
- Removed exampleaccount from active config.json (retained in config.example.json as template)
- Config schema unchanged - only template cleanup

**Example Output:**
```
[DEV] powershell-console
  Console version: 1.10.2
  Config version:  1.8.1
```

### v1.10.1 (2025-11-24)

**Bug Fixes: Package Manager Cleanup & Search**

Fixed two issues introduced in v1.10.0 package manager functionality:

**Bug Fixes:**
- **Scoop Cleanup Progress Bars**: Fixed scoop cleanup showing progress bar artifacts during execution
  - Changed from `2>&1 | Out-Null` to `$null = ... *>&1` for proper output suppression
  - Affects both `scoop cleanup` and `scoop cache rm` commands
  - Now shows clean "Cleaning up..." / "✅ Old versions cleaned" messages without visual artifacts

- **Winget Installed Package Search**: Fixed error when searching installed packages with no matches
  - Added handling for "No installed package found matching input criteria" message
  - Previously only checked for "No package found" which didn't match winget list output format
  - Now properly displays "No matches found" instead of showing parsing errors

**Technical Details:**
- Scoop commands now use PowerShell stream redirection `*>&1` to catch all output streams
- Winget search now checks for both global search ("No package found") and installed search ("No installed package found") error messages

### v1.10.0 (2025-11-20)

**New Feature: Package Manager Cleanup + Bug Fix: Winget Search Selectability**

Added comprehensive package manager cleanup functionality and fixed winget package selection bug.

**New Features:**
- **Package Manager Cleanup Menu**
  - New "Package Manager Cleanup" option in Package Manager menu
  - Comprehensive cleanup for Scoop, npm, pip, and winget package managers
  - Interactive prompts for destructive operations (cache clearing, etc.)

- **Scoop Cleanup**
  - `scoop checkup` - System health check
  - `scoop cleanup * --cache` - Remove old package versions and cache (with progress suppression)
  - Optional full cache wipe with confirmation prompt

- **npm Cleanup**
  - Version comparison display (Current vs Latest)
  - Optional npm self-update to latest version
  - `npm cache clean --force` - Clear npm cache
  - `npm cache verify` - Verify cache integrity

- **pip Cleanup**
  - Version comparison display (Current vs Latest via pip index)
  - Optional pip self-update to latest version
  - `pip cache purge` - Purge pip cache

- **winget Cleanup**
  - `winget source update` - Update winget source catalogs (with progress suppression)
  - Optional cache clearing with confirmation prompt
  - Note: Removed `winget validate` (requires manifest file, not applicable for general cleanup)

**Bug Fixes:**
- **Winget Search Selectability Issue**
  - Fixed bug where some winget packages weren't selectable in global search
  - Changed from whitespace-based parsing to header column position-based parsing
  - Handles dynamic column widths that vary based on search results
  - Resolves issue with searches like "grape" (narrow columns) vs "tweak" (wide columns)
  - Filters out progress indicators and footer lines from installed package list

- **Menu Configuration Merging**
  - Fixed issue where new menu items wouldn't appear if menu was previously customized
  - Menu loading now merges new default items into saved configurations
  - Ensures code updates automatically add new options to existing customized menus

**Technical Details:**
- New function: `Invoke-PackageManagerCleanup` in [console.ps1:2671-2838](console.ps1#L2671-L2838)
- Enhanced winget column-based parsing in [console.ps1:2390-2449](console.ps1#L2390-L2449)
- Improved menu merging in `Get-MenuFromConfig` [console.ps1:194-241](console.ps1#L194-L241)
- Enhanced winget installed package parsing in [console.ps1:1664-1688](console.ps1#L1664-L1688)
- Updated Package Manager menu in [console.ps1:2840-2859](console.ps1#L2840-L2859)

### v1.9.4 (2025-11-20)

**Documentation: Animated Demo GIF**

Added animated demo GIF to showcase console features and user interface.

**Documentation Updates:**
- **Demo GIF**
  - Added `assets/demo.gif` - Animated demonstration of console launch and usage
  - Shows terminal session starting with `pwsh console.ps1` command
  - Demonstrates console appearance and styling
  - Enhances README.md visual documentation

**Technical Details:**
- New file: [assets/demo.gif](assets/demo.gif)
- Referenced in [README.md:15](README.md#L15) Demo section
- GIF format for broad compatibility and GitHub rendering

### v1.9.3 (2025-11-19)

**Enhancement: Configurable VPN Output Path**

Added configurable path for VPN configuration output, replacing hardcoded script-relative directory.

**Config Changes Required:**
- Added `paths.vpnOutputPath` (string) - Directory for VPN configuration file output
- Example: `"vpnOutputPath": "C:\\path\\to\\vpn_output"`
- **Backward compatible** - Falls back to script directory if not configured

**Enhancements:**
- **VPN Output Directory**
  - VPN configurations now save to configurable path from `config.json`
  - Replaces hardcoded `$PSScriptRoot\vpn_output` with `paths.vpnOutputPath`
  - Maintains backward compatibility with fallback to script directory
  - Allows organizing VPN configs in user-preferred location

**Technical Details:**
- Updated `Get-VpnConnections` function in [console.ps1:6149-6160](console.ps1#L6149-L6160)
- Added `vpnOutputPath` to config schema in [config.example.json:12](config.example.json#L12)
- Checks for config property before using, gracefully falls back for existing configs

### v1.9.2 (2025-11-19)

**Bug Fix: Alohomora Non-RDP Window Launch**

Fixed Alohomora remote access to launch in a new window for non-RDP connections (SSH, HTTPS, etc.), matching the behavior of RDP connections.

**No Config Changes Required** - This release has no configuration changes.

**Bug Fixes:**
- **Alohomora Remote Access - Non-RDP Connections**
  - Fixed issue where answering 'n' to "Is this an RDP connection?" would launch Alohomora in the current console window (blocking the session)
  - Non-RDP connections now launch in a new PowerShell window, identical to RDP connection behavior
  - Added helpful connection banner showing browser URL (`https://localhost:<port>`) in the new window
  - Both connection types (RDP and non-RDP) now provide consistent user experience

**Code Improvements:**
- **Refactored wrapper script generation** - Eliminated code duplication by creating `New-AlohaWrapperScript` helper function
- Both RDP and non-RDP paths now use shared wrapper script generation logic
- Cleaner, more maintainable code with proper PowerShell documentation

**Technical Details:**
- Added `New-AlohaWrapperScript` helper function in [console.ps1:5876-5940](console.ps1#L5876-L5940)
- Updated `Start-AlohaConnection` function in [console.ps1:5942-6031](console.ps1#L5942-L6031)
- Non-RDP path now uses `Start-Process` with wrapper script (same pattern as RDP path)
- Keeps tunnel window open with instructions, prevents accidental disconnection

### v1.9.1 (2025-11-17)

**GitHub Enhancements: Sponsor Links & Visual Improvements**

Enhanced GitHub repository presence with sponsor support and improved README presentation.

**No Config Changes Required** - This release has no configuration changes.

**New Features:**
- **GitHub Sponsors Integration**
  - Added `.github/FUNDING.yml` for automatic sponsor button on repo page
  - Added sponsor badge to README (social style badge at top)
  - Added sponsor link to `--help` output in console.ps1 (colored display)

- **README Visual Enhancements**
  - Added colorful GitHub alert callouts (TIP and NOTE boxes)
  - Highlights latest v1.9.0 features in blue TIP box
  - Explains DEV/PROD structure in gray NOTE box
  - Added Demo section with placeholder for future demo.gif

- **Assets Directory Structure**
  - Created `assets/` directory for demo GIF
  - Added instructional README for creating demo recordings

**Documentation:**
- Enhanced README presentation with modern GitHub markdown features
- Improved visibility of key project features and structure
- Added guidance for future demo content creation

### v1.9.0 (2025-11-17)

**Okta Sync Enhancements: Auto-Discovery & Intelligent Updates**

Major enhancements to the AWS account sync function with automatic IAM role session duration discovery, comprehensive okta.yaml management, and duplicate prevention.

**No Config Changes Required** - This release is fully backward compatible.

**New Features:**
- **Automatic Session Duration Discovery** (Step 3.5)
  - Queries `aws iam get-role` for each discovered role's MaxSessionDuration
  - Uses actual IAM configuration instead of hardcoded 3600 (1 hour)
  - Typically discovers 12h for Admin roles, 4h for devops roles
  - Graceful fallback to 1h if query fails or permissions denied
  - Updates both okta.yaml profiles and config.json sessionDuration
  - Output shows discovered durations: "Admin in exampleaccount... 12h (43200 seconds)"

- **Comprehensive okta.yaml Management** (Enhanced Step 6)
  - Step 6a: Automatically adds missing IDP mappings (account ID → friendly name)
  - Step 6b: Automatically adds missing role ARNs with normalized display names
  - Step 6c: Adds new profiles AND updates existing profiles with new session durations
  - All three sections (idps, roles, profiles) now kept in sync automatically
  - Eliminates all manual okta.yaml editing

- **Profile Update Detection**
  - Sync now updates existing profiles when session duration changes
  - Detects IAM configuration changes and auto-updates okta.yaml
  - Output shows updates: "Updated profile: <name> session duration: 3600s → 43200s"
  - Prevents stale session duration values

- **Duplicate Prevention Fix**
  - Fixed critical regex bug that caused duplicate profile entries
  - Changed from `^\s+` to `(?m)^\s+` for multiline matching
  - Now correctly detects existing profiles before adding
  - Prevents okta.yaml bloat from repeated sync runs

**Enhanced Output:**
- Step 3.5 shows role duration discovery with human-readable times (12h, 4h, etc.)
- Step 6 separates IDP, roles, and profiles with clear section headers
- Summary shows counts: "Added X IDP mapping(s), Added Y role(s), Updated Z profile(s)"
- Color-coded updates (Green for adds, Cyan for updates)

**Technical Details:**
- Session duration discovery uses already-authenticated credentials from Step 2
- Per-role query (~100-300ms each, ~2-4 seconds total for typical setup)
- Multiline regex pattern with dotall mode for reliable profile updates
- Profile update pattern: `(?ms)(^\s+${profileName}:.*?aws-session-duration:\s*)(\d+)`
- RoleMaxDurations hashtable tracks discovered durations per account/role

**Bug Fixes:**
- Fixed duplicate profile creation (multiline regex)
- Fixed sync not updating existing profile session durations
- Fixed IDP and roles sections not being updated by sync

**Backward Compatibility:**
- Existing okta.yaml files work unchanged
- Sync will update profiles to discovered durations on next run
- Existing config.json sessionDuration values will be updated
- No breaking changes

**Files Changed:**
- `console.ps1` - Session duration discovery, comprehensive okta.yaml updates, duplicate fix

**Performance Impact:**
- Additional 2-4 seconds per sync for IAM role queries
- Acceptable trade-off for automatic optimal configuration

---

### v1.8.0 (2025-11-14)

**Pause Standardization & User Experience Enhancements**

Major refactoring of pause/break functions for consistent keyboard input handling across all menu actions, plus enhancements to count-lines.py and other user experience improvements.

**No Config Changes Required** - This release is fully backward compatible.

**New Features:**
- **Pause Standardization**: Complete refactoring for uniform Enter/Esc/Q behavior
  - New `Invoke-StandardPause` function with consistent keyboard handling
  - All 45 pause instances systematically replaced across console.ps1
  - Keyboard buffer clearing to prevent key interference
  - Added Esc support to ping function (previously Q-only)
  - Updated config.json menu actions (local only, gitignored)
  - Result: All pauses now respond uniformly to Enter, Esc, and Q keys
- **count-lines.py Inline Exclusions**: Redesigned output for better visibility
  - Shows excluded items inline with included items using color coding
  - White text: Included files, Gray text: Excluded files
  - New "Excluded" column with counts (e.g., "26(f), 1(d)")
  - Always-on visibility without CLI flags
  - Better integration with existing workflow
- **count-lines.py Single File Format**: Standardized table output
  - Single files now use same table structure as project folders
  - Consistent column headers (File, Files, Lines, Excluded, Status)
  - Professional formatting with totals section
- **IP Config Progress Spinner**: Added visual feedback during network gathering
  - Animated spinner with progress counter (e.g., "| Gathering network information (2/5)...")
  - Improves user experience during network adapter enumeration
  - Spinner clears before displaying results

**Bug Fixes:**
- **Start-MerakiBackup Path Resolution**: Now uses devRoot from config
  - Changed from hardcoded path derivation to config.paths.devRoot
  - Added fallback to parent directory for backward compatibility
  - Matches pattern used in Start-CodeCount function
  - Ensures consistent path resolution across all functions

**Code Cleanup:**
- Removed `MIGRATION-v1.7.0.md` (migration completed, info preserved in CHANGELOG)
- Removed `upgrade-prod.ps1` from `_dev` directory (exists in parent, not for distribution)
- Added `upgrade-prod.ps1` to `.gitignore` to prevent accidental commits

**Technical Details:**
- Fixed PowerShell parameter type issue: Changed `[switch]` to `[bool]` for proper default values
  - `[switch]` parameters don't properly support default `$true` values
  - `[bool]` parameters correctly support default values
- Updated 8 menu actions in config.json to use new pause function (Main Menu + Package Manager)

**Files Changed:**
- `console.ps1` - Pause refactoring, IP spinner, Meraki fix (+195, -140 lines)
- `scripts/count-lines.py` - Inline exclusions, single file format, _prod exclusion (+136, -105 lines)
- `.gitignore` - Added upgrade-prod.ps1 (+3 lines)
- `MIGRATION-v1.7.0.md` - Removed (-211 lines)
- `upgrade-prod.ps1` - Removed from _dev (-242 lines)

**Total:** 5 files changed, 255 insertions(+), 532 deletions(-)

**Net change:** -277 lines (significant cleanup + new standardization function)

---

### v1.7.0 (2025-11-13)

**DEV/PROD Environment Separation & Smart Config Merge**

Implemented a dual environment structure to separate active development from production usage, with intelligent config management.

**Config Changes Required:**
- Added `configVersion` (string) - Tracks config schema version for smart upgrade merging
  - Set to "1.7.0" for this release
  - Will be automatically managed by upgrade-prod.ps1 script
- Added `paths.devRoot` (string) - Absolute path to development root directory
  - Used by count-lines.py for project exclusion rules
  - Example: `"C:\\AppInstall\\dev"`

**New Features:**
- **DEV/PROD Separation**: Repository restructured for safe parallel development and production use
  - `_dev/` - Development environment with Git repository
  - `_prod/` - Production environment for daily use (stable releases only)
  - Separate config.json files for each environment
- **Environment Indicators**: Visual indicators to identify which environment you're running
  - Startup banner shows `[DEV]` (yellow), `[PROD]` (green), or `[UNKNOWN]` (red)
  - Window title displays environment: "PowerShell Console [DEV] v1.7.0"
  - Version flags (--version, -v) show environment indicator
- **Smart Config Merge**: Created `upgrade-prod.ps1` script with intelligent config management
  - Automatically merges new config fields from releases
  - Preserves all user values during upgrades
  - Detects and reports deprecated fields
  - Tracks schema versions with `configVersion` field
  - Alerts to CHANGELOG for manual review when needed
- **Config Versioning**: Added `configVersion` field to config.json schema
  - Enables automatic detection of config schema changes
  - Supports safe upgrades with schema migrations

**Bug Fixes:**
- **Code Count Fix**: Updated both count-lines.py and Start-CodeCount to read `devRoot` from config.json
  - count-lines.py: No longer relies on relative path navigation (parent.parent)
  - Start-CodeCount: Now reads paths.devRoot from config instead of calculating parent directory
  - Both use same config source for consistency
  - Explicitly configured in config.json paths.devRoot
  - Works correctly with new _dev directory structure

**Breaking Changes:**
- **Repository Structure**: Git repository moved to `_dev/` subdirectory
  - All Git operations must be run from `C:\AppInstall\dev\powershell-console\_dev`
  - Update any scripts/aliases that reference the old path
- **PowerShell Profile**: If using aws-prompt-indicator module, update Import-Module path:
  - Old: `C:\AppInstall\dev\powershell-console\modules\aws-prompt-indicator\...`
  - New: `C:\AppInstall\dev\powershell-console\_dev\modules\aws-prompt-indicator\...`

**Documentation:**
- Updated REPOS.md with new _dev path and DEV/PROD structure
- Updated CLAUDE.md with DEV/PROD workflow and config management process
- Added comprehensive upgrade script documentation

### v1.6.0 (2025-11-13)

**Package Manager Enhancement: Installed Package Visibility & Version Support**

Improved package search functionality to display already-installed packages and added command-line version support.

**New Features:**
- **Version Support**: Added command-line flags to display version information
  - `--version` - Display version number (double-dash)
  - `-Version` - Display version number (single-dash)
  - `-v` - Display version number (shorthand)
  - `--help` - Display help message (double-dash)
  - `-Help` - Display help message (single-dash)
  - `-h` - Display help message (shorthand)

**Bug Fixes:**
- **Installed Package Visibility**: Fixed package search to show already-installed packages
  - Installed packages now displayed in search results (shown in gray)
  - Installed packages marked with `[INSTALLED]` suffix
  - Installed packages are unselectable (cannot be selected with spacebar)
  - "Select All" (A key) only selects available (non-installed) packages
  - Clear messaging about installed vs. available package counts
  - Applies to all package managers: Scoop, npm, pip, winget

**Technical Improvements:**
- Updated `Show-CheckboxSelection` function to support disabled items
- Updated `Show-InlineBatchSelection` function to support disabled items
- Enhanced package result objects to include `Installed` property
- Improved user feedback with installed package counts

### v1.5.0 (2025-11-12)

**Package Manager Enhancement: Multi-Select Installation with Unified Installation Phase**

Added powerful multi-select capability to package search functionality, allowing users to select packages from multiple package managers and install them all at once in a unified installation phase.

**New Features:**
- **Multi-Select Installation**: After searching for packages globally, users can now:
  - Select multiple packages using checkbox UI (Space to toggle, Enter to confirm)
  - Select all packages with 'A' key
  - Deselect all with 'N' key
  - Cancel with 'Q' key
  - **Selections queued across all package managers** (no immediate installation)
  - Review complete installation summary before proceeding
  - Install all selected packages in a single unified installation phase

- **Supported Package Managers**:
  - ✅ **npm** - Search npm registry (3.6M+ packages) with progressive batch selection
  - ✅ **Scoop** - Search Scoop buckets and select packages
  - ✅ **PyPI** - Search PyPI (exact match + variations) and select packages
  - ✅ **winget** - Search winget packages and select packages (NEW!)

- **Unified Installation Workflow**:
  - All package managers complete their search and selection phases first
  - Installation summary shows all selections grouped by package manager
  - User confirms installation with Y/n prompt
  - All packages installed together in one batch
  - Installation results summarized with success/failure counts

- **Smart Filtering**: Only non-installed packages are offered for selection
  - Installed packages are highlighted in green during search
  - Installation prompt only appears if uninstalled packages were found

**User Experience:**
- Reuses existing checkbox selection pattern from package updates
- Consistent UI across all package managers
- Deferred installation allows selecting from multiple PMs before installing
- Clear visual feedback during installation with live status indicators
- Comprehensive success/error reporting for each package

**Benefits:**
- Save time by selecting packages from multiple package managers in one session
- Review all selections before any installation begins
- No need to re-run searches to install packages one by one
- Reduces manual typing of package names
- Consistent experience across npm, Scoop, PyPI, and winget
- Better error handling and reporting

**Example Workflow:**
```powershell
# Complete workflow (all package managers → unified installation)
1. Search: Enter "aws" → Select "Globally available"
2. npm: "Found 50 packages" → Select from batches (M for more, Enter when done)
   - Status: "✅ Added 3 npm package(s) to installation queue"
3. Scoop: "Found 5 packages" → Select packages
   - Status: "✅ Added 2 Scoop package(s) to installation queue"
4. PyPI: "Found 8 packages" → Select packages
   - Status: "✅ Added 1 pip package(s) to installation queue"
5. winget: "Found 12 packages" → Select packages
   - Status: "✅ Added 2 winget package(s) to installation queue"
6. INSTALLATION SUMMARY appears:
   Total: 8 package(s) selected

   NPM (3 package(s)):
     • aws-sdk (2.1450.0)
     • aws-cli (1.29.0)
     • @aws-cdk/core (2.100.0)

   SCOOP (2 package(s)):
     • aws
     • awscli

   PIP (1 package(s)):
     • awscli

   WINGET (2 package(s)):
     • Amazon.AWSCLI
     • Amazon.SAM-CLI

   Proceed with installation? (Y/n): Y

7. INSTALLING PACKAGES:
   Installing npm packages...
     → aws-sdk (2.1450.0)... ✅
     → aws-cli (1.29.0)... ✅
     → @aws-cdk/core (2.100.0)... ✅

   Installing Scoop packages...
     → aws... ✅
     → awscli... ✅

   Installing pip packages...
     → awscli... ✅

   Installing winget packages...
     → Amazon.AWSCLI... ✅
     → Amazon.SAM-CLI... ✅

8. INSTALLATION COMPLETE
   ✅ Successfully installed: 8
```

**Key Improvements:**
- 🎯 **Deferred installation** - Select from all PMs before any installation begins
- 📋 **Installation summary** - Review all selections grouped by PM before proceeding
- ⚡ **Unified installation** - All packages installed in one batch, grouped by PM
- 📦 **Persistent selections** - npm selections remembered across batches (M for more)
- 🔄 **Progressive loading** - npm: Press M to fetch more batches, Enter when done
- 📊 **Live status** - Real-time success/failure indicators during installation
- ✅ **Comprehensive reporting** - Success/failure counts and detailed error messages
- 🪟 **winget support** - Added multi-select capability for winget packages (NEW!)

### v1.4.0 (2025-11-12)

**Project Structure Improvements**

Reorganized project structure to improve modularity, maintainability, and clarity by consolidating utility scripts and modules into dedicated directories.

**Changes:**
- **Modularized backup-dev**: Moved `backup-dev.ps1` to `modules/backup-dev/` directory
  - Created `modules/backup-dev/README.md` with comprehensive documentation
  - Updated path references in `console.ps1` to use new module location
  - Log files now stored in module directory (`modules/backup-dev/backup-dev.log` and `modules/backup-dev/backup-history.log`)
  - Config file continues to be read from project root
  - **Simplified backup modes** by removing redundant list-only mode
    - Count mode provides fast summary statistics
    - Test mode provides limited preview with file-by-file details
    - List-only was duplicative and slow
  - Added `/XJ` flag to exclude junction points (fixes inflated counts in Scoop directories)
  - Enhanced count mode with inventory comparison (total items vs. items needing backup)
- **Moved count-lines to scripts**: Relocated `count-lines.py` to `scripts/` directory
  - Updated path reference in `console.ps1` to use new location
  - Aligns with existing pattern (e.g., `scripts/aws-logout.ps1` from v1.3.1)
- **Project Structure**: Improved organization following modular patterns
  - `modules/` - PowerShell modules with self-contained functionality
  - `scripts/` - Utility scripts called by console.ps1

**Migration Notes:**
- **Breaking change**: List-only mode has been removed from backup-dev
  - Use count mode (`--count`) for fast summary statistics
  - Use test mode (`--test-mode`) for limited preview with file details
- Paths are automatically resolved using `$PSScriptRoot`
- Config file remains in project root
- Backup logs now stored in `modules/backup-dev/` for better organization
- Users calling scripts directly should update paths:
  - Old: `.\count-lines.py` → New: `.\scripts\count-lines.py`
  - Old: `.\backup-dev.ps1` → New: `.\modules\backup-dev\backup-dev.ps1`

**Benefits:**
- Clearer project organization
- Easier to locate and maintain utility scripts
- Sets pattern for future modularization
- Follows established conventions from aws-prompt-indicator module (v1.3.0)

### v1.3.2 (2025-11-11)

**Main Script Renamed**

Renamed main script from `cmdprmpt.ps1` to `console.ps1` to better align with project name and improve clarity.

**Breaking Change:**
- Main script renamed: `cmdprmpt.ps1` → `console.ps1`
- New launch command: `.\console.ps1`

**Action Required for Users:**
- Update any shortcuts or scripts that reference `cmdprmpt.ps1`
- Update PowerShell profile functions if you've added custom launch functions
- Example profile function update:
  ```powershell
  function Start-AWSConsole {
      & "C:\path\to\powershell-console\console.ps1"
  }
  ```

**Files Changed:**
- Renamed: `cmdprmpt.ps1` → `console.ps1`
- Updated documentation: `README.md`, `SETUP.md`, `CHANGELOG.md`
- Updated examples: `config.example.json`
- Updated module documentation: `modules/aws-prompt-indicator/README.md`, `modules/aws-prompt-indicator/directory-mappings.example.json`

**Note**: This rename aligns with the v1.2.3 project rename from `powershell-aws-console` to `powershell-console`, completing the transition to the new project identity.

### v1.3.1 (2025-11-11)

**Performance Fix & New Utility**

Fixed performance issue with AWS Prompt Indicator and added AWS logout script.

**Changes:**
- **Performance Fix** (AWS Prompt Indicator):
  - Fixed 1-second prompt delay when AWS credentials are expired/logged out
  - Modified cache logic to cache both valid and null results
  - Changed line 137 in `Get-CurrentAwsAccountId` to remove `&& $null -ne $script:CachedAccountId` condition
  - Result: Fast prompts (<1ms) even when logged out, one-time delay (~1s) only on first prompt after logout
- **New Script**: `scripts/aws-logout.ps1`
  - Provides clean logout functionality for okta-aws-cli
  - Clears only `[default]` profile credentials from `~/.aws/credentials`
  - Preserves all other profiles
  - Creates automatic backup before modification
  - Error handling with backup restoration on failure
- **Visual Improvements** (AWS Prompt Indicator):
  - Match indicator: Bright green background (`#378504`) with Font Awesome checkmark ()
  - Mismatch indicator: Bright red background (`#c62828`) with warning emoji (⚠️)
  - Uses colors consistent with git status theme

**Files Changed:**
- `modules/aws-prompt-indicator/AwsPromptIndicator.psm1` (1 line fix)
- `modules/aws-prompt-indicator/quick-term-aws.omp.json` (color updates)
- `scripts/aws-logout.ps1` (new file, 86 lines)
- `scripts/README.md` (new documentation)
- `README.md` (updated features list)

### v1.3.0 (2025-11-10)

**New Feature - AWS Prompt Indicator Module (Optional)**

Added optional PowerShell module for displaying visual indicators in oh-my-posh prompts when your current directory's expected AWS account doesn't match your active AWS session.

**Features:**
- **Smart Session Display**: Shows AWS account friendly name in prompt instead of username
  - Falls back to username when not logged into AWS
  - Uses `displayName` from config.json environments
  - Provides at-a-glance awareness of current AWS context
- **Visual Match/Mismatch Indicators**:
  - Green checkmark (✔ AWS) when in correct account
  - Yellow warning (⚠️ AWS MISMATCH) when in wrong account
  - Indicators only appear in directories mapped to AWS accounts
  - Prevents accidental deployments to wrong environments
- **Directory-to-Account Mapping**: Configure which AWS accounts are expected for specific working directories
- **Automatic Detection**: Reads active AWS account from `~/.aws/credentials` (set by okta-aws-cli)
  - Smart caching with file change detection (<1ms typical, ~3ms on updates)
  - Hybrid detection: Fast file parsing + AWS CLI fallback for [default] profile
- **oh-my-posh Integration**: Pre-configured quick-term theme with AWS features
- **Simple Setup**: Two-line PowerShell profile integration via `Enable-AwsPromptIndicator`
- **Flexible Usage Options**:
  - oh-my-posh custom segment (recommended)
  - PowerShell profile function integration
  - Direct module function calls for custom implementations
- **Performance Optimized**: Smart caching, file change detection, minimal overhead
- **Comprehensive Documentation**: Dedicated README with setup instructions, examples, and troubleshooting

**Module Functions:**
- `Enable-AwsPromptIndicator`: ⭐ One-step integration for PowerShell profiles (recommended)
- `Initialize-AwsPromptIndicator`: Load configuration and directory mappings
- `Get-CurrentAwsAccountId`: Read active AWS account from credentials file (cached)
- `Get-ExpectedAwsAccountId`: Determine expected account for current directory
- `Test-AwsAccountMismatch`: Compare current and expected accounts
- `Get-AwsPromptIndicator`: Simple text indicator for custom prompts
- `Get-AwsPromptSegmentData`: JSON data for oh-my-posh segments

**Configuration:**
```json
{
  "awsPromptIndicator": {
    "directoryMappings": {
      "C:\\path\\to\\project-alpha": "123456789012",
      "C:\\path\\to\\project-beta": "210987654321"
    }
  }
}
```

**Files Added:**
- `modules/aws-prompt-indicator/AwsPromptIndicator.psm1` - Main PowerShell module (7 exported functions)
- `modules/aws-prompt-indicator/README.md` - Comprehensive module documentation
- `modules/aws-prompt-indicator/quick-term-aws.omp.json` - Pre-configured quick-term theme with AWS features
- `modules/aws-prompt-indicator/aws-prompt-theme.omp.json` - Example oh-my-posh theme template
- `modules/aws-prompt-indicator/directory-mappings.example.json` - Configuration example

**PowerShell Profile Integration (Two Lines):**
```powershell
Import-Module "C:\AppInstall\dev\powershell-console\modules\aws-prompt-indicator\AwsPromptIndicator.psm1" -Force -DisableNameChecking
Enable-AwsPromptIndicator -ConfigPath "C:\AppInstall\dev\powershell-console\config.json" -OhMyPoshTheme "C:\AppInstall\dev\powershell-console\modules\aws-prompt-indicator\quick-term-aws.omp.json" | Out-Null
```

**Environment Variables Set:**
- `$env:AWS_ACCOUNT_MATCH` - "true" when accounts match (enables green indicator)
- `$env:AWS_ACCOUNT_MISMATCH` - "true" when accounts don't match (enables yellow warning)
- `$env:AWS_DISPLAY_NAME` - AWS account friendly name or username (for session segment)

**Use Cases:**
- Prevent accidental deployments to wrong AWS account
- Always know which AWS account you're logged into at a glance
- Visual reminder when switching between multiple Terraform workspaces
- Safety guard for multi-account AWS infrastructure work
- Works seamlessly with okta-aws-cli authentication workflow

**Performance:**
- Module initialization: ~20ms (one-time on profile load)
- Cached account detection: <1ms (typical, 99% of prompts)
- File change detection: ~3ms (when credentials file updates)
- AWS CLI fallback: ~1500ms (one-time per authentication, then cached)

**Requirements (Optional):**
- oh-my-posh (for custom prompt theming)
- posh-git (optional, for git integration)
- okta-aws-cli (for AWS authentication)

See [modules/aws-prompt-indicator/README.md](modules/aws-prompt-indicator/README.md) for full setup instructions.

### v1.2.4 (2025-11-05)

**Bug Fixes - Path Resolution**

Fixed critical bugs introduced by project rename where several features were using hardcoded config paths instead of dynamic script location.

**Changes:**
- **Path Resolution Fix**: Replaced all instances of `$script:Config.paths.workingDirectory` with `$PSScriptRoot`
  - Automatically references script's actual location regardless of directory name
  - Eliminates dependency on config.json being updated after directory renames
  - More resilient to user configuration changes
- **Backup Dev Environment**: Fixed "backup-dev.ps1 not found" errors (all 4 backup options)
- **Code Count**: Fixed null reference error in `$devRoot` initialization
- **Meraki Backup**: Fixed path lookup to find meraki-api in parent directory (sibling project)
- **Meraki Backup Interactive Mode**: Added `-i` flag to prevent hanging when backing up all organizations
- **Command Prompt**: Fixed working directory path resolution

**Impact:**
- ✅ Backup Dev Environment fully functional
- ✅ Meraki Backup prompts for org/network selection
- ✅ Code Count navigation working correctly
- ✅ Command Prompt opens in correct directory

### v1.2.3 (2025-11-05)

**Project Rename & Bug Fixes**

**BREAKING CHANGE:** Project renamed from `powershell-aws-console` to `powershell-console` to better reflect its expanded functionality beyond AWS management (package managers, backups, utilities, etc.).

**Migration Notes:**
- GitHub repository: `Gronsten/powershell-aws-console` → `Gronsten/powershell-console` (old URLs automatically redirect)
- Local directory: Update your clone path from `powershell-aws-console` to `powershell-console`
- Git remote: Run `git remote set-url origin https://github.com/Gronsten/powershell-console.git`
- All internal functionality remains unchanged - no code changes required

**Bug Fixes - Package Search & Backup Progress**

Fixed two critical issues affecting package search and backup progress tracking.

**Changes:**
- **npm Package Name Search**: Replaced slow `npm search` command with local package database
  - **Complete Package Database**: Uses local copy of all 3.6M+ npm package names from [nice-registry/all-the-package-names](https://github.com/nice-registry/all-the-package-names)
  - **Package Name Only Search**: Searches only package names (not descriptions/metadata) for precise results
  - **Relevance Sorting**: Results sorted by length then alphabetically (shorter/exact matches appear first)
  - **Non-Scoped Priority**: Shows non-scoped packages before @-scoped packages for better visibility
  - **Total Match Count**: Displays total number of matching packages found
  - **Table Format Output**: Clean columnar display (NAME | VERSION | DESCRIPTION) with aligned columns
  - **Global Caching**: Loads package list once per session for instant subsequent searches (~2-3s first search, <0.5s after)
  - **Parallel API Fetching**: Package metadata retrieved concurrently using PowerShell runspaces for faster results (~0.9s vs 4+s sequential, 5x speedup)
  - **Paginated Results**: Shows 20 packages at a time with "Show more? (Y/n)" prompt (defaults to yes for easy browsing)
  - **Auto-Update Check**: Prompts to update package list if older than 24 hours with "Update now? (Y/n)" (defaults to yes)
  - **Auto-Download**: If package list missing, prompts to download with "Download now? (90MB) (Y/n)"
  - **Truncated Descriptions**: Descriptions limited to 60 characters for readability
  - Fast local search across entire npm registry
  - Shows [I] indicator for installed packages in green
  - Intelligent fallback to `npm search` command if download declined or fails
- **Backup Progress Fix**: Corrected Pass 2 progress meter calculation in `backup-dev.ps1`
  - Previously: Progress based on total source file volume (all files in source)
  - Now: Progress based on actual files to be copied (new, newer, and extra files only)
  - Provides accurate progress percentage during backup operations
  - Improved user experience with realistic completion estimates

**Technical Details:**
- npm package database: `resources/npm-packages.json` (90MB, 3.6M+ packages, updated from GitHub source)
- Search algorithm: Substring match with relevance sorting (length-first)
- Package metadata API: `https://registry.npmjs.org/<package-name>` for version/description
- Parallel execution: PowerShell runspaces (lightweight threads) instead of jobs (avoided ~3x performance penalty from job serialization overhead)
- Backup progress now uses robocopy summary columns: Copied + EXTRAS for both files and directories
- ~80 lines modified in main script, ~15 lines modified in `backup-dev.ps1`
- Added `resources/` directory with README for package list management

### v1.2.2 (2025-11-04)

**Package Manager - Enhanced PyPI Search & UX Improvements**

Significantly improved package search functionality with PyPI JSON API integration and better user feedback.

**Changes:**
- **PyPI JSON API Integration**: Replaced disabled `pip search` with PyPI's JSON API for accurate package information
- **Smart Package Discovery**: Automatically tries common variations (e.g., searching "cairo" finds "pycairo", "cairosvg", "python-cairo")
- **Package Details Display**: Shows package name, version, summary, and homepage from PyPI
- **Installation Status Indicators**: Displays [INSTALLED] tag in green for already-installed packages
- **Fixed Display Issue**: Removed spurious "Installed apps:" header from global search results
- **Progress Indicators**: Added "Loading installed packages... Scoop ✓ npm ✓ pip ✓ winget ✓" feedback during initialization
- **Performance Optimization**: Changed from `scoop list` to `scoop export` (JSON format, cleaner output)
- **Improved Messaging**: Clear explanations for PyPI search limitations and helpful suggestions

**Technical Details:**
- Uses `Invoke-RestMethod` to query `https://pypi.org/pypi/<package>/json` API endpoint
- Tries exact match first, then common naming variations for Python packages
- Properly handles API errors and provides fallback to installed package search
- ~100 lines modified in main script

### v1.2.1 (2025-11-01)

**Code Line Counter - Exclusion Rule Updates**

Updated exclusion rules in count-lines.py for better file filtering:

**Changes:**
- Moved `.vsix` exclusion from vscode-extensions project to global exclusions
- Added `.csv` exclusion for defender project
- Improved code organization with clearer section comments for global exclusions

### v1.2.0 (2025-11-01)

**Backup Dev Environment - Submenu and Improvements**

Added interactive submenu for backup operations with multiple modes and fixed test mode functionality:

**New Features:**
- Added backup submenu with four modes accessible from main menu:
  - List-Only Mode (Preview): Preview all changes without modifying files
  - Test Mode (Limited Preview): Preview limited operations with user-specified limit
  - Count Mode (Quantify Source): Count all files and directories, then exit
  - Full Backup: Create full backup with confirmation warning
- Interactive test mode now prompts for operation limit (default: 100)
- Improved user experience with safer preview options before destructive operations

**Bug Fixes:**
- Fixed Test Mode argument parsing that prevented it from working
- Refactored `Invoke-BackupScript` to accept string array instead of string
- Updated argument passing to use PowerShell splatting (`@Arguments`)
- Test mode now correctly passes `--test-mode` and limit as separate arguments

**Code Improvements:**
- Added `Get-BackupScriptPath` helper function for DRY principle
- Added `Invoke-BackupScript` helper function to centralize backup execution logic
- Created separate functions for each backup mode for better maintainability
- Improved error handling and user feedback

### v1.1.0 (2025-10-31)

**Backup Dev Environment - Major Enhancement**

Enhanced backup-dev.ps1 with advanced features and improved user experience:

**New Features:**
- GNU-style command-line arguments with full help system (`--help`, `--test-mode`, `--list-only`, `--count`)
- Test mode with configurable operation limits (default 100, minimum 100)
- List-only mode for dry-run previews without file modifications
- Count-only mode for quick file/directory statistics
- Two-pass operation: Pass 1 counts files, Pass 2 performs backup with accurate progress
- Visual progress indicators with animated spinner and percentage-based progress bar
- Real-time statistics display (directories, files, copied, extra)
- Dual logging system: detailed operation log + rotating summary history
- Smart log rotation (automatically keeps last 7 backup summaries)
- Runtime statistics and formatted completion reporting

**Improvements:**
- Removed OneDrive shutdown/restart functionality (no longer needed)
- Cleaned up unused variables for better code quality
- Added helper function `Write-Separator` for consistent visual formatting
- Enhanced robocopy integration with intelligent retry logic (/R:3 /W:5)
- Background job processing for responsive progress updates
- Improved error handling and graceful exits

**User Experience:**
- Progress updates every 500ms with spinner animation
- Clear mode indicators (TEST MODE, LIST-ONLY MODE, COUNT MODE)
- Comprehensive command-line help with usage examples
- Formatted output with color-coded messages (Cyan/Yellow/Green)
- Human-readable runtime display (mm:ss format)

**Configuration:**
- Paths configured via config.json (backupSource, backupDestination)
- Log files stored in script directory (backup-dev.log, backup-history.log)

### v1.0.0 (Initial Release)

Initial release with comprehensive AWS management console functionality.

---

## Development Utilities

### Backup Dev Environment Enhancements (v1.1.0)

See [Version History](#version-history) above for complete details of backup-dev.ps1 enhancements.

---

## Menu System Enhancements

### Menu Customization and Persistence

**Implemented Menu Customization Persistence** (Option 5 with Option 1)
- Store complete menu state in config.json, not deltas
- Auto-save changes after move/rename operations
- Menus stored as arrays of {text, action} objects

**Menu Structure**:
```json
{
  "menus": {
    "Main Menu": [
      { "text": "AWS Login", "action": "Start-AwsWorkflow" },
      { "text": "Ping Google", "action": "Start-InteractivePing..." }
    ]
  }
}
```

**Created Functions**:
- `Save-Menu` (lines 64-104): Saves entire menu state to config.json after changes
- `Get-MenuFromConfig` (lines 106-134): Loads menu from config or returns default

**Updated Functions**:
- `Show-ArrowMenu`: Auto-saves after Ctrl+Space move (line 1480) and Ctrl+R rename (line 1515)
- `Show-MainMenu`: Loads from config using Get-MenuFromConfig (line 1619)
- `Show-InstanceManagementMenu`: Loads from config using Get-MenuFromConfig (line 2859)
- `Show-PackageManagerMenu`: Loads from config using Get-MenuFromConfig (line 977)

**Menus with Persistence** (3 total):
1. Main Menu
2. Instance Management
3. Package Manager

**Benefits**:
- Simple - no complex overlay logic
- Complete menu state stored, easy to understand
- Auto-saves - user doesn't have to remember to save
- Backwards compatible - works with existing configs

### AWS Account Menu Persistence

**Implemented AWS Account Menu Persistence** (Option A - menuOrder approach)
- Store menu order as array in `awsAccountMenuOrder`
- Store custom names in `environment.customMenuNames`

**Created Helper Functions** (lines 136-271):
- `Get-AwsAccountMenuOrder`: Retrieves saved menu order array from config.json
- `Save-AwsAccountMenuOrder`: Saves menu order as array of "envKey:Role" strings
- `Save-AwsAccountCustomName`: Saves custom display names to environment.customMenuNames
- `Get-AwsAccountCustomName`: Retrieves custom display names for menu items

**Updated Show-AwsAccountMenu** (lines 2688-2838):
- Builds lookup hashtable of all account+role items from environments
- Checks for saved order and uses it if exists, otherwise alphabetical sort
- New items (not in saved order) are added at end alphabetically
- Custom display names override default "envKey (accountId) - Role: RoleName" format

**Updated Show-ArrowMenu Integration**:
- Ctrl+Space move (line 1641-1645): Detects AWS Account menu and calls Save-AwsAccountMenuOrder
- Ctrl+R rename (line 1681-1684): Detects AWS Account menu and calls Save-AwsAccountCustomName

**Data Structure in config.json**:
```json
{
  "awsAccountMenuOrder": [
    "exampleaccount1:Admin",
    "exampleaccount2:Admin",
    "exampleaccount3:Admin"
  ],
  "environments": {
    "exampleaccount1": {
      "customMenuNames": {
        "Admin": "Production Account - Admin Role",
        "default": "Production Account"
      }
    }
  }
}
```

**Benefits**:
- Menu order persists across script restarts
- Custom names persist across script restarts
- Order preserved during Sync - new accounts added at end
- Uses environment data as source of truth
- No duplicate data between environments and menus

### In-Menu Editing

**Added in-menu editing functionality** (lines 1359-1490)
- Integrated move and rename capabilities directly into Show-ArrowMenu
- Updated footer with emoji key indicators

**Implemented Ctrl+Space for move mode** (lines 1392-1459):
- Enters dedicated "MOVE MODE" with magenta highlighting
- Shows item being moved with "→ text ←" arrows in magenta
- Other items shown in dark gray for visual distinction
- Up/Down arrows swap item positions dynamically
- Enter confirms move, Escape cancels
- Selection cursor follows moved item automatically

**Implemented Ctrl+R for rename** (lines 1461-1487):
- Opens inline rename dialog showing current name
- Prompts for new name with option to cancel
- Updates menu item text immediately
- Works with both string and object menu items

**Changes apply immediately during session**
- All menus automatically support editing without code changes
- Removed standalone menu editor functions

### Menu Position Memory

**Implemented menu position memory** (Option 1 - Session-based)
- Added global hashtable `$global:MenuPositionMemory = @{}` (line 76)
- Created `Get-SavedMenuPosition` helper function (lines 950-971)
- Created `Save-MenuPosition` helper function (lines 973-997)
- Modified `Show-ArrowMenu` to restore last position (line 1007)
- Position saved when user selects with Enter (line 1056)
- Position NOT saved when going back with ESC/Q
- Memory persists for entire script session
- All menus automatically benefit with no changes required

### Menu Legend and Navigation

**Menu Legend Formatting Improvements** (lines 1526, 1593)
- Replaced emoji arrows with ASCII: `↑↓ navigate`
- Removed space between arrows
- Changed Ctrl indicators to lowercase: `⌃x exit`, `⌃r rename`
- Final format: `↑↓ navigate | ⏎ select | ⎋ back | ⌃x exit | ⌃␣ move | ⌃r rename`
- Move mode: `↑↓ move position | ⏎ confirm | ⎋ cancel`

**Enhanced navigation with ESC and Ctrl-X**:
- Added ESC key support to go back one level (line 1001-1003)
- Added Ctrl-X to exit script completely (lines 1007-1015)
- Updated instruction text
- Q key still works for backward compatibility
- Ctrl-X immediately exits with cleanup (Restore-ConsoleState)

**Fixed Q key navigation to go up only one menu level**:
- Removed explicit call to Show-AwsAccountMenu from Show-AwsActionMenu
- Changed to return instead of calling
- Modified Show-AwsAccountMenu to use continue instead of break
- Q properly navigates: AWS Actions → AWS Account Menu → Main Menu

---

## AWS Account Management

### Multi-Role Support

**Added multi-role support for AWS accounts**:
- Fixed role name case sensitivity (Admin with capital A, devops lowercase)
- Created separate Okta profiles for each role combination
- Added oktaProfileMap to config.json
- Added accountId, availableRoles, and preferredRole fields

**Created Functions**:
- `Select-AwsRole`: Present role selection menu when multiple roles available
- `Set-PreferredRole`: Store user's role preference in config.json

**Modified Start-AwsLoginForAccount**:
- Checks for multiple roles and prompts user to select
- Selected role maps to specific Okta profile
- Preferred role automatically pre-selected in menu
- Preference saved when user selects different role

### AWS Account Menu Redesign

**Redesigned AWS Account Menu to show Account+Role combinations**:
- Menu displays each account+role combination as separate item
- Format: "friendlyname (accountId) - Role: RoleName"
- Example: "exampleaccount (123456789012) - Role: Admin"
- Users select specific role from menu instead of prompt after selection
- Modified Start-AwsLoginForAccount to accept PreselectedRole parameter
- Accounts without roles show as: "friendlyname (accountId)"
- Menu items sorted alphabetically by account name
- Manual and Sync options appear at bottom
- Removed redundant "Re-run from Okta" action

### Account Synchronization

**Implemented and Fixed AWS Account Sync feature**:
- Added "Sync AWS Accounts from Okta" option to AWS account menu
- Created `Backup-ConfigFile` to backup config.json and okta.yaml
- Main `Sync-AwsAccountsFromOkta` runs okta-aws-cli with --all-profiles

**Sync Features**:
- ALWAYS uses 1-hour session duration to avoid re-authentication
- Parses okta-aws-cli output from "Updated profile" lines
- Extracts account names and roles from profile names
- Matches profile names to account IDs using okta.yaml IDP mappings
- Discovers all AWS accounts and roles from Okta in single authentication
- Converts friendly names to proper display names
- Renames accounts with wrong keys
- Checks for duplicate entries using normalized matching
- Merges duplicates, prefers entry matching Okta friendly name
- Updates config.json with newly discovered accounts
- Updates existing accounts with new roles
- Updates display names to match Okta during sync
- Creates placeholder entries for new accounts
- Sets sessionDuration="3600" for ALL synced accounts
- Uses sessionDuration from config when authenticating

**Created Functions**:
- `Update-ScriptConfiguration`: Reload config after changes
- `Get-OktaIdpMapping`: Extract friendly names from okta.yaml

**Account list automatically updated after sync**:
- Alphabetically sorted with Manual and Sync at bottom
- Returns to AWS account menu instead of main menu
- Preserves existing custom settings
- Shows summary of changes

**Updated Sync Function** (lines 2654-2665):
- Removes old deprecated menu data from config.json
- Preserves `awsAccountMenuOrder`
- New accounts/roles added at end of list
- User preference: keep custom order through Sync

**Step 6: Automatically creates missing profiles in okta.yaml**:
- Profiles created with correct account ID, role, and session duration
- All discovered profiles from okta-aws-cli added if missing

### AWS Context Display

**Added AWS Context Header to Instance Management Menu**:
- Displays current AWS account information at top
- Shows: `AWS Context: accountname (Account: 123456789012) - Region: us-east-1`
- Uses ANSI color codes (yellow) to match other displays
- Updates dynamically on each menu display
- Provides context awareness
- Implementation: Added HeaderLines parameter to Show-ArrowMenu (line 2832)

**Added account context display to instance tables**:
- Shows AWS account name, account ID, and region at top
- Format: "AWS Context: accountname (Account: 123456789012) - Region: us-east-1"
- Changed color to Yellow for visual consistency
- Removed blank line between context and table
- Shows whenever viewing EC2 instances
- Added to Get-Ec2InstanceInfo (line 2403)
- Added to Select-Ec2Instance (line 2560)

**Fixed instance selection menus to display context inline**:
- Modified Show-ArrowMenu to accept HeaderLines parameter (lines 948, 957-963)
- Header lines redisplayed on each menu redraw
- Updated Select-Ec2Instance to build header with context and legend (lines 2557-2581)
- Uses ANSI color codes for colored display
- Context and legend visible while navigating
- User can see AWS account context during instance selection

### Authentication Improvements

**Deprecated AWS Actions menu**:
- Goes directly to Instance Management after authentication (line 1249)
- Bypasses AWS Actions menu
- Changed prompt from "AWS Actions menu" to "Instance Management" (line 1217)
- Simpler navigation: Okta auth → Instance Management → ESC to select different account
- Functions still exist but not used in main flow

**Added 5 second auto-continue timer**:
- After authentication, automatically continues after 5 seconds (lines 1220-1246)
- Displays animated spinner: | / - \\ rotating every 100ms
- Shows countdown: "| Continuing in 5 seconds..."
- User can press any key to continue immediately
- Uses ANSI escape sequences to update in place
- Clears countdown line before proceeding
- Provides smooth UX with visual feedback

---

## Instance Management

### Instance Display Enhancements

**Enhanced instance display with visual markers**:
- Added markers to DescribeInstances table (lines 2489-2498):
  - `*  ` prefix for Default Instance (yellow)
  - `+  ` prefix for Default Host (cyan)
  - `*+ ` prefix for Both (yellow)
- Added legend: "Legend: * = Default Instance | + = Default Host | *+ = Both" (line 2502)
- Legend appears directly after table with no blank line
- Added blank line before pause (line 2509)

**Updated Legend and "Both" indicator**:
- Changed from "** = Both" to "*+ = Both" (lines 3005, 3134)
- Changed display marker from "** " to "*+ " (lines 2995, 3150)
- Consistent format across Get-RunningInstances and Select-Ec2Instance
- Changed "Default IP" to "Default Host" in legend (line 2621)

### Instance Configuration

**Replaced Set-DefaultRemoteIP with Set-DefaultRemoteHostInfo**:
- Uses Select-Ec2Instance for interactive selection
- Prompts for RemotePort and LocalPort
- Shows configuration summary before saving
- Saves all settings to config.json
- Updated Instance Management menu to call new function

**Added "None" option to EC2 instance selection**:
- Allows clearing instance and remote host configuration
- Both Set-DefaultInstanceId and Set-DefaultRemoteHostInfo support clearing
- Useful for accounts without Aloha

**Simplified Set-DefaultRemoteHostInfo**:
- Removed redundant "Step 2" prompt for Remote IP
- Automatically uses selected instance's Private IP address
- Renumbered steps accordingly
- Step 2 is now Remote Port, Step 3 is Local Port

**Fixed bug where Remote Host Instance ID overwriting Default Instance ID**:
- Created separate field instances.'remote-host' (lines 2782-2786)
- Default Instance ID remains in instances.'jump-box'
- Updated cache key to use "remote-host" (line 2812)
- Updated Show-CurrentInstanceSettings to display separately (lines 2842-2852)
- Shows "Instance ID" for default and "Remote Host Instance ID" under Remote Host Info
- Truly independent settings

**Added instance names/descriptions to Show-CurrentInstanceSettings**:
- Created `Get-InstanceNameById` helper to fetch Name tag (lines 2829-2858)
- Uses aws ec2 describe-instances with correct profile
- Display format: "i-xxxxx (Aloha)" (lines 2835-2845)
- Remote Host format: "i-xxxxx (Jump Box)" (lines 2860-2869)
- Shows only ID if Name tag unavailable

### Instance Selection Improvements

**Fixed Select-Ec2Instance menu display**:
- Removed New-MenuAction wrapper from instance menu items
- Changed to use simple string array for display
- Menu properly displays instance information
- Fixed issue with vertical character fragments

**Fixed single-instance parsing bug** (lines 2502-2523):
- When only one instance exists, JSON returns single array
- Added logic to detect single vs multiple instances
- Prevents foreach from iterating over property values

**Fixed Q key behavior in Set Default menus**:
- Modified Select-Ec2Instance to return @{ Cancelled = $true } (line 2616)
- Previously Q and "None" both returned null
- Updated Set-DefaultInstanceId to detect cancellation (lines 2635-2640)
- Updated Set-DefaultRemoteHostInfo to detect cancellation (lines 2701-2706)
- Pressing Q shows "Selection cancelled - no changes made"
- Settings remain unchanged when Q pressed vs "None"

**Changed default to "No" for clearing remote host settings**:
- Updated prompt from "(Y/n)" to "(y/N)" (line 2709)
- Changed logic to require explicit "y" to proceed (line 2710)
- Pressing Enter or other keys cancels operation
- Safer default prevents accidental deletion

### Configuration Management

**Cleaned up Show-CurrentInstanceSettings output**:
- Removed "Last Used Remote IP" line
- Removed "Last Used Ports" line
- Shows only Environment, Region, and Instance ID (lines 2804-2811)

**Enhanced Show-CurrentInstanceSettings to display Remote Host Info**:
- Added "Default Remote Host Info" section
- Displays Remote Host Instance ID, Remote IP, Remote Port, Local Port
- Shows "(not configured)" in gray if values not set
- Provides complete view of all settings

**Fixed bug where config changes not immediately visible**:
- Added Update-ScriptConfiguration call after saving in Set-DefaultInstanceId (line 2675)
- Added Update-ScriptConfiguration call in Set-DefaultRemoteHostInfo (line 2806)
- Configuration reloaded from file after changes
- Show-CurrentInstanceSettings displays newly saved values correctly

---

## Remote Access Features

### Aloha Remote Access

**Restored and enhanced Aloha Remote Access functionality**:
- Created `Start-AlohaRemoteAccess` function (lines 2753-2874)
- Added "Aloha Remote Access" to Instance Management menu (line 2870)
- Displays current instance settings matching View Current Instance Settings
- Shows Default Instance ID with name (e.g., "i-xxxxx (Aloha)")
- Shows Remote Host configuration
- Prompts to use current settings or modify (Y/n/m)
- Auto-launches Set-DefaultRemoteHostInfo if settings incomplete
- Restarts itself after configuration to show updated settings
- Changed RDP prompt default to "Y" (Y/n instead of y/N)

**Fixed AWS profile parameter in Start-AlohaConnection** (line 3494):
- Changed from $global:currentAwsEnvironment to $global:currentAwsProfile
- Uses correct AWS CLI profile name for authentication

**Fixed Oh-My-Posh initialization error** (line 3536):
- Added -NoProfile flag to PowerShell launch
- Avoids profile conflicts

**Fixed Aloha command execution** (line 3536):
- Changed from single quotes to double quotes
- Proper variable expansion
- Command actually executes instead of literal "$Command"

**Fixed instance ID selection logic** (line 2863):
- Uses $defaultInstanceId for SSM connection (-i parameter)
- Uses $remoteIP from Remote Host config for port forwarding (-r parameter)
- Correct architecture: SSM into Aloha instance, forward to Jump Box IP

**RDP Manager Launcher Window Minimization** (line 3746):
- Changed `-WindowStyle Normal` to `-WindowStyle Minimized`
- Launcher window starts minimized instead of appearing in front
- Window accessible in taskbar for monitoring
- Cleaner user experience

### VPN Management

**Added "Get VPN Connections" to Instance Management menu**:
- Added menu item on line 2773
- Removed deprecated post-search menu flow
- Function pauses after results and returns to menu
- Cleaner flow: Search VPN → View Results → Press key → Back to menu

**Added AWS credential validation and profile support**:
- Validates credentials before executing VPN query
- Uses `$global:currentAwsProfile` for correct profile
- Shows friendly error if credentials expired
- Prevents cryptic AWS API errors

**Improved output formatting**:
- Changed from single-line to formatted table
- Format: NAME (40 chars) | VPN CONNECTION ID
- Shows total count of VPN connections
- Saved file includes header with search term and timestamp
- Example output with proper table formatting

**VPN Connections AWS CLI Command**:
- `aws ec2 describe-vpn-connections --profile {profile} --query 'VpnConnections[].{Name:Tags[?Key==\`Name\`].Value | [0],VpnConnectionId:VpnConnectionId}' --output text`
- Filters by user-provided search string
- Saves to `vpn_output/vpn_connections_{search}_{timestamp}.txt`
- Located in Get-VpnConnections function (around line 3511)

---

## Package Manager Integration

### Package Manager Enhancements

**Enhanced Package Manager functionality**:
- Added pause before winget list with default "Y" prompt (line 302)
- Allows leisurely review of Scoop and npm output
- Sorted winget list alphabetically by package name (lines 327-380)
- Parses output to separate header, data, and footer
- Maintains proper table formatting while displaying sorted results

**Added "Search Packages" menu option** (line 726):
- Created Search-Packages function (lines 639-809)
- Prompts for Installed vs Globally available search (default: Installed)
- Uses different commands for each scope
- Highlights installed packages in green when searching globally
- Excluded npm from all searches as requested
- Sorted all results alphabetically (Scoop and winget)
- Fixed Scoop results to exclude headers and separators
- Removed extra blank lines

### Scoop Status Parsing Fix

**Fixed Package Manager scoop status parsing** (lines 606-661):
- Fixed `scoop status` output parsing
- Root Cause: Parser looked for old format instead of table format
- Solution: Updated parser to recognize table format
- Removed output suppression from scoop update (line 611)
- Removed output suppression from scoop status (line 615)
- Parser correctly identifies packages needing updates
- Handles "Scoop is up to date" message
- Still detects packages below that need updating
- User can see all output on screen

**Fixed Manage Updates**:
- Runs "scoop update" first to update buckets
- Then runs "scoop status"
- Removed redundant bucket update option

---

## Network Utilities

### Network Configuration Display

**Show-NetworkConfiguration functionality**:
- Comprehensive display of network adapters
- Shows IPs, DNS, DHCP settings
- Sorted by status (Up first) and IP type (routable first)
- Color-coded output
- Adapter details include MAC, link speed
- System information with computer name and DNS domain

**Interactive Ping**:
- Continuous ping with real-time latency display
- Press Q to quit and return to menu
- Shows timestamp, IP, response time, TTL
- Error handling for timeouts

---

## User Experience Improvements

### Console Initialization

**Console encoding setup** (lines 7-18):
- Save original console state
- Set console encoding to UTF-8 for proper character rendering
- Set PowerShell output encoding
- Don't modify PSStyle.OutputRendering for Oh-My-Posh compatibility

**Restore-ConsoleState function** (lines 21-37):
- Restore original encoding settings
- Clear keyboard buffer
- Reset console cursor visibility
- Write newline for clean prompt rendering

### Timed Pause Enhancement

**Fixed Invoke-TimedPause countdown display** (lines 1232-1260):
- Eliminated duplicate lines during countdown
- Added $lastRemaining tracking
- Only updates when second changes
- Clears line properly before rewriting
- Prevents text overlap
- Countdown updates cleanly on single line

### Port Prompt Simplification

**Simplified port prompts** (lines 2791-2814):
- Remote Port: "Enter Remote Port [3389]"
- Local Port: "Enter Local Port [8388]"
- Clean, simple display of current value
- Removed verbose text
- Pressing Enter keeps current value
- Falls back to sensible defaults if no current value

---

## Bug Fixes

### AWS Profile Authentication

**Fixed AWS profile authentication issue** (CRITICAL BUG FIX):
- Root Cause: All accounts showed instances from wrong account
- Issue: Previously removed --profile flag incorrectly
- Reality: okta-aws-cli only sets environment variables in "exec" mode
- Solution: Store actual Okta profile name in $global:currentAwsProfile
- Modified Invoke-AwsAuthentication to accept ProfileName (line 1155, 1178)
- Modified Start-AwsLoginForAccount to extract and pass profile (lines 1297-1320)
- Updated Get-Ec2InstanceInfo to build --profile parameter (lines 2364-2386)
- Updated Get-Ec2InstancesData to build --profile parameter (lines 2447-2467)
- Updated credential validation to use correct profile
- Each AWS account now shows its own instances
- All AWS CLI commands use: --profile $global:currentAwsProfile
- Fixes issue where any account showed wrong account's instances

---

## Code Cleanup

### Major Cleanup

**MAJOR CLEANUP - Removed deprecated code and unused functions**:
- Backup Created: main script backup (20251018-060208)
- Lines Removed: 222 lines (3,812 → 3,590 lines = 5.8% reduction)
- Functions Removed: 8 functions (51 → 43 functions)

**Category 1 - Deprecated AWS Actions Menu System** (5 functions):
- Removed `New-StandardAwsActions` (lines 933-945)
- Removed `Get-EnvironmentActions` (lines 947-969)
- Removed `Get-ManualAwsActions` (lines 971-978)
- Removed `Show-AwsActionMenu` (lines 2629-2652)
- Removed `Get-AccountSpecificActions` (lines 2654-2656)
- Note: Already deprecated per TODO line 309

**Category 2 - Unused Box Menu System** (3 functions):
- Removed `Show-AlohaBoxMenu` (lines 2663-2688)
- Removed `Get-AccountSpecificBoxes` (lines 2690-2737)
- Removed `Start-CustomAlohaConnection` (lines 2798-2776)
- Note: Replaced by dynamic instance management

**Category 3 - Code Optimization** (1 function):
- Inlined `Get-InstanceConfigurations` into `Get-CurrentInstanceId`
- Function only had one caller
- Inlining improves code readability
- Removed function overhead and indirection

**Removed deprecated key-letter highlighting**:
- Simplified `New-MenuAction` to only accept Text and Action
- Updated all menu creation code throughout script

---

## Summary Statistics

- **Total Features Added**: 50+
- **Bug Fixes**: 15+
- **Code Improvements**: 20+
- **Lines of Code**: ~3,590 (after cleanup)
- **Total Functions**: 43
- **Menus with Persistence**: 4 (Main, Package Manager, Instance Management, AWS Account)
- **Package Managers Supported**: 3 (Scoop, npm, winget)
- **AWS Features**: Multi-account, multi-role, sync, SSM, VPN management
