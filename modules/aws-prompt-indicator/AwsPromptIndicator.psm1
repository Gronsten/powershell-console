# AwsPromptIndicator.psm1
# PowerShell module for AWS account mismatch detection in oh-my-posh prompts
# Part of powershell-console project

<#
.SYNOPSIS
    Detects AWS account mismatches between current directory and logged-in AWS account.

.DESCRIPTION
    This module provides functions to:
    - Read AWS credentials from ~/.aws/credentials
    - Extract current AWS account ID from IAM role ARN
    - Map current directory to expected AWS account
    - Provide oh-my-posh custom segment data for visual indicators

.NOTES
    Requirements:
    - oh-my-posh (for custom prompt segments)
    - posh-git (optional, for git integration)
    - okta-aws-cli (for AWS authentication)
    - AWS CLI v2
#>

# Module variables
$script:AwsCredentialsPath = "$env:USERPROFILE\.aws\credentials"
$script:ConfigPath = $null
$script:DirectoryMappings = @{}
$script:ProfileToAccountMap = @{}
$script:Config = $null
$script:CachedAccountId = $null
$script:CredentialsFileLastModified = $null

<#
.SYNOPSIS
    Initializes the AWS Prompt Indicator module with configuration.

.PARAMETER ConfigPath
    Path to the powershell-console config.json file.

.EXAMPLE
    Initialize-AwsPromptIndicator -ConfigPath "/root/AppInstall/dev/powershell-console/config.json"
