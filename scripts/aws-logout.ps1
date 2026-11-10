#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Clears local AWS/Okta session state and resets the AWS prompt indicator.

.DESCRIPTION
    okta-aws-cli writes credentials to named profiles (and the console syncs [default]).
    The AWS CLI "aws logout" command only clears its own login-session cache, so running
    it alone can warn that no session exists while stale keys remain and the prompt still
    shows the old account.

    This script clears credential keys from [default] and the active AWS profile (when set),
    runs aws logout for those profiles when available, and resets AWS_DISPLAY_NAME and
    related prompt variables.

.EXAMPLE
    .\aws-logout.ps1

.NOTES
    Part of powershell-console project
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$Profile
)

$ErrorActionPreference = 'Stop'

$consoleRoot = Split-Path $PSScriptRoot -Parent
$credentialScript = Join-Path $PSScriptRoot 'AwsCredentialProfile.ps1'
$modulePath = Join-Path $consoleRoot 'modules\aws-prompt-indicator\AwsPromptIndicator.psm1'

if (Test-Path $credentialScript) {
    . $credentialScript
}

$profileNames = @()
if ($Profile) {
    $profileNames += @($Profile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

if (Get-Command Invoke-AwsCredentialLogout -ErrorAction SilentlyContinue) {
    $null = Invoke-AwsCredentialLogout -ProfileNames $profileNames
}
else {
    Write-Warning "AwsCredentialProfile.ps1 helpers were not loaded; credential file was not updated."
}

if (Test-Path $modulePath) {
    Import-Module $modulePath -Force -DisableNameChecking | Out-Null
    if (Get-Command Clear-AwsPromptSessionState -ErrorAction SilentlyContinue) {
        Clear-AwsPromptSessionState -RefreshPrompt
    }
}
else {
    if (Test-Path -LiteralPath Env:AWS_PROFILE) {
        Remove-Item Env:AWS_PROFILE
    }
    $env:AWS_DISPLAY_NAME = $env:USERNAME
    $env:AWS_ACCOUNT_MISMATCH = 'false'
    $env:AWS_ACCOUNT_MATCH = 'false'
}

Write-Host "AWS session cleared and prompt reset to default." -ForegroundColor Green
