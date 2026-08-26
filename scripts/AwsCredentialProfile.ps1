# AwsCredentialProfile.ps1
# Shared helpers for reading/writing named profiles in ~/.aws/credentials
# Used by console.ps1 (login sync) and _test (INI transform tests)

<#
.SYNOPSIS
    Parses an AWS credentials INI document into a profile → key/value map.

.PARAMETER IniText
    Full text of a credentials or config file.

.OUTPUTS
    Hashtable whose keys are profile names and values are hashtables of key → value.
#>
function Get-AwsIniProfileMap {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$IniText
    )

    $profiles = @{}
    $current = $null

    foreach ($line in ($IniText -split "`r?`n")) {
        if ($line -match '^\s*\[([^\]]+)\]\s*$') {
            $current = $Matches[1].Trim()
            if (-not $profiles.ContainsKey($current)) {
                $profiles[$current] = @{}
            }
            continue
        }

        if ($null -eq $current) {
            continue
        }

        if ($line -match '^\s*([^=;#]+?)\s*=\s*(.*)$') {
            $key = $Matches[1].Trim()
            $value = $Matches[2].Trim()
            $profiles[$current][$key] = $value
        }
    }

    return $profiles
}

<#
.SYNOPSIS
    Returns $true when the profile has an x_security_token_expires value in the past.
#>
function Test-AwsIniProfileExpired {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [hashtable]$ProfileKeys
    )

    if (-not $ProfileKeys.ContainsKey("x_security_token_expires")) {
        return $false
    }

    $raw = [string]$ProfileKeys["x_security_token_expires"]
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
    Copies credential keys from one INI profile section into another.

.DESCRIPTION
    Used to keep [default] in sync with the named okta-aws-cli profile so AWS CLI
    and OpenTofu work without --profile. If the source has no expiry field, a
    stale x_security_token_expires on the target is removed.

.PARAMETER IniText
    Full credentials-file text.

.PARAMETER SourceProfile
    Profile that already has fresh credentials.

.PARAMETER TargetProfile
    Profile to update (defaults to "default").

.OUTPUTS
    Updated INI text.
#>
function Update-AwsIniProfileSection {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$IniText,

        [Parameter(Mandatory = $true)]
        [string]$SourceProfile,

        [Parameter(Mandatory = $false)]
        [string]$TargetProfile = "default"
    )

    if ($SourceProfile -eq $TargetProfile) {
        return $IniText
    }

    $profiles = Get-AwsIniProfileMap -IniText $IniText
    if (-not $profiles.ContainsKey($SourceProfile)) {
        throw "Source profile [$SourceProfile] was not found in the credentials file."
    }

    $source = $profiles[$SourceProfile]
    $required = @("aws_access_key_id", "aws_secret_access_key", "aws_session_token")
    foreach ($key in $required) {
        if (-not $source.ContainsKey($key) -or [string]::IsNullOrWhiteSpace([string]$source[$key])) {
            throw "Source profile [$SourceProfile] is missing $key."
        }
    }

    $copyKeys = @("aws_access_key_id", "aws_secret_access_key", "aws_session_token", "x_principal_arn")
    if ($source.ContainsKey("x_security_token_expires") -and -not [string]::IsNullOrWhiteSpace([string]$source["x_security_token_expires"])) {
        $copyKeys += "x_security_token_expires"
    }

    $targetKeys = @{}
    if ($profiles.ContainsKey($TargetProfile)) {
        foreach ($entry in $profiles[$TargetProfile].GetEnumerator()) {
            $targetKeys[$entry.Key] = $entry.Value
        }
    }

    foreach ($key in $copyKeys) {
        if ($source.ContainsKey($key)) {
            $targetKeys[$key] = $source[$key]
        }
    }

    # Named okta-aws-cli profiles often omit expiry. Drop a stale value so
    # readers do not treat fresh keys as expired.
    if ($copyKeys -notcontains "x_security_token_expires") {
        $targetKeys.Remove("x_security_token_expires")
    }

    $usesLf = $IniText.Contains("`n") -and -not $IniText.Contains("`r`n")
    $nl = if ($usesLf) { "`n" } else { "`r`n" }

    $sectionPattern = "(?ms)^\[$([regex]::Escape($TargetProfile))\][^\[]*"
    $newSection = "[$TargetProfile]$nl"
    foreach ($key in @(
            "aws_access_key_id",
            "aws_secret_access_key",
            "aws_session_token",
            "x_security_token_expires",
            "x_principal_arn"
        )) {
        if ($targetKeys.ContainsKey($key)) {
            $newSection += "$key = $($targetKeys[$key])$nl"
            $targetKeys.Remove($key)
        }
    }
    foreach ($entry in ($targetKeys.GetEnumerator() | Sort-Object Name)) {
        $newSection += "$($entry.Key) = $($entry.Value)$nl"
    }

    if ($IniText -match $sectionPattern) {
        $updated = [regex]::Replace($IniText, $sectionPattern, $newSection, 1)
    }
    else {
        $trimmed = $IniText.TrimEnd()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            $updated = $newSection
        }
        else {
            $updated = $trimmed + $nl + $nl + $newSection
        }
    }

    return $updated
}

<#
.SYNOPSIS
    Copies a named AWS profile's credentials onto [default].

.PARAMETER SourceProfile
    Profile written by okta-aws-cli (for example etsnettoolsprod-CFA-OKTA-PROD-Admin).

.PARAMETER CredentialsPath
    Path to the credentials file. Defaults to ~/.aws/credentials.
#>
function Sync-AwsDefaultProfileFrom {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceProfile,

        [Parameter(Mandatory = $false)]
        [string]$CredentialsPath = $(Join-Path $env:USERPROFILE ".aws\credentials")
    )

    if ([string]::IsNullOrWhiteSpace($SourceProfile) -or $SourceProfile -eq "manual" -or $SourceProfile -eq "default") {
        return $false
    }

    if (-not (Test-Path $CredentialsPath)) {
        throw "AWS credentials file not found: $CredentialsPath"
    }

    $original = Get-Content -Path $CredentialsPath -Raw
    $updated = Update-AwsIniProfileSection -IniText $original -SourceProfile $SourceProfile -TargetProfile "default"

    if ($updated -eq $original) {
        return $false
    }

    $backupPath = "$CredentialsPath.backup"
    Copy-Item -Path $CredentialsPath -Destination $backupPath -Force
    Set-Content -Path $CredentialsPath -Value $updated -NoNewline -Encoding utf8

    Write-Host "Synced [$SourceProfile] credentials to [default] for AWS CLI / OpenTofu" -ForegroundColor Gray
    return $true
}