#>
function Initialize-AwsPromptIndicator {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    if (-not (Test-Path $ConfigPath)) {
        Write-Warning "Config file not found: $ConfigPath"
        return $false
    }

    try {
        $script:ConfigPath = $ConfigPath
        $script:Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

        # Load directory mappings if they exist
        if ($script:Config.awsPromptIndicator -and $script:Config.awsPromptIndicator.directoryMappings) {
            $script:DirectoryMappings = @{}
            $script:Config.awsPromptIndicator.directoryMappings.PSObject.Properties | ForEach-Object {
                $script:DirectoryMappings[$_.Name] = $_.Value
            }
            Write-Verbose "Loaded $($script:DirectoryMappings.Count) directory mappings"
        }

        # Build profile name to account ID mapping from environments
        $script:ProfileToAccountMap = @{}
        if ($script:Config.environments) {
            $script:Config.environments.PSObject.Properties | ForEach-Object {
                $envName = $_.Name
                $envConfig = $_.Value

                if ($envConfig.accountId) {
                    # Map various profile name formats that okta-aws-cli might use
                    # Examples: "myproject-prod", "myprojectprod", "my-project-prod"
                    $script:ProfileToAccountMap[$envName] = $envConfig.accountId
                    $script:ProfileToAccountMap[$envName.Replace("-","")] = $envConfig.accountId

                    # Also try with dashes in different positions for compound names
                    if ($envName -match "^([a-z]+)([a-z]+)(.*)$") {
                        $prefix = $Matches[1]
                        $middle = $Matches[2]
                        $suffix = $Matches[3]
                        $altName = "$prefix-$middle$suffix"
                        $script:ProfileToAccountMap[$altName] = $envConfig.accountId
                    }
                }
            }
            Write-Verbose "Loaded $($script:ProfileToAccountMap.Count) profile-to-account mappings"
        }

        return $true
    }
    catch {
        Write-Warning "Failed to load config: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Reads the current AWS account ID from credentials file.

.DESCRIPTION
    Parses ~/.aws/credentials to find the most recently updated profile
    (determined by file modification time or most recent profile in file).
    Maps the profile name to account ID using the config.json environments.
    This is fast (no network calls) and works with okta-aws-cli profile naming.

.OUTPUTS
    String - The 12-digit AWS account ID, or $null if not found.

.EXAMPLE
    $accountId = Get-CurrentAwsAccountId
    # Returns: "123456789012"
#>
function Get-CurrentAwsAccountId {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not (Test-Path $script:AwsCredentialsPath)) {
        Write-Verbose "AWS credentials file not found: $script:AwsCredentialsPath"
        $script:CachedAccountId = $null
        $script:CredentialsFileLastModified = $null
        return $null
    }

    try {
        # Check if credentials file has been modified since last read
        $fileInfo = Get-Item $script:AwsCredentialsPath
        $currentLastModified = $fileInfo.LastWriteTime

        # Use cached value if file hasn't changed (cache both valid and null results)
        if ($script:CredentialsFileLastModified -eq $currentLastModified) {
            Write-Verbose "Using cached account ID: $script:CachedAccountId (file unchanged)"
            return $script:CachedAccountId
        }

        # File changed or first read - parse it
        Write-Verbose "Credentials file changed or first read - parsing..."
        $credContent = Get-Content $script:AwsCredentialsPath -Raw

        # Find all profile names in the credentials file
        $profiles = [regex]::Matches($credContent, '\[([^\]]+)\]') | ForEach-Object { $_.Groups[1].Value }

        if ($profiles.Count -eq 0) {
            Write-Verbose "No profiles found in credentials file"
            $script:CachedAccountId = $null
            $script:CredentialsFileLastModified = $currentLastModified
            return $null
        }

        # Prefer [default] profile if it exists (okta-aws-cli writes here)
        # Otherwise use the last profile in the file
        $activeProfile = if ($profiles -contains "default") {
            Write-Verbose "Using [default] profile (okta-aws-cli standard)"
            "default"
        } else {
            Write-Verbose "No [default] profile, using last profile in file"
            $profiles[-1]
        }
        Write-Verbose "Active profile from credentials file: $activeProfile"

        # Try to map profile name to account ID
        $accountId = $script:ProfileToAccountMap[$activeProfile]

        # If profile name doesn't map, try AWS CLI as fallback (e.g., for [default] profile)
        if (-not $accountId -and $activeProfile -eq "default") {
            Write-Verbose "Profile '$activeProfile' has no mapping, using AWS CLI fallback"
            try {
                $identityJson = aws sts get-caller-identity 2>$null
                if ($LASTEXITCODE -eq 0 -and $identityJson) {
                    $identity = $identityJson | ConvertFrom-Json
                    $accountId = $identity.Account
                    if ($accountId -match '^\d{12}$') {
                        Write-Verbose "Retrieved account from AWS CLI: $accountId"
                    }
                }
            }
            catch {
                Write-Verbose "AWS CLI fallback failed: $_"
            }
        }

        if ($accountId) {
            Write-Verbose "Final account ID: $accountId"
            $script:CachedAccountId = $accountId
            $script:CredentialsFileLastModified = $currentLastModified
            return $accountId
        }
        else {
            Write-Verbose "No account ID determined for profile: $activeProfile"
            $script:CachedAccountId = $null
            $script:CredentialsFileLastModified = $currentLastModified
            return $null
        }
    }
    catch {
        Write-Verbose "Error reading AWS credentials: $_"
        return $script:CachedAccountId  # Return cached value on error
    }
}

<#
.SYNOPSIS
    Gets the expected AWS account ID for the current directory.

.DESCRIPTION
    Checks if the current working directory (or any parent directory)
    is mapped to an AWS account in the configuration.

.OUTPUTS
    String - The expected 12-digit AWS account ID, or $null if no mapping found.

.EXAMPLE
    $expectedAccount = Get-ExpectedAwsAccountId
#>
function Get-ExpectedAwsAccountId {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $currentPath = Get-Location | Select-Object -ExpandProperty Path

    # Check exact match first
    if ($script:DirectoryMappings.ContainsKey($currentPath)) {
        Write-Verbose "Exact directory mapping found for: $currentPath"
        return $script:DirectoryMappings[$currentPath]
    }

    # Check if current path is under any mapped directory
    foreach ($mappedDir in $script:DirectoryMappings.Keys) {
        if ($currentPath -like "$mappedDir*") {
            Write-Verbose "Parent directory mapping found: $mappedDir"
            return $script:DirectoryMappings[$mappedDir]
        }
    }

    Write-Verbose "No directory mapping found for: $currentPath"
    return $null
}

<#
.SYNOPSIS
    Checks if there's an AWS account mismatch for the current directory.

.DESCRIPTION
    Compares the current AWS account (from credentials) with the expected
    account for the current directory. Returns detailed status information.

.OUTPUTS
    PSCustomObject with properties:
    - HasMismatch (bool): True if accounts don't match
    - CurrentAccount (string): Current AWS account ID
    - ExpectedAccount (string): Expected AWS account ID
    - CurrentDirectory (string): Current working directory
    - Message (string): Human-readable status message

.EXAMPLE
    $status = Test-AwsAccountMismatch
    if ($status.HasMismatch) {
        Write-Host "Warning: AWS account mismatch!" -ForegroundColor Yellow
    }
#>
function Test-AwsAccountMismatch {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $currentAccount = Get-CurrentAwsAccountId
    $expectedAccount = Get-ExpectedAwsAccountId
    $currentDir = Get-Location | Select-Object -ExpandProperty Path

    # Determine if there's a mismatch
    $hasMismatch = $false
    $message = "No AWS session active"

    if ($null -ne $currentAccount -and $null -ne $expectedAccount) {
        if ($currentAccount -ne $expectedAccount) {
            $hasMismatch = $true
            $message = "AWS account mismatch: logged into $currentAccount, expected $expectedAccount"
        }
        else {
            $message = "AWS account matches: $currentAccount"
        }
    }
    elseif ($null -ne $currentAccount -and $null -eq $expectedAccount) {
        $message = "AWS session active ($currentAccount), but no mapping for current directory"
    }
    elseif ($null -eq $currentAccount -and $null -ne $expectedAccount) {
        $message = "No AWS session, but directory expects account $expectedAccount"
    }

    return [PSCustomObject]@{
        HasMismatch      = $hasMismatch
        CurrentAccount   = $currentAccount
        ExpectedAccount  = $expectedAccount
        CurrentDirectory = $currentDir
        Message          = $message
    }
}

<#
.SYNOPSIS
    Gets AWS account mismatch data formatted for oh-my-posh custom segment.

.DESCRIPTION
    Returns a JSON string that can be used by oh-my-posh's custom segment
    type to display AWS account status in the prompt.

.OUTPUTS
    String - JSON formatted data for oh-my-posh

.EXAMPLE
    Get-AwsPromptSegmentData | Out-File -FilePath $env:TEMP\aws-prompt-data.json -Encoding UTF8
#>
function Get-AwsPromptSegmentData {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $status = Test-AwsAccountMismatch

    $data = @{
        hasMismatch     = $status.HasMismatch
        currentAccount  = $status.CurrentAccount
        expectedAccount = $status.ExpectedAccount
        message         = $status.Message
        icon            = if ($status.HasMismatch) { "⚠" } else { "✓" }
        color           = if ($status.HasMismatch) { "red" } else { "green" }
    }

    return $data | ConvertTo-Json -Compress
}

<#
.SYNOPSIS
    Gets a simple text indicator for AWS account status.

.DESCRIPTION
    Returns a formatted string that can be added to any prompt.
    Only shows output when there's a mismatch.

.PARAMETER AlwaysShow
    If specified, shows status even when accounts match.

.OUTPUTS
    String - Formatted status text

.EXAMPLE
    $indicator = Get-AwsPromptIndicator
    if ($indicator) { Write-Host $indicator -ForegroundColor Yellow }
#>
function Get-AwsPromptIndicator {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [switch]$AlwaysShow
    )

    $status = Test-AwsAccountMismatch

    if ($status.HasMismatch) {
        return "⚠️  AWS: $($status.CurrentAccount) (expected: $($status.ExpectedAccount))"
    }
    elseif ($AlwaysShow -and $null -ne $status.CurrentAccount) {
        return "✓ AWS: $($status.CurrentAccount)"
    }

    return ""
}

