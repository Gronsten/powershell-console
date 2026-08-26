# Setup and Configuration Guide

This guide will walk you through setting up the PowerShell AWS Management Console from scratch.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
3. [Configuration](#configuration)
4. [AWS and Okta Setup](#aws-and-okta-setup)
5. [First Run](#first-run)
6. [Advanced Configuration](#advanced-configuration)
7. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Software

1. **PowerShell**
   - Windows PowerShell 5.1+ (comes with Windows)
   - OR PowerShell 7+ (recommended) - [Download here](https://github.com/PowerShell/PowerShell/releases)

2. **AWS CLI v2**
   - Download: https://aws.amazon.com/cli/
   - Verify installation: `aws --version`
   - Should show version 2.x.x

3. **okta-aws-cli**
   - Installation: `scoop install okta-aws-cli` (if using Scoop)
   - OR download from: https://github.com/okta/okta-aws-cli
   - Verify: `okta-aws-cli --version`

4. **AWS Systems Manager Session Manager Plugin**
   - Download: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
   - Required for SSM connections and port forwarding
   - Verify: `session-manager-plugin --version`

### Optional Software

1. **Scoop** (Windows Package Manager)
   - Installation: https://scoop.sh/
   - Command: `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser; irm get.scoop.sh | iex`
   - Used for package management features

2. **npm** (Node Package Manager)
   - Comes with Node.js: https://nodejs.org/
   - Used for npm package management features

3. **winget** (Windows Package Manager)
   - Comes with Windows 11
   - Windows 10 users: Install from Microsoft Store ("App Installer")

4. **Cursor** (Optional, for viewing/editing config files)
   - Download: https://cursor.com/
   - Or Scoop: `scoop install cursor`
   - Used by Edit Configs, backup log viewers, and deprecated-file reports
   - The console runs `cursor <file> --classic` (PATH `cursor` CLI) so the dedicated IDE opens, not Cursor Agents
   - The `code` CLI is not used as a fallback (it is often VS Code, not Cursor)

---

## Installation

### 1. Clone the Repository

```powershell
# Navigate to your desired location
cd "C:\Users\YourUsername\Documents"

# Clone the repository
git clone https://github.com/yourusername/powershell-console.git

# Navigate into the directory
cd powershell-console
```

### 2. Create Configuration File

```powershell
# Copy the example config
Copy-Item config.example.json config.json
```

### 3. Verify Files

Ensure you have these files:
- `console.ps1` - Main script
- `config.json` - Your configuration (created above)
- `README.md` - Documentation
- `SETUP.md` - This file
- `CHANGELOG.md` - Change history
- `LICENSE` - License information

---

## Configuration

### Basic Configuration

Edit `config.json` with your preferred text editor:

```powershell
# Using Cursor
cursor config.json

# OR using Notepad
notepad config.json
```

### Required Path Configuration

Update the `paths` section:

```json
{
  "paths": {
    "workingDirectory": "C:\\Users\\YourUsername\\Documents\\powershell-console",
    "profilePath": "C:\\Users\\YourUsername\\Documents\\PowerShell\\Microsoft.PowerShell_profile.ps1",
    "oktaYamlPath": "C:\\Users\\YourUsername\\.okta\\okta.yaml",
    "rdcManagerPath": "C:\\path\\to\\RDCMan.exe",
    "linksPath": "C:\\Users\\YourUsername\\Favorites\\Links\\"
  }
}
```

**Path Descriptions**:
- `workingDirectory`: Location where you cloned this repository
- `profilePath`: Your PowerShell profile path (run `$PROFILE` in PowerShell to find it)
- `oktaYamlPath`: Location of your Okta configuration (will be created by okta-aws-cli)
- `rdcManagerPath`: Path to Remote Desktop Connection Manager (optional, for RDP features)
- `linksPath`: Windows Favorites/Links folder (optional)

### AWS Configuration

Update the `aws` section:

```json
{
  "aws": {
    "defaultRegion": "us-east-1",
    "fortiGateDeviceTypeId": "7125681a"
  }
}
```

- `defaultRegion`: Your primary AWS region
- `fortiGateDeviceTypeId`: FortiGate device type ID (optional, for specific use cases)

---

## AWS and Okta Setup

### 1. Configure Okta AWS CLI

Create the Okta configuration file at `~/.okta/okta.yaml`:

```yaml
# Example okta.yaml structure
okta:
  org-domain: your-org.okta.com
  auth-type: OAUTH2
  oidc-client-id: your-client-id

profiles:
  - name: account1-OKTA-PROD-Admin
    account: "123456789012"
    role: arn:aws:iam::123456789012:role/Admin

  - name: account1-OKTA-PROD-devops
    account: "123456789012"
    role: arn:aws:iam::123456789012:role/devops
```

**Getting your Okta configuration**:
1. Contact your Okta administrator for:
   - Org domain
   - OIDC Client ID
   - Available AWS accounts and roles
2. Or use the sync feature (see below)

### 2. Test Okta Authentication

```powershell
# Test authentication to a single profile
okta-aws-cli web --profile account1-OKTA-PROD-Admin

# If successful, you should be able to run AWS commands
aws sts get-caller-identity --profile account1-OKTA-PROD-Admin
```

### 3. Use Built-in Sync Feature

The easiest way to set up your AWS accounts:

1. Run the script: `.\console.ps1`
2. Select "AWS Login" from Main Menu
3. Select "Sync AWS Accounts from Okta"
4. Authenticate with Okta when prompted
5. All available accounts and roles will be discovered automatically
6. Configuration will be saved to `config.json`

**What Sync Does**:
- Discovers all AWS accounts you have access to
- Creates entries in `config.json` for each account+role combination
- Updates `okta.yaml` with missing profiles
- Creates backup of config files before making changes
- Displays summary of discovered/updated accounts

---

## First Run

### 1. Launch the Script

```powershell
.\console.ps1
```

You should see the Main Menu:

```
Main Menu
=========

> Ping Google
  IP Config
  AWS Login
  PowerShell Profile Edit
  Okta YAML Edit
  Package Manager

↑↓ navigate | ⏎ select | ⎋ back | ⌃x exit | ⌃␣ move | ⌃r rename
```

### 2. Test Basic Features

Try these features to verify everything works:

1. **Network Test**: Select "Ping Google" to verify network connectivity
2. **View Network Info**: Select "IP Config" to see your network configuration
3. **Package Manager**: If you have Scoop/npm/winget installed, test package listing

### 3. Configure AWS Access

1. Select "AWS Login"
2. If this is your first time:
   - Select "Sync AWS Accounts from Okta"
   - Authenticate with Okta in your browser
   - Wait for sync to complete
   - Your accounts will be listed
3. Select an AWS account from the menu
4. Authentication will complete
5. You'll be taken to Instance Management

### 4. Configure Instance Settings (if using AWS features)

From Instance Management menu:

1. **View Current Instance Settings**: See what's configured
2. **Set Default Instance ID**: Choose your jump box/bastion instance
3. **Set Default Remote Host Info**: Configure port forwarding settings
4. **List Running Instances**: Verify you can see EC2 instances

---

## Advanced Configuration

### Environment-Specific Settings

Each AWS account in `config.json` can have detailed configuration:

```json
{
  "environments": {
    "myaccount": {
      "displayName": "My Production Account",
      "accountId": "123456789012",
      "region": "us-east-1",
      "sessionDuration": "3600",
      "availableRoles": ["Admin", "devops"],
      "preferredRole": "Admin",
      "oktaProfileMap": {
        "Admin": "myaccount-OKTA-PROD-Admin",
        "devops": "myaccount-OKTA-PROD-devops"
      },
      "instances": {
        "jump-box": "i-0123456789abcdef0",
        "remote-host": "i-0fedcba9876543210"
      },
      "defaultRemoteIP": "10.0.1.10",
      "defaultRemotePort": "3389",
      "defaultLocalPort": "8388",
      "boxes": [],
      "actions": ["instanceManagement"]
    }
  }
}
```

**Field Descriptions**:
- `displayName`: Friendly name shown in menus
- `accountId`: AWS account ID (12 digits)
- `region`: AWS region for this account
- `sessionDuration`: AWS session duration in seconds (3600 = 1 hour)
- `availableRoles`: List of IAM roles you can assume
- `preferredRole`: Default role to use (remembered preference)
- `oktaProfileMap`: Maps role names to Okta profile names
- `instances.jump-box`: Instance ID for default jump box
- `instances.remote-host`: Instance ID for remote host (Aloha)
- `defaultRemoteIP`: IP address of remote host
- `defaultRemotePort`: Remote port (3389 for RDP, 443 for HTTPS)
- `defaultLocalPort`: Local port for port forwarding
- `boxes`: Custom connection configurations (advanced)
- `actions`: Available actions for this account

### Menu Customization

Menus are automatically saved when you customize them:

**To reorder menu items**:
1. Press `Ctrl+Space` to enter move mode
2. Use arrow keys to reposition
3. Press Enter to save

**To rename menu items**:
1. Press `Ctrl+R` on the item
2. Type new name
3. Press Enter to save

**To reset menus to defaults**:
- Delete the `"menus"` section from `config.json`
- Or delete specific menu entries

### AWS Account Menu Order

Customize the order of AWS accounts:

```json
{
  "awsAccountMenuOrder": [
    "prod-account:Admin",
    "dev-account:Admin",
    "test-account:devops"
  ]
}
```

Format: `"accountKey:RoleName"`

New accounts discovered via Sync are added at the end.

### Custom Account Display Names

Override account display names:

```json
{
  "environments": {
    "myaccount": {
      "customMenuNames": {
        "Admin": "My Custom Name - Admin",
        "devops": "My Custom Name - DevOps"
      }
    }
  }
}
```

---

## Troubleshooting

### "Command not found" errors

**Problem**: `aws`, `okta-aws-cli`, or `session-manager-plugin` not found

**Solution**:
1. Verify installation: Run the command with `--version`
2. Check PATH: Ensure installation directory is in your PATH
3. Restart PowerShell after installing software
4. For Scoop packages: Run `scoop reset *` to fix shims

### "RequestExpired" AWS errors

**Problem**: AWS credentials have expired

**Solution**:
1. From Instance Management menu, press ESC to go back
2. Select "Change AWS Account"
3. Re-authenticate to your account
4. Or select a different account

### Okta Authentication Fails

**Problem**: Browser doesn't open or authentication fails

**Solution**:
1. Verify `okta.yaml` exists and has correct configuration
2. Check Okta org domain is correct
3. Verify OIDC Client ID is valid
4. Ensure you have permission to access AWS via Okta
5. Try manual profile: `okta-aws-cli web --profile YourProfileName`

### Config Changes Don't Persist

**Problem**: Menu customizations or settings don't save

**Solution**:
1. Verify `config.json` is not read-only
2. Check file permissions (should be writable)
3. Ensure you have write access to the directory
4. Look for error messages when saving

### Instance List Shows Wrong Account

**Problem**: Selecting an account shows instances from different account

**Solution**:
1. Verify `oktaProfileMap` in `config.json` is correct
2. Profile names must exactly match profiles in `okta.yaml`
3. Re-run Sync to rebuild profile mappings
4. Try re-authenticating to the account

### Script Runs Slowly

**Problem**: Menus take long time to load

**Solution**:
1. Package manager checks can be slow - use "Manage Updates" instead of auto-check
2. AWS API calls may be slow - check network connectivity
3. Consider increasing session duration to reduce re-authentication
4. Large number of instances may slow listings

### UTF-8 Characters Display Incorrectly

**Problem**: Arrows, boxes, or special characters look wrong

**Solution**:
1. Ensure PowerShell console is set to UTF-8
2. Script handles this automatically, but if issues persist:
   ```powershell
   [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
   ```
3. Use Windows Terminal for better UTF-8 support
4. Avoid legacy console hosts (cmd.exe)

### Module Import Errors

**Problem**: Script fails to load or import errors

**Solution**:
1. Ensure PowerShell 5.1+ or PowerShell 7+
2. Check execution policy: `Get-ExecutionPolicy`
3. If Restricted, set to RemoteSigned:
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

---

## Additional Resources

### Useful Commands

**Check PowerShell version**:
```powershell
$PSVersionTable.PSVersion
```

**Find your profile path**:
```powershell
$PROFILE
```

**Test AWS credentials**:
```powershell
aws sts get-caller-identity --profile YourProfile
```

**List Okta profiles**:
```powershell
okta-aws-cli web --list-profiles
```

**Check installed package managers**:
```powershell
scoop --version
npm --version
winget --version
```

### Documentation Links

- [AWS CLI Documentation](https://docs.aws.amazon.com/cli/)
- [Okta AWS CLI GitHub](https://github.com/okta/okta-aws-cli)
- [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [PowerShell Documentation](https://docs.microsoft.com/en-us/powershell/)
- [Scoop Package Manager](https://scoop.sh/)

---

## Getting Help

If you encounter issues not covered here:

1. Check the [README.md](README.md) for feature documentation
2. Review [CHANGELOG.md](CHANGELOG.md) for known issues and fixes
3. Open an issue on GitHub with:
   - PowerShell version (`$PSVersionTable.PSVersion`)
   - Error messages (full text)
   - Steps to reproduce
   - Relevant config (redact sensitive data)

---

## Next Steps

After setup is complete:

1. Explore the Main Menu features
2. Customize menu order and names to your preference
3. Configure AWS instance settings for your accounts
4. Set up package managers if desired
5. Add custom menu items (see Advanced Configuration)
6. Consider adding the script to your PowerShell profile for quick access:
   ```powershell
   # Add to your PowerShell profile
   function Start-AWSConsole {
       & "C:\path\to\powershell-console\console.ps1"
   }
   Set-Alias awsc Start-AWSConsole
   ```

Enjoy using the PowerShell AWS Management Console!
