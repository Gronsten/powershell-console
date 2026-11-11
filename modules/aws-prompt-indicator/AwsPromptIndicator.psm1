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
$script:CachedProfileKey = $null
$script:CachedStsValidatedUntil = $null
$script:AwsStsValidationCacheSeconds = 90
$script:ConsoleRoot = $null

<#
.SYNOPSIS
    Initializes the AWS Prompt Indicator module with configuration.

.PARAMETER ConfigPath
    Path to the powershell-console config.json file.

.EXAMPLE
    Initialize-AwsPromptIndicator -ConfigPath "/root/AppInstall/dev/powershell-console/config.json"
#>
function Set-AwsPromptIndicatorConfigDerivedState {
    $script:DirectoryMappings = @{}
    if ($script:Config.awsPromptIndicator -and $script:Config.awsPromptIndicator.directoryMappings) {
        $script:Config.awsPromptIndicator.directoryMappings.PSObject.Properties | ForEach-Object {
            $script:DirectoryMappings[$_.Name] = $_.Value
        }
        Write-Verbose "Loaded $($script:DirectoryMappings.Count) directory mappings"
    }

    $script:ProfileToAccountMap = @{}
    if ($script:Config.environments) {
        $script:Config.environments.PSObject.Properties | ForEach-Object {
            $envName = $_.Name
            $envConfig = $_.Value

            if ($envName -eq "manual") {
                return
            }

            if ($envConfig.accountId) {
                $script:ProfileToAccountMap[$envName] = $envConfig.accountId
                $script:ProfileToAccountMap[$envName.Replace("-", "")] = $envConfig.accountId

                if ($envName -match "^([a-z]+)([a-z]+)(.*)$") {
                    $prefix = $Matches[1]
                    $middle = $Matches[2]
                    $suffix = $Matches[3]
                    $altName = "$prefix-$middle$suffix"
                    $script:ProfileToAccountMap[$altName] = $envConfig.accountId
                }

                if ($envConfig.PSObject.Properties['oktaProfileMap'] -and $envConfig.oktaProfileMap) {
                    $envConfig.oktaProfileMap.PSObject.Properties | ForEach-Object {
                        if ($_.Value) {
                            $script:ProfileToAccountMap[$_.Value] = $envConfig.accountId
                        }
                    }
                }
            }
        }
        Write-Verbose "Loaded $($script:ProfileToAccountMap.Count) profile-to-account mappings"
    }
}

function Test-AwsPromptIndicatorTerraformInferenceEnabled {
    if (-not $script:Config.awsPromptIndicator) {
        return $true
    }

    if ($script:Config.awsPromptIndicator.PSObject.Properties['autoInferTerraformPaths']) {
        return [bool]$script:Config.awsPromptIndicator.autoInferTerraformPaths
    }

    return $true
}

function Get-ExpectedAwsAccountIdFromTerraformPath {
    param([string]$NormalizedPath)

    if (-not (Test-AwsPromptIndicatorTerraformInferenceEnabled)) {
        return $null
    }

    if (-not $script:Config -or -not $script:Config.environments) {
        return $null
    }

    $envEntries = @(
        $script:Config.environments.PSObject.Properties |
            Where-Object { $_.Name -ne "manual" -and $_.Value.accountId } |
            Sort-Object { $_.Name.Length } -Descending
    )

    foreach ($envProp in $envEntries) {
        $envKey = $envProp.Name
        $marker = "\terraform\$envKey"
        $pattern = '(?i)' + [regex]::Escape($marker) + '(\\|$)'
        if ($NormalizedPath -match $pattern) {
            Write-Verbose "Terraform path inference matched environment '$envKey'"
            return $envProp.Value.accountId
        }
    }

    return $null
}