<#
.SYNOPSIS
    Enables AWS prompt indicator integration for PowerShell profiles.

.DESCRIPTION
    This function sets up the AWS prompt indicator for use in PowerShell profiles.
    It initializes the module, creates the update function, and sets up prompt wrapping
    for oh-my-posh integration.

.PARAMETER ConfigPath
    Path to the powershell-console config.json file.

.PARAMETER OhMyPoshTheme
    Optional path to oh-my-posh theme. If not provided, oh-my-posh initialization is skipped.

.EXAMPLE
    Enable-AwsPromptIndicator -ConfigPath "/root/AppInstall/dev/powershell-console/config.json" -OhMyPoshTheme "/root/AppInstall/dev/powershell-console/modules/aws-prompt-indicator/quick-term-aws.omp.json"

.EXAMPLE
    # Without oh-my-posh (if you initialize it separately)
    Enable-AwsPromptIndicator -ConfigPath "/root/AppInstall/dev/powershell-console/config.json"
#>
function Enable-AwsPromptIndicator {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,

        [Parameter(Mandatory = $false)]
        [string]$OhMyPoshTheme
    )

    try {
        # Initialize the module
        $initResult = Initialize-AwsPromptIndicator -ConfigPath $ConfigPath -ErrorAction Stop

        if ($initResult) {
            # Create the update function in global scope
            $global:AwsPromptIndicatorUpdateFunction = {
                $status = Test-AwsAccountMismatch
                $currentAccountId = Get-CurrentAwsAccountId
                $expectedAccountId = Get-ExpectedAwsAccountId

                # Set mismatch status for oh-my-posh theme
                # Only show indicators when in a mapped directory
                if ($expectedAccountId) {
                    if ($status.HasMismatch) {
                        $env:AWS_ACCOUNT_MISMATCH = "true"
                        $env:AWS_ACCOUNT_MATCH = "false"
                    } elseif ($currentAccountId) {
                        $env:AWS_ACCOUNT_MISMATCH = "false"
                        $env:AWS_ACCOUNT_MATCH = "true"
                    } else {
                        # In mapped directory but not logged into AWS
                        $env:AWS_ACCOUNT_MISMATCH = "false"
                        $env:AWS_ACCOUNT_MATCH = "false"
                    }
                } else {
                    # Not in a mapped directory - hide indicators
                    $env:AWS_ACCOUNT_MISMATCH = "false"
                    $env:AWS_ACCOUNT_MATCH = "false"
                }

                # Set display name for session segment (falls back to username if not logged into AWS)
                if ($currentAccountId) {
                    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

                    # Find friendly name from config environments
                    $friendlyName = $null
                    foreach ($env in $config.environments.PSObject.Properties) {
                        if ($env.Value.accountId -eq $currentAccountId) {
                            $friendlyName = if ($env.Value.displayName) { $env.Value.displayName } else { $env.Name }
                            break
                        }
                    }

                    $env:AWS_DISPLAY_NAME = if ($friendlyName) { $friendlyName } else { $currentAccountId }
                } else {
                    $env:AWS_DISPLAY_NAME = $env:USERNAME
                }
            }

            # Run initial update
            & $global:AwsPromptIndicatorUpdateFunction

            # Initialize oh-my-posh if theme provided
            if ($OhMyPoshTheme -and (Test-Path $OhMyPoshTheme)) {
                oh-my-posh init pwsh --config $OhMyPoshTheme | Invoke-Expression
            }

            # Wrap the prompt function to update AWS status
            $originalPrompt = $function:prompt
            $function:global:prompt = {
                # Update AWS status before rendering prompt
                & $global:AwsPromptIndicatorUpdateFunction

                # Call the original prompt
                & $originalPrompt
            }.GetNewClosure()

            Write-Host "✓ AWS Prompt Indicator enabled" -ForegroundColor Green
            return $true
        }
    }
    catch {
        Write-Warning "Failed to enable AWS Prompt Indicator: $_"
        # Set fallback
        $env:AWS_DISPLAY_NAME = $env:USERNAME
        return $false
    }
}

# Export module functions
Export-ModuleMember -Function @(
    'Initialize-AwsPromptIndicator',
    'Get-CurrentAwsAccountId',
    'Get-ExpectedAwsAccountId',
    'Test-AwsAccountMismatch',
    'Get-AwsPromptSegmentData',
    'Get-AwsPromptIndicator',
    'Enable-AwsPromptIndicator'
)
