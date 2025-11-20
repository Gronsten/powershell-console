# AWS Prompt Indicator Module

An optional PowerShell module for [powershell-console](../../README.md) that displays visual indicators in your prompt when your current directory's expected AWS account doesn't match your active AWS session.

## Features

- **Smart Session Display** - Shows AWS account friendly name instead of username when logged in
  - Falls back to username when not in AWS context
  - Uses `displayName` from config.json environments
- **Visual Match/Mismatch Indicators**
  - Bright green checkmark ( AWS) when in correct account
  - Bright red warning (⚠️ AWS MISMATCH) when in wrong account
  - Indicators only appear in directories mapped to AWS accounts
- **Automatic Detection** - Reads active AWS account from `~/.aws/credentials`
- **Directory Mapping** - Configure which AWS accounts are expected for specific directories
- **oh-my-posh Integration** - Pre-configured themes with AWS indicators
- **Performance Optimized** - Smart caching (<1ms typical)
  - Caches both valid and null results
  - No slow prompts when logged out (fixed in v1.3.1)
  - One-time detection after credential changes
- **Simple Setup** - Two-line PowerShell profile integration
- **Graceful Fallback** - Works seamlessly when not logged into AWS
- **AWS Logout Integration** - Works with `aws-logout.ps1` script for clean session management

## Requirements

### Required
- **PowerShell 5.1+** (Windows PowerShell or PowerShell Core)
- **okta-aws-cli** - For AWS authentication via Okta
- **AWS CLI v2** - For AWS operations

### Recommended for Full Functionality
- **oh-my-posh** - For custom prompt theming with AWS account indicators
  - Install: `winget install JanDeDobbeleer.OhMyPosh` or `scoop install oh-my-posh`
  - Docs: https://ohmyposh.dev/
- **posh-git** - For enhanced git integration in prompts
  - Install: `Install-Module posh-git -Scope CurrentUser`
  - Docs: https://github.com/dahlbyk/posh-git

## Installation

This module is included with powershell-console. No separate installation required.

## Configuration

### 1. Enable the Feature

Edit `config.json` in the powershell-console root directory:

```json
{
  "awsPromptIndicator": {
    "directoryMappings": {
      "C:\\path\\to\\project-alpha": "123456789012",
      "C:\\path\\to\\project-beta": "210987654321",
      "C:\\path\\to\\terraform-shared": "123456789012"
    }
  }
}
```

### 2. Directory Mappings

Map your working directories to their expected AWS account IDs:

- **Key**: Full path to directory (use double backslashes on Windows)
- **Value**: 12-digit AWS account ID

The module will match the current directory or any parent directory in the tree.

**Example**: If you're in `C:\path\to\project-alpha\terraform\modules\vpc`, the module will match the `C:\path\to\project-alpha` mapping.

### 3. Finding AWS Account IDs

Account IDs are available in your `config.json` under the `environments` section:

```json
"acmeprod": {
  "accountId": "123456789012"
}
```

Or run this from the powershell-console menu:
```powershell
aws sts get-caller-identity
```

## Usage

### Recommended: PowerShell Profile Integration (Always Active)

The best way to use this module is to load it in your PowerShell profile so it's always available, not just when running console.ps1.

**Add to your `$PROFILE`** (typically `$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`):

```powershell
# AWS Prompt Indicator - Simple two-line integration
# Adjust paths to where you installed powershell-console
Import-Module "C:\path\to\powershell-console\modules\aws-prompt-indicator\AwsPromptIndicator.psm1" -Force -DisableNameChecking
Enable-AwsPromptIndicator -ConfigPath "C:\path\to\powershell-console\config.json" -OhMyPoshTheme "C:\path\to\powershell-console\modules\aws-prompt-indicator\quick-term-aws.omp.json" | Out-Null
```

**Example paths:**
- Regular installation: `C:\Tools\powershell-console\modules\...`
- Cloned from GitHub: `C:\Users\YourName\repos\powershell-console\modules\...`
- Repository maintainer (dev): `C:\AppInstall\dev\powershell-console\_dev\modules\...`

> **Note:** Replace `C:\path\to\powershell-console` with wherever you installed or cloned the repository.

That's it! The `Enable-AwsPromptIndicator` function handles everything:
- Initializes the module with your config
- Sets up environment variables for AWS account tracking
- Integrates with oh-my-posh theme (if provided)
- Wraps your prompt to update on every directory change
- Falls back gracefully if AWS credentials aren't available

**If you initialize oh-my-posh separately**, omit the `-OhMyPoshTheme` parameter:

```powershell
Import-Module "C:\AppInstall\dev\powershell-console\modules\aws-prompt-indicator\AwsPromptIndicator.psm1" -Force -DisableNameChecking
oh-my-posh init pwsh --config 'C:\your\theme.omp.json' | Invoke-Expression
Enable-AwsPromptIndicator -ConfigPath "C:\AppInstall\dev\powershell-console\config.json" | Out-Null
```

**Benefits of this approach:**
- ✅ Works in ALL PowerShell sessions (not just console.ps1)
- ✅ Updates automatically when you change directories
- ✅ Updates automatically when you authenticate to AWS
- ✅ Simple two-line setup - all logic contained in the module
- ✅ No need to restart PowerShell - just `. $PROFILE`

### Option 1: oh-my-posh Custom Segment

#### Quick Start with quick-term Theme

If you're using the `quick-term` theme, we've created a pre-configured version for you:

**File**: [quick-term-aws.omp.json](./quick-term-aws.omp.json)

This is your existing `quick-term` theme with enhanced AWS integration:

**Features**:
1. **Session Segment** - Displays AWS account friendly name when logged in, falls back to username when not
2. **AWS Status Indicator** - Shows match/mismatch status between execution time and clock

See the **PowerShell Profile Integration** section above for the recommended setup that includes both the module loading and theme configuration.

**What you'll see**:
- **No AWS session**: Shows your username (e.g., `john.doe`)
- **AWS match**: Shows AWS account name (e.g., `My Project Prod`) + green `✔ AWS` indicator
- **AWS mismatch**: Shows AWS account name + yellow `⚠️ AWS MISMATCH` indicator

#### Custom Theme Integration

For other oh-my-posh themes, add this segment to your theme's right-side prompt block:

**AWS Status Indicator** (shows green checkmark on match, yellow warning on mismatch):
```json
{
  "background": "#d7af00",
  "foreground": "#121318",
  "background_templates": [
    "{{ if eq .Env.AWS_ACCOUNT_MATCH \"true\" }}#378504{{ end }}"
  ],
  "invert_powerline": true,
  "style": "diamond",
  "leading_diamond": "\ue0b2",
  "template": "{{ if eq .Env.AWS_ACCOUNT_MISMATCH \"true\" }} \u26a0\ufe0f AWS MISMATCH {{ else if eq .Env.AWS_ACCOUNT_MATCH \"true\" }} \u2714 AWS {{ end }}",
  "type": "text"
}
```

**Session Segment** (replace your existing session segment to show AWS account name):
```json
{
  "background": "#e4e4e4",
  "foreground": "#4e4e4e",
  "style": "powerline",
  "powerline_symbol": "\ue0b0",
  "template": " {{ if .Env.AWS_DISPLAY_NAME }}{{ .Env.AWS_DISPLAY_NAME }}{{ else }}{{ .UserName }}{{ end }} ",
  "type": "session"
}
```

See [aws-prompt-theme.omp.json](./aws-prompt-theme.omp.json) for another example theme configuration.

### Option 2: Manual Check

Use the module functions directly in your PowerShell profile or scripts:

```powershell
# Import the module
Import-Module "C:\AppInstall\dev\powershell-console\modules\aws-prompt-indicator\AwsPromptIndicator.psm1"

# Initialize with config path
Initialize-AwsPromptIndicator -ConfigPath "C:\AppInstall\dev\powershell-console\config.json"

# Get current AWS account
$currentAccount = Get-CurrentAwsAccountId
Write-Host "Current AWS Account: $currentAccount"

# Check for mismatch
$status = Test-AwsAccountMismatch
if ($status.HasMismatch) {
    Write-Host "⚠️  WARNING: AWS account mismatch!" -ForegroundColor Yellow
    Write-Host "  Current:  $($status.CurrentAccount)" -ForegroundColor Red
    Write-Host "  Expected: $($status.ExpectedAccount)" -ForegroundColor Green
}

# Get simple indicator for custom prompt
$indicator = Get-AwsPromptIndicator
if ($indicator) {
    Write-Host $indicator -ForegroundColor Yellow
}
```

### Option 3: Simple Prompt Function

Add this to your PowerShell profile for a basic implementation:

```powershell
function prompt {
    # Your existing prompt code here...

    # Add AWS indicator
    Import-Module "C:\path\to\modules\aws-prompt-indicator\AwsPromptIndicator.psm1" -Force
    Initialize-AwsPromptIndicator -ConfigPath "C:\path\to\config.json"

    $awsIndicator = Get-AwsPromptIndicator
    if ($awsIndicator) {
        Write-Host $awsIndicator -ForegroundColor Yellow -NoNewline
        Write-Host " " -NoNewline
    }

    # Return prompt string
    return "> "
}
```

## Module Functions