function Update-AwsPromptIndicatorConfigFromFile {
    if (-not $script:ConfigPath -or -not (Test-Path $script:ConfigPath)) {
        return $false
    }

    try {
        $script:Config = Get-Content $script:ConfigPath -Raw | ConvertFrom-Json
        Set-AwsPromptIndicatorConfigDerivedState
        return $true
    }
    catch {
        Write-Verbose "Failed to reload config: $_"
        return $false
    }
}

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
        $script:ConsoleRoot = Split-Path -Parent $ConfigPath
        $env:AWS_PROMPT_CONFIG_PATH = $ConfigPath
        $null = Update-AwsPromptIndicatorConfigFromFile
        return $true
    }
    catch {
        Write-Warning "Failed to load config: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Returns $true when a credentials-file profile has a past x_security_token_expires value.
#>
function Reset-AwsPromptIndicatorCache {
    $script:CachedAccountId = $null
    $script:CredentialsFileLastModified = $null
    $script:CachedProfileKey = $null
    $script:CachedStsValidatedUntil = $null
}

function Test-AwsCredentialsProfileHasKeys {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CredentialsText,

        [Parameter(Mandatory = $true)]
        [string]$ProfileName
    )

    $pattern = "(?ms)^\[$([regex]::Escape($ProfileName))\](.*?)(?=^\[|\z)"
    $section = [regex]::Match($CredentialsText, $pattern)
    if (-not $section.Success) {
        return $false
    }

    $body = $section.Groups[1].Value
    foreach ($key in @('aws_access_key_id', 'aws_secret_access_key', 'aws_session_token')) {
        if ($body -notmatch "(?im)^\s*$([regex]::Escape($key))\s*=\s*(\S+)\s*$") {
            return $false
        }
    }

    return $true
}

function Get-AwsCliNativeExecutablePath {
    $commands = @(Get-Command aws.exe -All -ErrorAction SilentlyContinue | Where-Object {
            $_.CommandType -eq 'Application' -and $_.Path -notmatch '\\shims\\'
        })

    if ($commands.Count -gt 0) {
        return $commands[0].Path
    }

    $shim = Get-Command aws.exe -ErrorAction SilentlyContinue
    if ($shim) {
        return $shim.Path
    }

    return $null
}

function Test-AwsStsCallerIdentityForProfile {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileName
    )

    $awsExe = Get-AwsCliNativeExecutablePath
    if (-not $awsExe) {
        return $null
    }

    $stsArgs = @('sts', 'get-caller-identity', '--output', 'json')
    if ($ProfileName -ne 'default') {
        $stsArgs += @('--profile', $ProfileName)
    }

    try {
        $identityJson = & $awsExe @stsArgs 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $identityJson) {
            return $null
        }

        $identity = $identityJson | ConvertFrom-Json
        if ($identity.Account -match '^\d{12}$') {
            return $identity.Account
        }
    }
    catch {
        Write-Verbose "STS validation failed for profile '$ProfileName': $_"
    }

    return $null
}

function Clear-AwsPromptSessionState {
    [CmdletBinding()]
    param(
        [switch]$RefreshPrompt
    )

    Reset-AwsPromptIndicatorCache

    if (Test-Path -LiteralPath Env:AWS_PROFILE) {
        Remove-Item Env:AWS_PROFILE
    }

    $env:AWS_DISPLAY_NAME = $env:USERNAME
    $env:AWS_ACCOUNT_MISMATCH = 'false'
    $env:AWS_ACCOUNT_MATCH = 'false'

    if ($RefreshPrompt -and $global:AwsPromptIndicatorUpdateFunction) {
        & $global:AwsPromptIndicatorUpdateFunction
    }
}

function Test-AwsCredentialProfileHelpersAvailable {
    return [bool]$script:CredentialProfileHelpersLoaded
}

