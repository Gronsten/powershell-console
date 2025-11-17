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
  - Output shows discovered durations: "Admin in etsnettoolsprod... 12h (43200 seconds)"

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