### `Enable-AwsPromptIndicator` ⭐ Recommended
**Complete one-step integration for PowerShell profiles.**

Initializes the module, sets up environment variables, wraps the prompt function, and optionally integrates oh-my-posh. This is the simplest way to use the module.

**Parameters:**
- `-ConfigPath` (required): Path to config.json
- `-OhMyPoshTheme` (optional): Path to oh-my-posh theme (if omitted, oh-my-posh initialization is skipped)

**Returns:** Boolean - Success/failure

**Example:**
```powershell
Enable-AwsPromptIndicator -ConfigPath "C:\path\to\config.json" -OhMyPoshTheme "C:\path\to\theme.omp.json"
```

**What it does:**
- Loads configuration and directory mappings
- Creates environment variables (`AWS_ACCOUNT_MATCH`, `AWS_ACCOUNT_MISMATCH`, `AWS_DISPLAY_NAME`)
- Wraps prompt function to update on every render
- Integrates with oh-my-posh (if theme provided)
- Falls back to username when not logged into AWS

---

### `Initialize-AwsPromptIndicator`
**Low-level initialization function.** Use `Enable-AwsPromptIndicator` instead for profile integration.

Loads configuration and directory mappings.

**Parameters:**
- `-ConfigPath` (required): Path to config.json

**Returns:** Boolean - Success/failure

### `Get-CurrentAwsAccountId`
Reads the active AWS account from `~/.aws/credentials`.

**Returns:** String - 12-digit account ID or `$null`

**Performance:** <1ms (cached), ~3ms on credential file changes

### `Get-ExpectedAwsAccountId`
Gets the expected AWS account for the current directory.

**Returns:** String - 12-digit account ID or `$null`

### `Test-AwsAccountMismatch`
Compares current and expected accounts.

**Returns:** PSCustomObject with:
- `HasMismatch` (bool)
- `CurrentAccount` (string)
- `ExpectedAccount` (string)
- `CurrentDirectory` (string)
- `Message` (string)

### `Get-AwsPromptSegmentData`
Returns JSON data for oh-my-posh custom segments.

**Returns:** String (JSON)

### `Get-AwsPromptIndicator`
Gets a formatted text indicator.

**Parameters:**
- `-AlwaysShow` (switch): Show status even when accounts match

**Returns:** String - Formatted indicator text

## How It Works

### 1. AWS Account Detection

When you run `okta-aws-cli web`, it updates `~/.aws/credentials`:

```ini
[default]
aws_access_key_id = ASIA...
aws_secret_access_key = ...
aws_session_token = ...
```

The module parses this file and extracts the account ID from the IAM role ARN in the session metadata.

### 2. Directory Mapping

The module checks your current working directory against the configured mappings:

1. Exact path match
2. Parent directory match (traverses up the tree)

### 3. Comparison

If both current and expected accounts are found, the module compares them and shows an indicator if they don't match.

## Troubleshooting

### Indicator Not Showing

1. **Check if feature is enabled** in `config.json`:
   ```json
   "awsPromptIndicator": { "enabled": true }
   ```

2. **Verify directory mapping** exists for your current location

3. **Check AWS credentials file** exists:
   ```powershell
   Test-Path "$env:USERPROFILE\.aws\credentials"
   ```

4. **Verify you're logged in** to AWS:
   ```powershell
   aws sts get-caller-identity
   ```

### Wrong Account Detected

The module reads the `[default]` profile from `~/.aws/credentials`. If okta-aws-cli is writing to a different profile, you may need to adjust the module code or update your okta configuration.

### Performance Issues

The module reads from disk on each prompt render. If you experience slowness:

1. Use oh-my-posh's caching mechanisms
2. Add debouncing to only check every N seconds
3. Disable the feature when not needed

## Examples

### Example: Mismatch Warning

```
C:\path\to\project-alpha> # Logged into account 210987654321
⚠️  AWS: 210987654321 (expected: 123456789012)
```

### Example: Matching Accounts

```
C:\path\to\project-alpha> # Logged into account 123456789012
✓ AWS: 123456789012
```

### Example: No Mapping

```
C:\Users\username> # Logged into account 123456789012
# No indicator shown (directory not mapped)
```

## Contributing

This module is part of the powershell-console project. See the main [CHANGELOG.md](../../CHANGELOG.md) for version history.

To report issues or suggest features:
1. Open an issue on the GitHub repository
2. Include your oh-my-posh version and theme configuration
3. Provide example directory mappings and expected behavior

## License

Same license as powershell-console. See main repository for details.

## Credits

- **okta-aws-cli**: https://github.com/okta/okta-aws-cli
- **oh-my-posh**: https://ohmyposh.dev/
- **posh-git**: https://github.com/dahlbyk/posh-git
