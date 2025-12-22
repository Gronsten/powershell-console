# Backup-Dev Module

A PowerShell module for [powershell-console](../../README.md) that provides intelligent backup functionality for the dev directory with multiple operation modes.

## Features

- **Multiple Backup Modes**
  - Full backup (copy mode - safer, keeps old files by default)
  - Mirror mode (optional - exact mirror with deletions, use with caution)
  - Test mode (preview limited number of operations)
  - Count mode (count files and directories only)
- **Configurable Exclusions** - Exclude directories and files via config.json patterns
- **Progress Tracking** - Real-time progress indicators during operations
- **Fully Configurable** - All settings managed through config.json
- **Comprehensive Logging** - Detailed logs in backup-dev.log and rotating history in backup-history.log

## Requirements

- **PowerShell 5.1+** (Windows PowerShell or PowerShell Core)
- **Robocopy** (included with Windows)

## Configuration

Edit `config.json` in the powershell-console root directory. The configuration has two main sections:

### Basic Paths

```json
{
  "paths": {
    "backupSource": "C:\\AppInstall\\dev",
    "backupDestination": "OneDrive - Company\\DevBackups"
  }
}
```

### Exclusion Configuration

```json
{
  "backupDev": {
    "excludeDirectories": [
      "node_modules",
      ".git",
      "bin",
      "obj",
      ".vscode",
      "_prod"
    ],
    "excludeFiles": [
      "*.log",
      "*.tmp",
      "*.bak",
      "*.vhdx"
    ],
    "customExclusions": {
      "directories": ["my-custom-folder"],
      "files": ["*.custom"]
    },
    "mirrorMode": false
  }
}
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `excludeDirectories` | Array | See [config.example.json](../../config.example.json) | Directory names to exclude anywhere in the tree |
| `excludeFiles` | Array | See [config.example.json](../../config.example.json) | File patterns to exclude (supports wildcards like `*.log`) |
| `customExclusions.directories` | Array | `[]` | User-defined directory exclusions |
| `customExclusions.files` | Array | `[]` | User-defined file exclusions |
| `mirrorMode` | Boolean | `false` | **WARNING:** When `true`, uses `/MIR` which DELETES files in destination not in source |

**Safety Note:** Mirror mode is disabled by default. The safer `/E` (copy) mode is used instead, which preserves old files in the destination.

## Usage

### From console.ps1 Menu (Recommended)

The easiest way to use backup-dev is through the console.ps1 menu:

1. Run `console.ps1`
2. Select "Backup" from the menu
3. Choose your backup mode:
   - **Count Only** - Count files and directories
   - **Test Mode** - Preview limited operations (configurable limit, minimum 100)
   - **Full Backup** - Complete mirror with deletions

### Direct Script Usage

You can also call the script directly:

```powershell
# Count only
.\modules\backup-dev\backup-dev.ps1 --count

# Test mode with default limit (100 items)
.\modules\backup-dev\backup-dev.ps1 --test-mode

# Test mode with custom limit (minimum 100)
.\modules\backup-dev\backup-dev.ps1 --test-mode 250

# Full backup
.\modules\backup-dev\backup-dev.ps1

# Show help
.\modules\backup-dev\backup-dev.ps1 --help
```

## Command-Line Options

| Option | Description |
|--------|-------------|
| `--count` | Only count files and directories, then exit |
| `--test-mode [N]` | Quick test: preview limited to N operations (N >= 100, default: 100) |
| `--help` | Show help message |

**Note:** The `--count` option runs alone and ignores other switches.

## How It Works

### Backup Process

1. **Load Configuration** - Reads source/destination paths and exclusion rules from config.json
2. **Build Exclusion Flags** - Constructs robocopy `/XD` and `/XF` flags from config
3. **Pass 1: Count Files** - Scans source to determine total files/directories (with exclusions applied)
4. **Pass 2: Execute Backup** - Uses robocopy with progress tracking
5. **Log Results** - Records operations to backup-dev.log and backup-history.log (rotating last 7)

### Exclusion System

The backup uses robocopy's `/XD` (exclude directories) and `/XF` (exclude files) flags:

**Default Directory Exclusions** (from config.example.json):
- `node_modules`, `.git`, `bin`, `obj` - Development artifacts
- `.vscode`, `.idea`, `.vs` - IDE configuration
- `_prod`, `dist`, `build`, `.next` - Build outputs
- `__pycache__`, `.pytest_cache`, `coverage` - Python/test artifacts
- `.terraform`, `.gradle`, `target`, `vendor` - Language-specific

**Default File Exclusions** (from config.example.json):
- `*.log`, `*.tmp`, `*.bak` - Temporary files
- `*.vhdx`, `*.iso`, `*.vmdk` - Virtual machine images
- `*.pyc`, `*.class`, `*.jar` - Compiled artifacts
- `.DS_Store`, `Thumbs.db`, `desktop.ini` - System files

**How Exclusions Work:**
- Directory exclusions match by **name** anywhere in the tree
- File exclusions support **wildcards** (`*.ext`)
- Custom exclusions can be added via `customExclusions` section
- All exclusions combine (default + custom)

### Logging

Two log files are maintained:
- **backup-dev.log** - Current session log (detailed)
- **backup-history.log** - Historical log with timestamps (cumulative)

## Integration with console.ps1

The backup-dev module integrates with console.ps1 through helper functions:

- `Get-BackupScriptPath` - Locates the backup script
- `Invoke-BackupScript` - Executes backup with specified arguments
- `Start-BackupCountMode` - Runs count-only mode
- `Start-BackupTestMode` - Runs test mode with user-provided limit
- `Start-BackupDevEnvironment` - Runs full backup with confirmation

## Troubleshooting

### Script Not Found

If you see "backup-dev.ps1 not found", verify:
1. The script exists in `modules/backup-dev/backup-dev.ps1`
2. You're running from the correct directory

### Config File Not Found

If you see "Config file not found", verify:
1. `config.json` exists in the powershell-console root
2. The file contains valid JSON
3. Paths are specified with double backslashes (`\\`) on Windows

### Backup Not Working

1. **Check paths** in config.json are correct
2. **Verify permissions** to read source and write to destination
3. **Check disk space** on destination drive
4. **Review logs** in backup-dev.log for detailed error messages

## Examples

### Example: Count Mode

```powershell
PS C:\AppInstall\dev\powershell-console> .\modules\backup-dev\backup-dev.ps1 --count
COUNT MODE - Only scanning source files

Source Inventory vs. Changes
───────────────────────────────────────────
               Inventory   Need to Copy
───────────────────────────────────────────
  Directories:      1,234            45
  Files:          123,456         1,234
───────────────────────────────────────────
  Total:          124,690         1,279
───────────────────────────────────────────
```

### Example: Test Mode

```powershell
PS C:\AppInstall\dev\powershell-console> .\modules\backup-dev\backup-dev.ps1 --test-mode 250
Test mode will preview a limited number of operations.
Limit: 250 items

Processing first 250 items...
[Preview of operations...]
```

## Contributing

This module is part of the powershell-console project. See the main [CHANGELOG.md](../../CHANGELOG.md) for version history.

To report issues or suggest features:
1. Open an issue on the GitHub repository
2. Include your PowerShell version and OS details
3. Provide relevant log excerpts from backup-dev.log

## License

Same license as powershell-console. See main repository for details.
