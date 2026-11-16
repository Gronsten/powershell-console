# PowerShell Console Scripts

Utility scripts for PowerShell console operations.

## Available Scripts

### Publish-ConfigExample.ps1

Publishes git-tracked `config.example.json` from gitignored `config.json` before a release commit.
Sanitization rules live in `config-publish.manifest.json`. Fails if employer paths, real AWS
account ids, or other forbidden patterns would leak into the example file.

```powershell
# From _dev/
pwsh -NoProfile -File .\scripts\Publish-ConfigExample.ps1
pwsh -NoProfile -File .\scripts\Publish-ConfigExample.ps1 -WhatIf
```

**Related:** `Prepare-ConsoleRelease.ps1` (publish + release checklist text).

### Prepare-ConsoleRelease.ps1

Runs `Publish-ConfigExample.ps1` and prints the version bump / CHANGELOG / PR reminders from
[ARCHITECTURE.md](../ARCHITECTURE.md).

### AwsCredentialProfile.ps1

Shared helpers (dot-sourced by `console.ps1`) that copy a named okta-aws-cli profile onto `[default]` so AWS CLI and OpenTofu work without `--profile`.

After a successful console login, `Sync-AwsDefaultProfileFrom` updates `[default]` and removes a stale `x_security_token_expires` when the named profile has none.

**Related tests:** `_test/Test-AwsCredentialProfile.ps1`

### aws-logout.ps1

Clears AWS credentials from the `[default]` profile in `~/.aws/credentials`.

**Purpose**: Provides a logout function for `okta-aws-cli`, which writes credentials to the `[default]` profile but doesn't provide a built-in logout mechanism.

**Features**:
- Safely clears only the `[default]` profile credentials
- Preserves all other profiles in the credentials file
- Creates automatic backup before modification
- Error handling with backup restoration on failure

**Usage**:
```powershell
.\scripts\aws-logout.ps1
```

**Output**:
```
Successfully logged out of AWS
  Cleared credentials from [default] profile
  Backup saved to: C:\Users\username\.aws\credentials.backup
```

**What it does**:
The script clears the following fields from the `[default]` profile:
- `aws_access_key_id`
- `aws_secret_access_key`
- `aws_session_token`

The profile structure remains intact with empty values:
```ini
[default]
aws_access_key_id     =
aws_secret_access_key =
aws_session_token     =
```

**Safety**:
- Creates a backup file (`credentials.backup`) before making changes
- Validates the credentials file exists before attempting changes
- Restores from backup if any errors occur during the operation
- Does not modify any other profiles in the credentials file

**Related**:
Works in conjunction with the [AWS Prompt Indicator](../modules/aws-prompt-indicator/README.md) module to provide visual feedback about AWS authentication status.