function Invoke-AwsConsoleLogout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$AwsArgumentList
    )

    $argumentList = @($AwsArgumentList)
    $explicitProfile = $null
    for ($i = 0; $i -lt $argumentList.Count; $i++) {
        if ($argumentList[$i] -eq '--profile' -and ($i + 1) -lt $argumentList.Count) {
            $explicitProfile = $argumentList[$i + 1]
            break
        }
    }

    $profilesToClear = @()
    if ($explicitProfile) {
        $profilesToClear += $explicitProfile
    }

    if (Test-AwsCredentialProfileHelpersAvailable) {
        try {
            $logoutResult = Invoke-AwsCredentialLogout -ProfileNames $profilesToClear -SkipCliLogout
            if ($logoutResult.ClearedFile) {
                Write-Host "Cleared AWS credentials for: $($logoutResult.ProfileNames -join ', ')" -ForegroundColor Green
            }
            else {
                Write-Host "No credential keys were cleared (profiles may already be empty)." -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "Could not clear credential file: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "Credential helper script not found; cleared prompt state only." -ForegroundColor Yellow
    }

    Clear-AwsPromptSessionState -RefreshPrompt
    Write-Host "Prompt AWS session indicator reset to default." -ForegroundColor Green
}

function Register-AwsCliLogoutWrapper {
    $nativeAws = Get-AwsCliNativeExecutablePath
    if (-not $nativeAws) {
        Write-Verbose "aws.exe not found; skipping logout wrapper registration"
        return
    }

    $moduleName = $MyInvocation.MyCommand.Module.Name
    $logoutCleanupCmd = Get-Command -Name Invoke-AwsConsoleLogout -Module $moduleName -ErrorAction Stop

    # Global handles survive in the global `aws` function (closures cannot call private module helpers).
    $global:AwsPromptIndicatorNativeCliPath = $nativeAws
    $global:AwsPromptIndicatorLogoutCommand = $logoutCleanupCmd

    $logoutWrapper = {
        param(
            [Parameter(ValueFromRemainingArguments = $true)]
            [object[]]$ArgumentList
        )

        $argsArray = @($ArgumentList)
        $nativeExe = $global:AwsPromptIndicatorNativeCliPath
        if (-not $nativeExe) {
            throw "aws.exe path missing. Re-run Enable-AwsPromptIndicator."
        }

        & $nativeExe @argsArray
        $exitCode = $LASTEXITCODE

        if ($argsArray.Count -ge 1 -and [string]$argsArray[0] -eq 'logout') {
            $cleanup = $global:AwsPromptIndicatorLogoutCommand
            if ($cleanup) {
                & $cleanup -AwsArgumentList $argsArray | Out-Null
            }
        }

        $global:LASTEXITCODE = $exitCode
    }

    Set-Item -Path function:global:aws -Value $logoutWrapper -Force
}

function Test-AwsCredentialsProfileExpired {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CredentialsText,

        [Parameter(Mandatory = $true)]
        [string]$ProfileName
    )

    $pattern = "(?ms)^\[$([regex]::Escape($ProfileName))\](.*?)(?=^\[|\z)"
    $section = [regex]::Match($CredentialsText, $pattern)
    if (-not $section.Success) {
        return $false
    }

    if ($section.Groups[1].Value -notmatch '(?im)^\s*x_security_token_expires\s*=\s*(.+?)\s*$') {
        return $false
    }

    $raw = $Matches[1].Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $false
    }

    try {
        $expires = [datetime]::Parse($raw, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal)
        return $expires.ToUniversalTime() -lt [datetime]::UtcNow
    }
    catch {
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
        $script:CachedProfileKey = $null
        return $null
    }

    try {
        # Check if credentials file has been modified since last read
        $fileInfo = Get-Item $script:AwsCredentialsPath
        $currentLastModified = $fileInfo.LastWriteTime
        $profileKey = [string]$env:AWS_PROFILE

        # Use cached value when file, profile, and recent STS validation are unchanged
        if ($script:CredentialsFileLastModified -eq $currentLastModified -and
            $script:CachedProfileKey -eq $profileKey -and
            $script:CachedStsValidatedUntil -and
            $script:CachedStsValidatedUntil -gt [datetime]::UtcNow) {
            Write-Verbose "Using cached account ID: $script:CachedAccountId"
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
            $script:CachedProfileKey = $profileKey
            return $null
        }

        # Prefer AWS_PROFILE when set (console login exports it). Otherwise use
        # [default] only if it is not marked expired. Stale [default] keys are
        # common because okta-aws-cli --profile writes a named section.
        $activeProfile = $null
        if ($env:AWS_PROFILE -and ($profiles -contains $env:AWS_PROFILE)) {
            Write-Verbose "Using AWS_PROFILE environment profile: $($env:AWS_PROFILE)"
            $activeProfile = $env:AWS_PROFILE
        }
        elseif ($profiles -contains "default") {
            $defaultExpired = Test-AwsCredentialsProfileExpired -CredentialsText $credContent -ProfileName "default"
            if (-not $defaultExpired) {
                Write-Verbose "Using [default] profile"
                $activeProfile = "default"
            }
            else {
                Write-Verbose "[default] profile is expired; not treating it as the active session"
            }
        }

        if (-not $activeProfile) {
            Write-Verbose "No usable active AWS profile"
            $script:CachedAccountId = $null
            $script:CredentialsFileLastModified = $currentLastModified
            $script:CachedProfileKey = $profileKey
            $script:CachedStsValidatedUntil = $null
            return $null
        }

        Write-Verbose "Active profile from credentials file: $activeProfile"

        $profileExpired = Test-AwsCredentialsProfileExpired -CredentialsText $credContent -ProfileName $activeProfile
        $hasKeys = Test-AwsCredentialsProfileHasKeys -CredentialsText $credContent -ProfileName $activeProfile
        if ($profileExpired -or -not $hasKeys) {
            Write-Verbose "Profile '$activeProfile' is expired or has no active credentials"
            $script:CachedAccountId = $null
            $script:CredentialsFileLastModified = $currentLastModified
            $script:CachedProfileKey = $profileKey
            $script:CachedStsValidatedUntil = $null
            return $null
        }

        $accountId = Test-AwsStsCallerIdentityForProfile -ProfileName $activeProfile
        if ($accountId) {
            Write-Verbose "Validated account ID via STS: $accountId"
            $script:CachedAccountId = $accountId
            $script:CredentialsFileLastModified = $currentLastModified
            $script:CachedProfileKey = $profileKey
            $script:CachedStsValidatedUntil = [datetime]::UtcNow.AddSeconds($script:AwsStsValidationCacheSeconds)
            return $accountId
        }

        Write-Verbose "No valid STS session for profile '$activeProfile'"
        $script:CachedAccountId = $null
        $script:CredentialsFileLastModified = $currentLastModified
        $script:CachedProfileKey = $profileKey
        $script:CachedStsValidatedUntil = [datetime]::UtcNow.AddSeconds(15)
        return $null
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

    $currentPath = (Get-Location | Select-Object -ExpandProperty Path).Replace('/', '\')

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

    $inferredAccount = Get-ExpectedAwsAccountIdFromTerraformPath -NormalizedPath $currentPath
    if ($inferredAccount) {
        Write-Verbose "Inferred expected account from terraform path: $inferredAccount"
        return $inferredAccount
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
        $script:ConsoleRoot = Split-Path -Parent $ConfigPath
        $initResult = Initialize-AwsPromptIndicator -ConfigPath $ConfigPath -ErrorAction Stop

        if ($initResult) {
            # Create the update function in global scope
            $global:AwsPromptIndicatorUpdateFunction = {
                $null = Update-AwsPromptIndicatorConfigFromFile

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
                    $config = $script:Config
                    if (-not $config) {
                        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
                    }

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

            Register-AwsCliLogoutWrapper

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

$script:CredentialProfileHelpersLoaded = $false
$script:CredentialProfileHelperPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'scripts\AwsCredentialProfile.ps1'
if (Test-Path $script:CredentialProfileHelperPath) {
    try {
        . $script:CredentialProfileHelperPath
        $helperCmd = Get-Command -Name Invoke-AwsCredentialLogout -CommandType Function -ErrorAction SilentlyContinue
        $script:CredentialProfileHelpersLoaded = $null -ne $helperCmd
    }
    catch {
        Write-Warning "Failed to dot-source credential helpers from $($script:CredentialProfileHelperPath): $_"
    }
}
else {
    Write-Warning "Credential helper script not found at $($script:CredentialProfileHelperPath)"
}

# Export module functions
Export-ModuleMember -Function @(
    'Initialize-AwsPromptIndicator',
    'Get-CurrentAwsAccountId',
    'Get-ExpectedAwsAccountId',
    'Test-AwsAccountMismatch',
    'Get-AwsPromptSegmentData',
    'Get-AwsPromptIndicator',
    'Enable-AwsPromptIndicator',
    'Clear-AwsPromptSessionState',
    'Invoke-AwsConsoleLogout',
    'Reset-AwsPromptIndicatorCache'
)
